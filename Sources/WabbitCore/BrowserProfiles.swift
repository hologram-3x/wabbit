import Foundation
import GRDB

/// A Browser Profile assigned to a Client (browser-profiles 01): stored by profile folder ("Profile 1"), not name,
/// so renaming the profile in the browser keeps it. Profile names live only in memory, supplied by the shell.
struct BrowserProfile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "browserProfile"
    var bundleID: String
    var folder: String
    var clientId: Int64
}

extension Tracker {
    static func migrateBrowserProfiles(_ db: Database) throws {
        try db.create(table: "browserProfile") { t in
            t.column("bundleID", .text).notNull().references("watchedApp", onDelete: .cascade)
            t.column("folder", .text).notNull()
            t.belongsTo("client", onDelete: .cascade).notNull()
            t.primaryKey(["bundleID", "folder"])
        }
    }

    /// Assigned profiles of one browser: folder → Client id.
    public func browserProfiles(bundleID: String) throws -> [String: Int64] {
        try db.read { db in
            Dictionary(uniqueKeysWithValues: try BrowserProfile.filter(Column("bundleID") == bundleID).fetchAll(db)
                .map { ($0.folder, $0.clientId) })
        }
    }

    /// Assigns the profile in `folder` to a Client, or unassigns it (nil).
    public func setBrowserProfileClient(bundleID: String, folder: String, clientId: Int64?) throws {
        try db.write { db in
            if let clientId { try BrowserProfile(bundleID: bundleID, folder: folder, clientId: clientId).save(db) }
            else { _ = try BrowserProfile.deleteOne(db, key: ["bundleID": bundleID, "folder": folder]) }
        }
    }

    /// The browser's profile names (folder → name), as the shell last read them; nil when they can't be read.
    /// Not persisted.
    public func setBrowserProfileNames(bundleID: String, _ names: [String: String]?) {
        watched.profileNames[bundleID] = names
    }

    /// The folder of the profile whose name ends the window title after " - " (Chromium adds it when a browser
    /// has more than one profile). Page titles contain dashes too, so the title is never split: the longest
    /// matching name wins.
    public static func profileFolder(title: String?, names: [String: String]) -> String? {
        guard let title else { return nil }
        return names.filter { !$0.value.isEmpty && title.hasSuffix(" - " + $0.value) }
            .max { $0.value.count < $1.value.count }?.key
    }

    /// For a browser with at least one assigned profile: `.some(clientId)` when the front window's profile is
    /// assigned to a Client with Open Projects, `.some(nil)` (no prompt) otherwise. `nil`: no assignments, or
    /// the profile names are unknown (an unreadable `Local State` must not silence the browser).
    func profileClient(bundleID: String, title: String?) -> Int64?? {
        guard let assigned = try? browserProfiles(bundleID: bundleID), !assigned.isEmpty,
              let names = watched.profileNames[bundleID] else { return nil }
        let folder = Self.profileFolder(title: title, names: names)
        guard let clientId = folder.flatMap({ assigned[$0] }), lastUsedProject(clientId: clientId) != nil
        else { return .some(nil) }
        return clientId
    }

    /// The Client's Open Project with the latest Session, else its first Open Project by name; nil when none
    /// (or the Client is Closed).
    func lastUsedProject(clientId: Int64) -> Int64? {
        try? db.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT p.id FROM project p JOIN client c ON c.id = p.clientId
                WHERE p.clientId = ? AND p.closedAt IS NULL AND c.closedAt IS NULL
                ORDER BY (SELECT MAX(s.start) FROM session s WHERE s.projectId = p.id) DESC NULLS LAST, p.name
                LIMIT 1
                """, arguments: [clientId])
        }
    }
}
