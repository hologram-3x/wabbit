import Foundation
import GRDB

/// A folder linked to a Project: a Watched App's front document inside it points to that Project.
public struct ProjectFolder: Codable, Equatable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "projectFolder"
    public var id: Int64?
    public var projectId: Int64
    /// Normalised (see `Tracker.normalisedPath`), original case kept for display.
    public var path: String
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum ProjectFolderError: Error, Equatable {
    /// The folder is already linked, to the Project with this id.
    case alreadyLinked(projectId: Int64)
}

extension Tracker {
    static func migrateProjectFolders(_ db: Database) throws {
        try db.create(table: "projectFolder", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.belongsTo("project", onDelete: .cascade).notNull()
            t.column("path", .text).notNull().unique().collate(.nocase)
        }
    }

    /// Expands `~`, standardises, resolves symlinks, drops a trailing slash.
    public static func normalisedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var p = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    public func projectFolders(projectId: Int64) throws -> [ProjectFolder] {
        try db.read { try ProjectFolder.filter(Column("projectId") == projectId).order(Column("path")).fetchAll($0) }
    }

    @discardableResult
    public func addProjectFolder(projectId: Int64, path: String) throws -> ProjectFolder {
        let p = Self.normalisedPath(path)
        return try db.write { db in
            guard try Project.exists(db, key: projectId) else { throw WabbitError.notFound }
            if let other = try ProjectFolder.filter(sql: "path = ? COLLATE NOCASE", arguments: [p]).fetchOne(db) {
                if other.projectId == projectId { return other }
                throw ProjectFolderError.alreadyLinked(projectId: other.projectId)
            }
            var folder = ProjectFolder(id: nil, projectId: projectId, path: p)
            try folder.insert(db)
            return folder
        }
    }

    public func removeProjectFolder(id: Int64) throws { try db.write { _ = try ProjectFolder.deleteOne($0, key: id) } }

    /// The Open Project whose folder contains `path` (deepest folder wins), compared case-insensitively.
    public func projectForDocument(path: String) -> Int64? {
        projectForNormalised(Self.normalisedPath(path).lowercased())
    }

    /// `path` already normalised and lowercased.
    func projectForNormalised(_ path: String) -> Int64? {
        let rows = (try? db.read { try Row.fetchAll($0, sql: """
            SELECT f.projectId, f.path FROM projectFolder f
            JOIN project p ON p.id = f.projectId JOIN client c ON c.id = p.clientId
            WHERE p.closedAt IS NULL AND c.closedAt IS NULL
            """) }) ?? []
        return rows
            .map { (id: $0["projectId"] as Int64, dir: ($0["path"] as String).lowercased()) }
            .filter { path == $0.dir || path.hasPrefix($0.dir.hasSuffix("/") ? $0.dir : $0.dir + "/") }
            .max { $0.dir.count < $1.dir.count }?.id
    }
}
