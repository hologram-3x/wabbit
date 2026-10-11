import Foundation
import GRDB

public struct Client: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var closedAt: Date? = nil
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Project: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var clientId: Int64
    public var name: String
    public var closedAt: Date? = nil
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// One continuous stretch of tracked time. A running Session has no end.
public struct Session: Codable, Equatable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var projectId: Int64
    public var start: Date
    public var end: Date?
    /// Added by hand (ticket 04).
    public var manual: Bool = false
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum HoursError: Error, Equatable {
    case emptyName
    case projectClosed, lastProject, notFound, invalidMoney
    case noPendingIdle
    case invalidRange
    /// The new or edited Session overlaps `Session`; `String` names it (Client / Project, times).
    case sessionOverlap(Session, String)
}

/// The core's public API: commands in, queries out. Tests drive it with a fake clock,
/// a fake detection feed and a real in-memory SQLite database.
public final class Tracker {
    let db: DatabaseQueue
    let clock: WallClock
    let idle = IdleRuntime()
    let meeting = MeetingRuntime()

    /// `path: nil` opens a fresh in-memory database.
    public init(path: String?, clock: WallClock) throws {
        db = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        self.clock = clock
        try Self.migrator.migrate(db)
    }

    /// Versioned schema. Append new migrations; never edit a shipped one.
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "client") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
            }
            try db.create(table: "project") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("client", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
            }
            // No uniqueness on running Sessions: the core enforces one at a time (spec).
            try db.create(table: "session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("project", onDelete: .cascade).notNull()
                t.column("start", .datetime).notNull()
                t.column("end", .datetime)
            }
        }
        registerLifecycleMigration(&m)
        m.registerMigration("v2-idle", migrate: migrateIdle)
        registerMoneyMigration(&m)
        registerManualMigration(&m)
        registerExportMigration(&m)
        return m
    }

    public func connect(_ feed: DetectionFeed) {
        feed.subscribe { [weak self] in self?.handle($0) }
    }

    func handle(_ event: DetectionEvent) {
        handleIdleEvent(event)
        handleMeetingEvent(event)
    }

    // MARK: Commands

    /// A Client can only be created together with its first Project.
    @discardableResult
    public func createClient(name: String, firstProject: String) throws -> (Client, Project) {
        let clientName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = firstProject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientName.isEmpty, !projectName.isEmpty else { throw HoursError.emptyName }
        return try db.write { db in
            var client = Client(name: clientName)
            try client.insert(db)
            var project = Project(clientId: client.id!, name: projectName)
            try project.insert(db)
            return (client, project)
        }
    }

    /// Starts a Session now. A running Session is stopped at the same instant.
    @discardableResult
    public func start(projectId: Int64) throws -> Session {
        let now = clock.now()
        return try db.write { db in
            try Self.requireOpen(db, projectId: projectId)
            try Self.stopRunning(db, at: now)
            var session = Session(projectId: projectId, start: now)
            try session.insert(db)
            return session
        }
    }

    /// Stops the running Session now. Returns it, or nil when nothing was running.
    @discardableResult
    public func stop() throws -> Session? {
        let now = clock.now()
        return try db.write { try Self.stopRunning($0, at: now) }
    }

    @discardableResult
    private static func stopRunning(_ db: Database, at now: Date) throws -> Session? {
        guard var running = try Session.filter(Column("end") == nil).fetchOne(db) else { return nil }
        running.end = now
        try running.update(db)
        return running
    }

    // MARK: Queries

    public func clients() throws -> [Client] {
        try db.read { try Client.order(Column("name")).fetchAll($0) }
    }

    public func projects() throws -> [Project] {
        try db.read { try Project.order(Column("name")).fetchAll($0) }
    }

    public func runningSession() throws -> Session? {
        try db.read { try Session.filter(Column("end") == nil).fetchOne($0) }
    }

    public func sessions(projectId: Int64) throws -> [Session] {
        try db.read { try Session.filter(Column("projectId") == projectId).order(Column("start")).fetchAll($0) }
    }

    /// Exact duration; a running Session counts up to the clock's now.
    public func duration(of session: Session) -> TimeInterval {
        (session.end ?? clock.now()).timeIntervalSince(session.start)
    }
}
