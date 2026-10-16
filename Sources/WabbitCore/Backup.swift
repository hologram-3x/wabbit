import Foundation
import GRDB

public enum BackupError: Error, Equatable {
    /// Not a SQLite file, or missing the Wabbit tables.
    case notABackup
    /// Written by a newer version of the app (has migrations this build doesn't know).
    case newerThanApp
}

extension Tracker {
    /// Writes a consistent single-file copy of the database (SQLite online backup, safe while tracking).
    public func backup(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let dest = try DatabaseQueue(path: url.path)
        try db.backup(to: dest)
    }

    /// Validates `url`, then replaces the current data with it and runs pending migrations.
    /// A safety copy of the current data is restored if anything fails after validation.
    public func restore(from url: URL) throws {
        let source = try Self.openBackup(url)
        let safety = FileManager.default.temporaryDirectory.appending(path: "wabbit-safety-\(UUID().uuidString).sqlite")
        try backup(to: safety)
        defer { try? FileManager.default.removeItem(at: safety) }
        do {
            try source.backup(to: db)
            try Self.migrator.migrate(db)
        } catch {
            if let old = try? DatabaseQueue(path: safety.path) { try? old.backup(to: db) }
            throw error
        }
    }

    /// Opens read-only and checks: it's SQLite, integrity holds, the Wabbit tables exist, no newer migrations.
    static func openBackup(_ url: URL) throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        do {
            let q = try DatabaseQueue(path: url.path, configuration: config)
            try q.read { db in
                guard try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok" else { throw BackupError.notABackup }
                for t in ["client", "project", "session"] where try !db.tableExists(t) { throw BackupError.notABackup }
                if try migrator.hasBeenSuperseded(db) { throw BackupError.newerThanApp }
            }
            return q
        } catch let e as BackupError {
            throw e
        } catch {
            throw BackupError.notABackup
        }
    }
}
