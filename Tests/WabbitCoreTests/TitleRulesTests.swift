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

private func prompt(_ h: Harness, title: String?) -> Int64?? {
    h.feed.emit(.activeAppChanged(bundleID: code, windowTitle: title))
    h.clock.advance(by: 30)
    return h.tracker.pendingWatchedAppPrompt().map(\.projectId)
}

@Test func firstMatchingRuleWinsThenDefault() throws {
    let (h, site, app, other) = try setup()
    try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: "acme", projectId: site.id!)
    try h.tracker.addTitleRule(bundleID: code, kind: .pattern, text: "^acme-.*", projectId: app.id!)
    #expect(prompt(h, title: "acme-site — VS Code") == site.id)
    #expect(prompt(h, title: "nothing") == other.id)
}

@Test func reorderingChangesTheWinner() throws {
    let (h, site, app, _) = try setup()
    try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: "acme", projectId: site.id!)
    let second = try h.tracker.addTitleRule(bundleID: code, kind: .pattern, text: "site$", projectId: app.id!)
    let first = try h.tracker.titleRules(bundleID: code)[0]
    try h.tracker.setTitleRuleOrder(bundleID: code, ids: [second.id!, first.id!])
    #expect(try h.tracker.titleRules(bundleID: code).map(\.id) == [second.id, first.id])
    #expect(prompt(h, title: "acme-site") == app.id)
}

@Test func missingTitleFallsBackToDefault() throws {
    let (h, site, _, other) = try setup()
    try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: "acme", projectId: site.id!)
    #expect(prompt(h, title: nil) == other.id)
}

@Test func titleChangeInSameStayRePicksProjectWithoutResettingDelay() throws {
    let (h, site, _, other) = try setup()
    try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: "acme", projectId: site.id!)
    h.feed.emit(.activeAppChanged(bundleID: code, windowTitle: "misc"))
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == other.id)
    h.feed.emit(.activeAppChanged(bundleID: code, windowTitle: "acme"))
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == site.id)
}

@Test func closedRuleProjectIsSkippedAndBadInputRejected() throws {
    let (h, site, _, other) = try setup()
    try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: "acme", projectId: site.id!)
    try h.tracker.closeProject(id: site.id!)
    #expect(prompt(h, title: "acme") == other.id)
    #expect(throws: TitleRuleError.invalidPattern) { try h.tracker.addTitleRule(bundleID: code, kind: .pattern, text: "(", projectId: other.id!) }
    #expect(throws: TitleRuleError.emptyPattern) { try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: " ", projectId: other.id!) }
    #expect(throws: WabbitError.projectClosed) { try h.tracker.addTitleRule(bundleID: code, kind: .contains, text: "x", projectId: site.id!) }
}
