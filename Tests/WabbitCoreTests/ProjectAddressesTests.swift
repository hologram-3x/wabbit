import Foundation
import Testing
import WabbitCore

private let safari = "com.apple.Safari", terminal = "com.apple.Terminal"

private func setup() throws -> (Harness, Project, Project, Project) {
    let h = try Harness()
    let (client, site) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let app = try h.tracker.addProject(clientId: client.id!, name: "App")
    let other = try h.tracker.addProject(clientId: client.id!, name: "Other")
    try h.tracker.setWatchedApp(bundleID: safari, name: "Safari", projectId: other.id)
    try h.tracker.setWatchedAppDelay(30)
    return (h, site, app, other)
}

@Test func addressesAreNormalised() throws {
    let (h, site, _, _) = try setup()
    try h.tracker.addProjectAddress(projectId: site.id!, address: " HTTPS://www.GitHub.com/acme/site/?tab=x#top ")
    try h.tracker.addProjectAddress(projectId: site.id!, address: "figma.com")
    try h.tracker.addProjectAddress(projectId: site.id!, address: "localhost:3000/")
    #expect(try h.tracker.projectAddresses(projectId: site.id!).map(\.display)
        == ["figma.com", "github.com/acme/site", "localhost:3000"])
    #expect(throws: ProjectAddressError.invalid) { try h.tracker.addProjectAddress(projectId: site.id!, address: "  ") }
}

@Test func hostOnlyHostPathAndLongestPrefixWins() throws {
    let (h, site, app, _) = try setup()
    try h.tracker.addProjectAddress(projectId: site.id!, address: "github.com/acme")
    try h.tracker.addProjectAddress(projectId: app.id!, address: "https://github.com/acme/app")
    try h.tracker.addProjectAddress(projectId: app.id!, address: "figma.com")
    #expect(h.tracker.projectForAddress(url: "https://figma.com/file/123") == app.id)
    #expect(h.tracker.projectForAddress(url: "https://www.figma.com/") == app.id)
    #expect(h.tracker.projectForAddress(url: "https://github.com/acme") == site.id)
    #expect(h.tracker.projectForAddress(url: "https://github.com/acme/site/pulls?q=1") == site.id)
    #expect(h.tracker.projectForAddress(url: "https://github.com/acme/app/issues/1#c") == app.id)
    #expect(h.tracker.projectForAddress(url: "https://github.com/acme/app/") == app.id)
    // Same prefix but a different segment, other hosts, subdomains: no match.
    #expect(h.tracker.projectForAddress(url: "https://github.com/acme-old") == nil)
    #expect(h.tracker.projectForAddress(url: "https://github.com/") == nil)
    #expect(h.tracker.projectForAddress(url: "https://api.figma.com/") == nil)
}

@Test func closedProjectsNeverMatchAnAddress() throws {
    let (h, site, app, _) = try setup()
    try h.tracker.addProjectAddress(projectId: site.id!, address: "github.com/acme")
    try h.tracker.addProjectAddress(projectId: app.id!, address: "github.com/acme/app")
    try h.tracker.closeProject(id: app.id!)
    #expect(h.tracker.projectForAddress(url: "https://github.com/acme/app") == site.id)
}

@Test func sameAddressCannotGoToTwoProjects() throws {
    let (h, site, app, _) = try setup()
    try h.tracker.addProjectAddress(projectId: site.id!, address: "github.com/acme")
    #expect(throws: ProjectAddressError.alreadyLinked(projectId: site.id!)) {
        try h.tracker.addProjectAddress(projectId: app.id!, address: "https://www.github.com/acme/")
    }
}

@Test func addressBeatsDocumentWhichBeatsTitleRulesAndTheDefault() throws {
    let (h, site, app, other) = try setup()
    try h.tracker.addProjectAddress(projectId: site.id!, address: "github.com/acme")
    try h.tracker.addProjectFolder(projectId: app.id!, path: "/work/app")
    try h.tracker.addTitleRule(bundleID: safari, kind: .contains, text: "misc", projectId: other.id!)
    func prompt(_ url: String?, doc: String? = nil, title: String? = nil) -> Int64? {
        h.feed.emit(.activeAppChanged(bundleID: terminal, windowTitle: nil)) // leave, so each check is a fresh stay
        h.feed.emit(.activeAppChanged(bundleID: safari, windowTitle: title, documentPath: doc))
        h.feed.emit(.browserAddress(bundleID: safari, url: url))
        h.clock.advance(by: 60)
        return h.tracker.pendingWatchedAppPrompt()?.projectId
    }
    #expect(prompt("https://github.com/acme/x", doc: "/work/app/a.html", title: "misc") == site.id)
    #expect(prompt("https://example.com", doc: "/work/app/a.html", title: "misc") == app.id)
    #expect(prompt(nil, title: "misc") == other.id)
}

@Test func addressIsForTheFrontAppOnlyAndClearedWhenItLeaves() throws {
    let (h, site, _, other) = try setup()
    try h.tracker.addProjectAddress(projectId: site.id!, address: "github.com/acme")
    try h.tracker.setWatchedApp(bundleID: terminal, name: "Terminal", projectId: other.id)
    h.feed.emit(.activeAppChanged(bundleID: safari, windowTitle: nil))
    h.feed.emit(.browserAddress(bundleID: terminal, url: "https://github.com/acme")) // late answer, not in front
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == other.id)
    h.feed.emit(.browserAddress(bundleID: safari, url: "https://github.com/acme"))
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == site.id)
    h.feed.emit(.activeAppChanged(bundleID: terminal, windowTitle: nil))
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == other.id)
}

@Test func unwatchedBrowserNeverPrompts() throws {
    let (h, site, _, _) = try setup()
    try h.tracker.addProjectAddress(projectId: site.id!, address: "github.com/acme")
    h.feed.emit(.activeAppChanged(bundleID: "com.google.Chrome", windowTitle: nil))
    h.feed.emit(.browserAddress(bundleID: "com.google.Chrome", url: "https://github.com/acme"))
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
}
