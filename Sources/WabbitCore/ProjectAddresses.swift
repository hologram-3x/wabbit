import Foundation
import GRDB

/// A web address linked to a Project (project-folders 03): a Watched browser's front tab under it points to
/// that Project. Stored as host (lowercased, no `www.`, port kept) plus an optional path prefix ("" for none).
/// The tab's own address is only compared in memory, never stored.
public struct ProjectAddress: Codable, Equatable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "projectAddress"
    public var id: Int64?
    public var projectId: Int64
    public var host: String
    /// No trailing slash; "" when the whole host is meant.
    public var path: String
    public var display: String { host + path }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum ProjectAddressError: Error, Equatable {
    case invalid
    /// The address is already linked, to the Project with this id.
    case alreadyLinked(projectId: Int64)
}

extension Tracker {
    static func migrateProjectAddresses(_ db: Database) throws {
        try db.create(table: "projectAddress", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.belongsTo("project", onDelete: .cascade).notNull()
            t.column("host", .text).notNull()
            t.column("path", .text).notNull()
            t.uniqueKey(["host", "path"])
        }
    }

    /// Host and path prefix of a typed or pasted address: scheme, `www.`, query, fragment and trailing
    /// slashes dropped, host lowercased. nil when there is no host.
    public static func normalisedAddress(_ raw: String) -> (host: String, path: String)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let c = URLComponents(string: s), var host = c.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if let port = c.port { host += ":\(port)" }
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        return (host, path)
    }

    public func projectAddresses(projectId: Int64) throws -> [ProjectAddress] {
        try db.read {
            try ProjectAddress.filter(Column("projectId") == projectId).order(Column("host"), Column("path")).fetchAll($0)
        }
    }

    @discardableResult
    public func addProjectAddress(projectId: Int64, address: String) throws -> ProjectAddress {
        guard let (host, path) = Self.normalisedAddress(address) else { throw ProjectAddressError.invalid }
        return try db.write { db in
            guard try Project.exists(db, key: projectId) else { throw WabbitError.notFound }
            if let other = try ProjectAddress.filter(Column("host") == host && Column("path") == path).fetchOne(db) {
                if other.projectId == projectId { return other }
                throw ProjectAddressError.alreadyLinked(projectId: other.projectId)
            }
            var a = ProjectAddress(id: nil, projectId: projectId, host: host, path: path)
            try a.insert(db)
            return a
        }
    }

    public func removeProjectAddress(id: Int64) throws { try db.write { _ = try ProjectAddress.deleteOne($0, key: id) } }

    /// The Open Project whose address is the longest prefix of `url`.
    public func projectForAddress(url: String) -> Int64? {
        Self.normalisedAddress(url).flatMap(projectForNormalisedAddress)
    }

    func projectForNormalisedAddress(_ a: (host: String, path: String)) -> Int64? {
        let rows = (try? db.read { try Row.fetchAll($0, sql: """
            SELECT a.projectId, a.path FROM projectAddress a
            JOIN project p ON p.id = a.projectId JOIN client c ON c.id = p.clientId
            WHERE a.host = ? AND p.closedAt IS NULL AND c.closedAt IS NULL
            """, arguments: [a.host]) }) ?? []
        return rows
            .map { (id: $0["projectId"] as Int64, path: $0["path"] as String) }
            .filter { a.path == $0.path || a.path.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }?.id
    }

    func handleBrowserAddress(_ event: DetectionEvent) {
        guard case .browserAddress(let id, let url) = event, id == watched.front else { return }
        watched.address = url.flatMap(Self.normalisedAddress)
    }
}
