import Foundation
import GRDB

extension Tracker {
    /// Top `limit` Open Projects for Quick Start. "Recent use" = the latest Session start on the
    /// Project (manual and running Sessions count). Ties, and Projects never used, order by
    /// name then id, so the result is deterministic.
    public func quickStartProjects(limit: Int = 5) throws -> [Project] {
        let open = try openProjects()
        let last: [Int64: Date] = try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT projectId, MAX(start) AS s FROM session GROUP BY projectId")
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["projectId"] as Int64, $0["s"] as Date) })
        }
        let sorted = open.sorted { a, b in
            let (la, lb) = (last[a.id!], last[b.id!])
            if la != lb { return (la ?? .distantPast) > (lb ?? .distantPast) }
            if a.name != b.name { return a.name < b.name }
            return a.id! < b.id!
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}
