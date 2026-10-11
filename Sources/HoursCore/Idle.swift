import Foundation
import GRDB

/// Idle Threshold bounds (spec: 5 min–1 h).
public enum IdleThreshold {
    public static let minimum: TimeInterval = 5 * 60
    public static let maximum: TimeInterval = 60 * 60
    public static let defaultSeconds: TimeInterval = 15 * 60

    public static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, minimum), maximum)
    }
}

/// Pending Idle resolution after the freelancer returns (spec: Keep / Discard / Split).
public struct IdlePrompt: Equatable, Sendable {
    public let sessionId: Int64
    public let projectId: Int64
    public let idleStart: Date
    public let idleEnd: Date
}

public enum IdleResolution: Equatable, Sendable {
    case keep
    case discard
    case split
}

public enum IdleResolveResult: Equatable, Sendable {
    case kept
    case discarded(Session)
    /// `work` ended at idle start; `idle` covers the idle stretch; `resumed` is the new running Session.
    case split(work: Session, idle: Session, resumed: Session)
}

/// In-memory Idle observation for the running Session. Not persisted (re-detected after relaunch).
final class IdleRuntime {
    var observedIdleStart: Date?
    var observedSessionId: Int64?
    var pending: IdlePrompt?

    func clearObservation() {
        observedIdleStart = nil
        observedSessionId = nil
    }

    func clearAll() {
        clearObservation()
        pending = nil
    }
}

extension Tracker {
    static let idleThresholdKey = "idleThresholdSeconds"

    static func migrateIdle(_ db: Database) throws {
        try db.create(table: "setting") { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text).notNull()
        }
        try db.execute(
            sql: "INSERT INTO setting (key, value) VALUES (?, ?)",
            arguments: [idleThresholdKey, String(Int(IdleThreshold.defaultSeconds))]
        )
    }

    // MARK: Settings

    public func idleThreshold() throws -> TimeInterval {
        let raw = try db.read { db -> String? in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM setting WHERE key = ?",
                arguments: [Self.idleThresholdKey]
            )
        }
        let seconds = raw.flatMap(TimeInterval.init(_:)) ?? IdleThreshold.defaultSeconds
        return IdleThreshold.clamp(seconds)
    }

    public func setIdleThreshold(_ seconds: TimeInterval) throws {
        let clamped = IdleThreshold.clamp(seconds)
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO setting (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [Self.idleThresholdKey, String(Int(clamped.rounded()))]
            )
        }
    }

    // MARK: Queries / commands

    public func pendingIdlePrompt() -> IdlePrompt? { idle.pending }

    /// Applies Keep, Discard or Split to the pending Idle prompt.
    @discardableResult
    public func resolveIdle(_ resolution: IdleResolution) throws -> IdleResolveResult {
        guard let prompt = idle.pending else { throw HoursError.noPendingIdle }
        let result: IdleResolveResult = try db.write { db in
            switch resolution {
            case .keep:
                return .kept
            case .discard:
                let ended = try Self.endSession(db, id: prompt.sessionId, at: prompt.idleStart)
                return .discarded(ended)
            case .split:
                let work = try Self.endSession(db, id: prompt.sessionId, at: prompt.idleStart)
                var idleSession = Session(
                    projectId: prompt.projectId,
                    start: prompt.idleStart,
                    end: prompt.idleEnd
                )
                try idleSession.insert(db)
                var resumed = Session(projectId: prompt.projectId, start: prompt.idleEnd)
                try resumed.insert(db)
                return .split(work: work, idle: idleSession, resumed: resumed)
            }
        }
        idle.clearAll()
        return result
    }

    /// Drops a finished Session (used for the Split idle stretch).
    public func dropSession(id: Int64) throws {
        try db.write { db in
            _ = try Session.deleteOne(db, key: id)
        }
    }

    /// Reassigns a finished Session to another Project (Split idle stretch).
    public func assignSession(id: Int64, toProjectId projectId: Int64) throws {
        try db.write { db in
            guard var session = try Session.fetchOne(db, key: id) else { return }
            session.projectId = projectId
            try session.update(db)
        }
    }

    func handleIdleEvent(_ event: DetectionEvent) {
        switch event {
        case .userIdle(let since):
            observeIdle(since: since)
        case .userActive:
            becomeActive()
        default:
            break
        }
    }

    private func observeIdle(since: Date) {
        guard idle.pending == nil else { return }
        guard let running = try? runningSession(), let sessionId = running.id else {
            idle.clearObservation()
            return
        }
        // Idle that began before the Session is not "during" it.
        let idleStart = max(since, running.start)
        let threshold = (try? idleThreshold()) ?? IdleThreshold.defaultSeconds
        guard clock.now().timeIntervalSince(idleStart) >= threshold else { return }
        idle.observedIdleStart = idleStart
        idle.observedSessionId = sessionId
    }

    private func becomeActive() {
        defer { idle.clearObservation() }
        guard idle.pending == nil else { return }
        guard let idleStart = idle.observedIdleStart,
              let sessionId = idle.observedSessionId,
              let running = try? runningSession(),
              running.id == sessionId
        else { return }
        let threshold = (try? idleThreshold()) ?? IdleThreshold.defaultSeconds
        let now = clock.now()
        guard now.timeIntervalSince(idleStart) >= threshold else { return }
        idle.pending = IdlePrompt(
            sessionId: sessionId,
            projectId: running.projectId,
            idleStart: idleStart,
            idleEnd: now
        )
    }

    private static func endSession(_ db: Database, id: Int64, at end: Date) throws -> Session {
        guard var session = try Session.fetchOne(db, key: id) else {
            throw HoursError.noPendingIdle
        }
        session.end = end
        try session.update(db)
        return session
    }
}
