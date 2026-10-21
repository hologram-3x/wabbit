import Foundation
import Testing
import WabbitCore

private let terminal = "com.apple.Terminal", code = "com.microsoft.VSCode"

/// Two real folders (signals must be existing directories): a/ for Website, b/ for App; Other is Terminal's default.
private func setup(enabled: Bool = true) throws -> (Harness, URL, Project, Project, Project) {
    let h = try Harness()
    let (client, site) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let app = try h.tracker.addProject(clientId: client.id!, name: "App")
    let other = try h.tracker.addProject(clientId: client.id!, name: "Other")
    let base = FileManager.default.temporaryDirectory.appending(path: "wabbit-signals-\(UUID().uuidString)")
    for d in ["a", "b"] { try FileManager.default.createDirectory(at: base.appending(path: d), withIntermediateDirectories: true) }
    try h.tracker.addProjectFolder(projectId: site.id!, path: base.appending(path: "a").path)
    try h.tracker.addProjectFolder(projectId: app.id!, path: base.appending(path: "b").path)
    for id in [terminal, code] { try h.tracker.setWatchedApp(bundleID: id, name: id, projectId: other.id) }
    try h.tracker.setWatchedAppDelay(30)
    try h.tracker.setFolderSignalsEnabled(enabled)
    return (h, base, site, app, other)
}

private func front(_ h: Harness, _ id: String = terminal, doc: String? = nil) -> Int64? {
    h.feed.emit(.activeAppChanged(bundleID: id, windowTitle: nil, documentPath: doc))
    h.clock.advance(by: 30)
    return h.tracker.pendingWatchedAppPrompt()?.projectId
}

@Test func freshSignalBeatsTheDocumentAndNewestWins() throws {
    let (h, base, site, app, _) = try setup()
    defer { try? FileManager.default.removeItem(at: base) }
    h.feed.emit(.folderSignal(path: base.appending(path: "a").path + "\n"))
    #expect(front(h, doc: base.appending(path: "b/x.txt").path) == site.id)
    h.feed.emit(.folderSignal(path: base.appending(path: "b").path))
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == app.id)
}

@Test func signalsExpireAfterFiveMinutes() throws {
    let (h, base, site, app, _) = try setup()
    defer { try? FileManager.default.removeItem(at: base) }
    h.feed.emit(.folderSignal(path: base.appending(path: "a").path))
    #expect(front(h, doc: base.appending(path: "b").path) == site.id)
    h.clock.advance(by: Tracker.folderSignalLifetime)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == app.id)
}

@Test func signalsOnlyRefineTerminals() throws {
    let (h, base, _, _, other) = try setup()
    defer { try? FileManager.default.removeItem(at: base) }
    h.feed.emit(.folderSignal(path: base.appending(path: "a").path))
    #expect(front(h, code) == other.id)
    #expect(front(h, "com.apple.TextEdit") == nil) // not watched: never prompts
}

@Test func signalsAreIgnoredWhenOffAndDroppedWhenTurnedOff() throws {
    let (h, base, site, _, other) = try setup(enabled: false)
    defer { try? FileManager.default.removeItem(at: base) }
    #expect(try !h.tracker.folderSignalsEnabled())
    h.feed.emit(.folderSignal(path: base.appending(path: "a").path))
    #expect(front(h) == other.id)
    try h.tracker.setFolderSignalsEnabled(true)
    h.feed.emit(.folderSignal(path: base.appending(path: "a").path))
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == site.id)
    try h.tracker.setFolderSignalsEnabled(false)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == other.id)
}

@Test func signalInputIsValidated() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "wabbit-signals-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "f.txt")
    FileManager.default.createFile(atPath: file.path, contents: Data())
    #expect(Tracker.validFolderSignal(dir.path + "\n") == dir.path)
    #expect(Tracker.validFolderSignal("relative/path") == nil)
    #expect(Tracker.validFolderSignal(file.path) == nil)
    #expect(Tracker.validFolderSignal(dir.path + "/missing") == nil)
    #expect(Tracker.validFolderSignal("/" + String(repeating: "a", count: 2000)) == nil)
    #expect(Tracker.validFolderSignal("") == nil)
}

@Test func herdrSnapshotGivesTheFocusedPanesFolder() {
    let json = """
        {"id":"cli:api:snapshot","result":{"type":"session_snapshot","snapshot":{"focused_pane_id":"w0:pB","panes":[
          {"pane_id":"wY:p1","cwd":"/Users/nic","foreground_cwd":"/Users/nic","focused":false},
          {"pane_id":"w0:pB","cwd":"/work/acme","foreground_cwd":null,"focused":true},
          {"pane_id":"w0:pC","cwd":"/work/x","foreground_cwd":"/work/x/sub","focused":false}]}}}
        """
    #expect(HerdrSnapshot.focusedFolder(Data(json.utf8)) == "/work/acme")
    let fg = json.replacingOccurrences(of: "\"focused_pane_id\":\"w0:pB\"", with: "\"focused_pane_id\":\"w0:pC\"")
    #expect(HerdrSnapshot.focusedFolder(Data(fg.utf8)) == "/work/x/sub")
    #expect(HerdrSnapshot.focusedFolder(Data("not json".utf8)) == nil)
}
