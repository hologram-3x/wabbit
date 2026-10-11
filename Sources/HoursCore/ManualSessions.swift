import Foundation
import GRDB

/// Manual Sessions: add, edit, delete by hand. Overlaps are rejected; a Session belongs to the day it started.
func registerManualMigration(_ m: inout DatabaseMigrator) {
    m.registerMigration("v4-manual") { db in
        try db.alter(table: "session") { $0.add(column: "manual", .boolean).notNull().defaults(to: false) }
    }
}

extension Tracker {
    /// Adds a finished Session by hand, marked Manual. Closed Projects reject it.
    @discardableResult
    public func addManualSession(projectId: Int64, start: Date, end: Date) throws -> Session {
        try db.write { db in
            try Self.requireOpen(db, projectId: projectId)
            try self.checkNoOverlap(db, start: start, end: end, excluding: nil)
            var s = Session(projectId: projectId, start: start, end: end, manual: true)
            try s.insert(db)
            return s
        }
    }

    /// Edits a finished Session (any Session, Manual or tracked); its Manual flag is kept.
    @discardableResult
    public func editSession(id: Int64, projectId: Int64, start: Date, end: Date) throws -> Session {
        try db.write { db in
            guard var s = try Session.fetchOne(db, key: id), s.end != nil else { throw HoursError.notFound }
            try Self.requireOpen(db, projectId: projectId)
            try self.checkNoOverlap(db, start: start, end: end, excluding: id)
            s.projectId = projectId
            s.start = start
            s.end = end
            try s.update(db)
            return s
        }
    }

    /// Deletes a finished Session (the running one is stopped, not deleted).
    public func deleteSession(id: Int64) throws {
        try db.write { db in
            guard let s = try Session.fetchOne(db, key: id), s.end != nil else { throw HoursError.notFound }
            try s.delete(db)
        }
    }

    /// Sessions that started on `day`, oldest first.
    public func sessions(onDay day: Date, calendar: Calendar = .current) throws -> [Session] {
        let from = calendar.startOfDay(for: day)
        guard let to = calendar.date(byAdding: .day, value: 1, to: from) else { return [] }
        return try db.read { try Session.filter(Column("start") >= from && Column("start") < to).order(Column("start")).fetchAll($0) }
    }

    /// Every Session, newest first.
    public func allSessions() throws -> [Session] {
        try db.read { try Session.order(Column("start").desc).fetchAll($0) }
    }

    /// A running Session counts as ending now. Touching edges are not an overlap.
    private func checkNoOverlap(_ db: Database, start: Date, end: Date, excluding id: Int64?) throws {
        guard end > start else { throw HoursError.invalidRange }
        let now = clock.now()
        for other in try Session.fetchAll(db) where other.id != id {
            if other.start < end && (other.end ?? now) > start {
                let p = try Project.fetchOne(db, key: other.projectId)
                let c = try p.flatMap { try Client.fetchOne(db, key: $0.clientId) }
                let f = Date.FormatStyle(date: .abbreviated, time: .shortened)
                let label = "\(c?.name ?? "?") / \(p?.name ?? "?"), \(other.start.formatted(f)) to \(other.end.map { $0.formatted(f) } ?? "now")"
                throw HoursError.sessionOverlap(other, label)
            }
        }
    }
}
