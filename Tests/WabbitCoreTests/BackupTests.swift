import Foundation
import GRDB
import Testing
@testable import WabbitCore

private func tmp(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "hours-test-\(name).sqlite")
}

@Test func backupRoundTripRestoresIdenticalData() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 600)
    try h.tracker.stop()
    let file = tmp(); defer { try? FileManager.default.removeItem(at: file) }
    try h.tracker.backup(to: file)

    // Change data afterwards, then restore into a different Tracker.
    try h.tracker.createClient(name: "Other", firstProject: "X")
    let h2 = try Harness()
    try h2.tracker.createClient(name: "Junk", firstProject: "J")
    try h2.tracker.restore(from: file)

    #expect(try h2.tracker.clients() == [c])
    #expect(try h2.tracker.projects() == [p])
    #expect(try h2.tracker.sessions(projectId: p.id!) == (try h.tracker.sessions(projectId: p.id!)))
    #expect(try h.tracker.clients().count == 2)
}

@Test func invalidFileIsRejectedAndDataUntouched() throws {
    let h = try Harness()
    let (c, _) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let junk = tmp(); defer { try? FileManager.default.removeItem(at: junk) }
    try Data("not a database".utf8).write(to: junk)
    #expect(throws: BackupError.notABackup) { try h.tracker.restore(from: junk) }

    // Valid SQLite but not Wabbit.
    let other = tmp(); defer { try? FileManager.default.removeItem(at: other) }
    try DatabaseQueue(path: other.path).write { try $0.execute(sql: "CREATE TABLE foo(x)") }
    #expect(throws: BackupError.notABackup) { try h.tracker.restore(from: other) }

    // Newer than this app.
    let newer = tmp(); defer { try? FileManager.default.removeItem(at: newer) }
    try h.tracker.backup(to: newer)
    try DatabaseQueue(path: newer.path).write {
        try $0.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v99-future')")
    }
    #expect(throws: BackupError.newerThanApp) { try h.tracker.restore(from: newer) }

    #expect(try h.tracker.clients() == [c])
}

@Test func olderSchemaBackupIsMigratedOnRestore() throws {
    // Build a v1-only database with data.
    let old = tmp(); defer { try? FileManager.default.removeItem(at: old) }
    let q = try DatabaseQueue(path: old.path)
    var m = DatabaseMigrator()
    m.registerMigration("v1") { db in
        try db.create(table: "client") { t in t.autoIncrementedPrimaryKey("id"); t.column("name", .text).notNull() }
        try db.create(table: "project") { t in
            t.autoIncrementedPrimaryKey("id"); t.belongsTo("client", onDelete: .cascade).notNull(); t.column("name", .text).notNull()
        }
        try db.create(table: "session") { t in
            t.autoIncrementedPrimaryKey("id"); t.belongsTo("project", onDelete: .cascade).notNull()
            t.column("start", .datetime).notNull(); t.column("end", .datetime)
        }
        try db.execute(sql: "INSERT INTO client(name) VALUES ('Legacy')")
        try db.execute(sql: "INSERT INTO project(clientId, name) VALUES (1, 'Old')")
    }
    try m.migrate(q)

    let h = try Harness()
    try h.tracker.restore(from: old)
    #expect(try h.tracker.clients().map(\.name) == ["Legacy"])
    // Newer-schema features work: pending migrations ran.
    #expect(try h.tracker.roundingStep() == 3600)
    try h.tracker.start(projectId: try h.tracker.projects()[0].id!)
}
