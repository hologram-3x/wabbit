import Foundation
import GRDB

/// Client and Project lifecycle: rename, Close, Reopen, remove, email domains.
/// A Project is Closed when it, or its Client, has a `closedAt`.
/// Defaults (spec is silent): the last Open Project of an Open Client can be neither
/// removed nor Closed; Closing a Client archives it as a whole and needs no such check.
func registerLifecycleMigration(_ m: inout DatabaseMigrator) {
    m.registerMigration("v2-lifecycle") { db in
        try db.alter(table: "client") { $0.add(column: "closedAt", .datetime) }
        try db.alter(table: "project") { $0.add(column: "closedAt", .datetime) }
        try db.create(table: "clientDomain") { t in
            t.belongsTo("client", onDelete: .cascade).notNull()
            t.column("domain", .text).notNull()
            t.primaryKey(["clientId", "domain"])
        }
    }
}

extension Tracker {
    // MARK: The single "can this Project take time?" rule (ticket 04 calls this for Manual Sessions)

    static func requireOpen(_ db: Database, projectId: Int64) throws {
        guard let p = try Project.fetchOne(db, key: projectId) else { throw WabbitError.notFound }
        let client = try Client.fetchOne(db, key: p.clientId)
        if p.closedAt != nil || client?.closedAt != nil { throw WabbitError.projectClosed }
    }

    public func requireOpen(projectId: Int64) throws {
        try db.read { try Self.requireOpen($0, projectId: projectId) }
    }

    // MARK: Commands

    public func renameClient(id: Int64, to name: String) throws {
        let n = try Self.trimmed(name)
        try db.write { try $0.execute(sql: "UPDATE client SET name = ? WHERE id = ?", arguments: [n, id]) }
    }

    public func renameProject(id: Int64, to name: String) throws {
        let n = try Self.trimmed(name)
        try db.write { try $0.execute(sql: "UPDATE project SET name = ? WHERE id = ?", arguments: [n, id]) }
    }

    /// Closing stops the Project's running Session first.
    public func closeProject(id: Int64) throws {
        let now = clock.now()
        try db.write { db in
            guard let p = try Project.fetchOne(db, key: id) else { throw WabbitError.notFound }
            if p.closedAt != nil { return }
            if try Self.openProjectCount(db, clientId: p.clientId) <= 1 { throw WabbitError.lastProject }
            try Self.stopRunning(db, ifProject: id, at: now)
            try db.execute(sql: "UPDATE project SET closedAt = ? WHERE id = ?", arguments: [now, id])
        }
    }

    public func reopenProject(id: Int64) throws {
        try db.write { try $0.execute(sql: "UPDATE project SET closedAt = NULL WHERE id = ?", arguments: [id]) }
    }

    /// Archives the Client and, by extension, all its Projects.
    public func closeClient(id: Int64) throws {
        let now = clock.now()
        try db.write { db in
            for p in try Project.filter(Column("clientId") == id).fetchAll(db) {
                try Self.stopRunning(db, ifProject: p.id!, at: now)
            }
            try db.execute(sql: "UPDATE client SET closedAt = ? WHERE id = ? AND closedAt IS NULL", arguments: [now, id])
        }
    }

    public func reopenClient(id: Int64) throws {
        try db.write { try $0.execute(sql: "UPDATE client SET closedAt = NULL WHERE id = ?", arguments: [id]) }
    }

    /// Adds a Project to an existing Client.
    @discardableResult
    public func addProject(clientId: Int64, name: String) throws -> Project {
        let n = try Self.trimmed(name)
        return try db.write { db in
            var p = Project(clientId: clientId, name: n, color: try Self.pickColor(db))
            try p.insert(db)
            try Self.applyDefaultRate(db, to: p)
            return p
        }
    }

    /// Removes a Project and its Sessions; refused for a Client's last Project.
    public func removeProject(id: Int64) throws {
        try db.write { db in
            guard let p = try Project.fetchOne(db, key: id) else { throw WabbitError.notFound }
            if try Project.filter(Column("clientId") == p.clientId).fetchCount(db) <= 1 { throw WabbitError.lastProject }
            if p.closedAt == nil, try Self.openProjectCount(db, clientId: p.clientId) <= 1 { throw WabbitError.lastProject }
            try p.delete(db)
        }
    }

    public func addDomain(clientId: Int64, _ domain: String) throws {
        let d = try Self.trimmed(domain).lowercased().drop { $0 == "@" }
        try db.write { try $0.execute(sql: "INSERT OR IGNORE INTO clientDomain (clientId, domain) VALUES (?, ?)", arguments: [clientId, String(d)]) }
    }

    public func removeDomain(clientId: Int64, _ domain: String) throws {
        try db.write { try $0.execute(sql: "DELETE FROM clientDomain WHERE clientId = ? AND domain = ?", arguments: [clientId, domain.lowercased()]) }
    }

    // MARK: Queries

    public func domains(clientId: Int64) throws -> [String] {
        try db.read { try String.fetchAll($0, sql: "SELECT domain FROM clientDomain WHERE clientId = ? ORDER BY domain", arguments: [clientId]) }
    }

    /// Projects that can take time: Open, under an Open Client. Feeds the tray and prompts.
    public func openProjects() throws -> [Project] {
        try projects().filter { p in try !isClosed(p) }
    }

    /// Closed Projects, for the Overview and Export.
    public func closedProjects() throws -> [Project] {
        try projects().filter { p in try isClosed(p) }
    }

    public func isClosed(_ p: Project) throws -> Bool {
        try db.read { db in
            if p.closedAt != nil { return true }
            return try Client.fetchOne(db, key: p.clientId)?.closedAt != nil
        }
    }

    // MARK: Helpers

    private static func trimmed(_ s: String) throws -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { throw WabbitError.emptyName }
        return t
    }

    private static func openProjectCount(_ db: Database, clientId: Int64) throws -> Int {
        try Project.filter(Column("clientId") == clientId && Column("closedAt") == nil).fetchCount(db)
    }

    private static func stopRunning(_ db: Database, ifProject id: Int64, at now: Date) throws {
        guard var running = try Session.filter(Column("end") == nil && Column("projectId") == id).fetchOne(db) else { return }
        try finish(db, &running, at: now)
    }
}
