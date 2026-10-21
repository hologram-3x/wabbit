import Foundation
import Testing
import WabbitCore

private let code = "com.microsoft.VSCode"

private func setup() throws -> (Harness, Project, Project, Project) {
    let h = try Harness()
    let (client, site) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let app = try h.tracker.addProject(clientId: client.id!, name: "App")
    let other = try h.tracker.addProject(clientId: client.id!, name: "Other")
    try h.tracker.setWatchedApp(bundleID: code, name: "VS Code", projectId: other.id)
    try h.tracker.setWatchedAppDelay(30)
    return (h, site, app, other)
}

private func prompt(_ h: Harness, _ id: String = code, title: String? = nil, doc: String?) -> WatchedAppPrompt? {
    h.feed.emit(.activeAppChanged(bundleID: id, windowTitle: title, documentPath: doc))
    h.clock.advance(by: 30)
    return h.tracker.pendingWatchedAppPrompt()
}

@Test func deepestFolderWinsAndTrailingSlashTildeAndCaseAreIgnored() throws {
    let (h, site, app, _) = try setup()
    try h.tracker.addProjectFolder(projectId: site.id!, path: "~/DEV/acme/")
    try h.tracker.addProjectFolder(projectId: app.id!, path: "~/DEV/acme/app")
    let home = NSHomeDirectory()
    #expect(try h.tracker.projectFolders(projectId: site.id!).map(\.path) == ["\(home)/DEV/acme"])
    #expect(h.tracker.projectForDocument(path: "\(home)/DEV/acme/readme.md") == site.id)
    #expect(h.tracker.projectForDocument(path: "\(home)/DEV/acme") == site.id)
    #expect(h.tracker.projectForDocument(path: "\(home)/dev/ACME/App/src/x.swift") == app.id)
    #expect(h.tracker.projectForDocument(path: "~/DEV/acme/app/") == app.id)
    // A sibling with the same prefix is not inside.
    #expect(h.tracker.projectForDocument(path: "\(home)/DEV/acme-old/x") == nil)
}

@Test func symlinksAreResolved() throws {
    let (h, site, _, _) = try setup()
    let base = FileManager.default.temporaryDirectory.appending(path: "wabbit-folders-\(UUID().uuidString)")
    let real = base.appending(path: "real"), link = base.appending(path: "link")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    defer { try? FileManager.default.removeItem(at: base) }
    try h.tracker.addProjectFolder(projectId: site.id!, path: link.path)
    FileManager.default.createFile(atPath: real.appending(path: "a.txt").path, contents: Data())
    #expect(h.tracker.projectForDocument(path: real.appending(path: "a.txt").path) == site.id)
    #expect(h.tracker.projectForDocument(path: link.appending(path: "a.txt").path) == site.id)
}

@Test func closedProjectsNeverMatch() throws {
    let (h, site, app, _) = try setup()
    try h.tracker.addProjectFolder(projectId: site.id!, path: "/work/acme")
    try h.tracker.addProjectFolder(projectId: app.id!, path: "/work/acme/app")
    try h.tracker.closeProject(id: app.id!)
    #expect(h.tracker.projectForDocument(path: "/work/acme/app/x") == site.id)
}

@Test func sameFolderCannotGoToTwoProjects() throws {
    let (h, site, app, _) = try setup()
    try h.tracker.addProjectFolder(projectId: site.id!, path: "/work/acme")
    #expect(throws: ProjectFolderError.alreadyLinked(projectId: site.id!)) {
        try h.tracker.addProjectFolder(projectId: app.id!, path: "/Work/ACME/")
    }
}

@Test func documentBeatsTitleRulesWhichBeatTheDefault() throws {
    let (h, site, app, other) = try setup()
    try h.tracker.addProjectFolder(projectId: site.id!, path: "/work/acme")
    try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: "app", projectId: app.id!)
    #expect(prompt(h, title: "app", doc: "/work/acme/index.html")?.projectId == site.id)
    #expect(prompt(h, title: "app", doc: "/elsewhere/x")?.projectId == app.id)
    #expect(prompt(h, title: "misc", doc: nil)?.projectId == other.id)
}

@Test func unwatchedAppWithMatchingDocumentNeverPrompts() throws {
    let (h, site, _, _) = try setup()
    try h.tracker.addProjectFolder(projectId: site.id!, path: "/work/acme")
    #expect(prompt(h, "com.apple.TextEdit", doc: "/work/acme/notes.txt") == nil)
}

@Test func foldersAreRemovedAndGoWithTheProject() throws {
    let (h, site, app, _) = try setup()
    let f = try h.tracker.addProjectFolder(projectId: site.id!, path: "/work/acme")
    try h.tracker.addProjectFolder(projectId: app.id!, path: "/work/app")
    try h.tracker.removeProjectFolder(id: f.id!)
    #expect(try h.tracker.projectFolders(projectId: site.id!).isEmpty)
    try h.tracker.removeProject(id: app.id!)
    #expect(h.tracker.projectForDocument(path: "/work/app/x") == nil)
}

@Test func foldersPersistAndAreInBackups() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "wabbit-folders-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbPath = dir.appending(path: "db.sqlite").path, backup = dir.appending(path: "backup.sqlite")
    let projectId: Int64
    do {
        let h = try Harness(path: dbPath)
        let (_, site) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
        projectId = site.id!
        try h.tracker.addProjectFolder(projectId: projectId, path: "/work/acme")
        try h.tracker.backup(to: backup)
    }
    #expect(try Harness(path: dbPath).tracker.projectFolders(projectId: projectId).map(\.path) == ["/work/acme"])
    let fresh = try Harness()
    try fresh.tracker.restore(from: backup)
    #expect(try fresh.tracker.projectFolders(projectId: projectId).map(\.path) == ["/work/acme"])
}
