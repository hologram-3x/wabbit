import Foundation
import Testing
import WabbitCore

private let helium = "net.imput.helium", terminal = "com.apple.Terminal"
private let names = ["Default": "Nic", "Profile 1": "OpenCom", "Profile 3": "Kipo"]

/// OpenCom (Site, Admin) and Kipo (Shop); the browser's default Project is Kipo's Shop.
private struct Setup {
    let h: Harness
    let openCom: Client, kipo: Client
    let site: Project, admin: Project, shop: Project
}

private func setup() throws -> Setup {
    let h = try Harness()
    let (openCom, site) = try h.tracker.createClient(name: "OpenCom", firstProject: "Site")
    let admin = try h.tracker.addProject(clientId: openCom.id!, name: "Admin")
    let (kipo, shop) = try h.tracker.createClient(name: "Kipo", firstProject: "Shop")
    try h.tracker.setWatchedApp(bundleID: helium, name: "Helium", projectId: shop.id)
    try h.tracker.setWatchedAppDelay(30)
    h.tracker.setBrowserProfileNames(bundleID: helium, names)
    return Setup(h: h, openCom: openCom, kipo: kipo, site: site, admin: admin, shop: shop)
}

/// A fresh stay in Helium with this window title (and address), then the prompt's Project; nil when no prompt.
private func prompt(_ h: Harness, _ title: String?, url: String? = nil) -> Int64?? {
    h.feed.emit(.activeAppChanged(bundleID: terminal, windowTitle: nil))
    h.feed.emit(.activeAppChanged(bundleID: helium, windowTitle: title))
    if let url { h.feed.emit(.browserAddress(bundleID: helium, url: url)) }
    h.clock.advance(by: 60)
    return h.tracker.pendingWatchedAppPrompt().map(\.projectId)
}

@Test func profileIsTheTitlesEndMatchedAgainstKnownNames() {
    #expect(Tracker.profileFolder(title: "Example Domain - Helium - Kipo", names: names) == "Profile 3")
    // Page titles with dashes, and a page title that ends with another profile's name.
    #expect(Tracker.profileFolder(title: "a - b - Nic - Helium - OpenCom", names: names) == "Profile 1")
    #expect(Tracker.profileFolder(title: "Example Domain - Helium", names: names) == nil)
    #expect(Tracker.profileFolder(title: "Kipo", names: names) == nil)
    #expect(Tracker.profileFolder(title: nil, names: names) == nil)
    // A name that is a suffix of another: the longest match wins.
    let nested = ["Profile 1": "Kipo", "Profile 2": "Acme - Kipo", "Profile 3": "Mr Kipo"]
    #expect(Tracker.profileFolder(title: "Page - Helium - Acme - Kipo", names: nested) == "Profile 2")
    #expect(Tracker.profileFolder(title: "Page - Helium - Kipo", names: nested) == "Profile 1")
    #expect(Tracker.profileFolder(title: "Page - Helium - Mr Kipo", names: nested) == "Profile 3")
}

@Test func assignmentsAreStoredPerBrowserAndFolder() throws {
    let s = try setup()
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 1", clientId: s.openCom.id)
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 3", clientId: s.kipo.id)
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 3", clientId: s.openCom.id)
    #expect(try s.h.tracker.browserProfiles(bundleID: helium)
        == ["Profile 1": s.openCom.id!, "Profile 3": s.openCom.id!])
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 3", clientId: nil)
    #expect(try s.h.tracker.browserProfiles(bundleID: helium) == ["Profile 1": s.openCom.id!])
    // Deleting the Client drops its assignments.
    try s.h.tracker.closeClient(id: s.openCom.id!)
    try s.h.tracker.removeClient(id: s.openCom.id!)
    #expect(try s.h.tracker.browserProfiles(bundleID: helium).isEmpty)
}

@Test func browserWithNoAssignmentsIsUnchanged() throws {
    let s = try setup()
    try s.h.tracker.addTitleRule(bundleID: helium, kind: .contains, text: "admin", projectId: s.admin.id!)
    #expect(prompt(s.h, "Admin - Helium - Kipo") == s.admin.id)
    #expect(prompt(s.h, "News - Helium - Kipo") == s.shop.id)
    #expect(prompt(s.h, nil) == s.shop.id)
}

@Test func assignedProfileRestrictsAddressDocumentAndTitleRulesToItsClient() throws {
    let s = try setup()
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 1", clientId: s.openCom.id)
    try s.h.tracker.addProjectAddress(projectId: s.shop.id!, address: "github.com/kipo")
    try s.h.tracker.addProjectAddress(projectId: s.site.id!, address: "github.com")
    try s.h.tracker.addTitleRule(bundleID: helium, kind: .contains, text: "shop", projectId: s.shop.id!)
    try s.h.tracker.addTitleRule(bundleID: helium, kind: .contains, text: "admin", projectId: s.admin.id!)
    // The longest address is Kipo's, but the profile is OpenCom's: its shorter address wins.
    #expect(prompt(s.h, "Repo - Helium - OpenCom", url: "https://github.com/kipo/x") == s.site.id)
    // A rule for another Client loses to the profile; the Client's own rule applies.
    #expect(prompt(s.h, "shop admin - Helium - OpenCom") == s.admin.id)
}

@Test func assignedProfileFallsBackToTheClientsLastUsedProject() throws {
    let s = try setup()
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 1", clientId: s.openCom.id)
    try s.h.tracker.addTitleRule(bundleID: helium, kind: .contains, text: "shop", projectId: s.shop.id!)
    // Never used: the Client's first Open Project by name; never the browser's default (another Client).
    #expect(prompt(s.h, "shop - Helium - OpenCom") == s.admin.id)
    for p in [s.site, s.admin, s.site] {
        try s.h.tracker.start(projectId: p.id!)
        s.h.clock.advance(by: 120)
    }
    try s.h.tracker.start(projectId: s.shop.id!) // later, other Client
    s.h.clock.advance(by: 120)
    try s.h.tracker.stop()
    #expect(prompt(s.h, "shop - Helium - OpenCom") == s.site.id)
    // A Closed last-used Project is skipped.
    try s.h.tracker.closeProject(id: s.site.id!)
    #expect(prompt(s.h, "News - Helium - OpenCom") == s.admin.id)
}

@Test func noPromptForUnassignedClosedOrEmptyClientOnceTheBrowserHasAnAssignment() throws {
    let s = try setup()
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 1", clientId: s.openCom.id)
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 3", clientId: s.kipo.id)
    #expect(prompt(s.h, "News - Helium - Nic") == nil)           // unassigned profile
    #expect(prompt(s.h, "News - Helium") == nil)                 // no profile in the title
    #expect(prompt(s.h, nil) == nil)                             // title unknown
    #expect(prompt(s.h, "News - Helium - Kipo") == s.shop.id)
    // (A Client can't close its last Open Project, so "no Open Projects" means a Closed Client.)
    try s.h.tracker.closeClient(id: s.kipo.id!)
    #expect(prompt(s.h, "News - Helium - Kipo") == nil)          // Closed Client
}

@Test func unreadableProfileNamesLeaveTheBrowserAsIfUnassigned() throws {
    let s = try setup()
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 1", clientId: s.openCom.id)
    try s.h.tracker.addTitleRule(bundleID: helium, kind: .contains, text: "admin", projectId: s.admin.id!)
    // Names unknown (Local State unreadable): normal rules and the default, never silence.
    s.h.tracker.setBrowserProfileNames(bundleID: helium, nil)
    #expect(prompt(s.h, "Admin - Helium - OpenCom") == s.admin.id)
    #expect(prompt(s.h, "News - Helium - OpenCom") == s.shop.id)
    // Names known but none in the title: still silent.
    s.h.tracker.setBrowserProfileNames(bundleID: helium, [:])
    #expect(prompt(s.h, "News - Helium - OpenCom") == nil)
}

@Test func renamingAProfileKeepsItsAssignment() throws {
    let s = try setup()
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 1", clientId: s.openCom.id)
    s.h.tracker.setBrowserProfileNames(bundleID: helium, ["Default": "Nic", "Profile 1": "OpenCom Work"])
    #expect(prompt(s.h, "News - Helium - OpenCom Work") == s.admin.id)
    #expect(prompt(s.h, "News - Helium - OpenCom") == nil)
}

@Test func backupsIncludeAssignments() throws {
    let s = try setup()
    try s.h.tracker.setBrowserProfileClient(bundleID: helium, folder: "Profile 1", clientId: s.openCom.id)
    let file = FileManager.default.temporaryDirectory.appending(path: "wabbit-profiles-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: file) }
    try s.h.tracker.backup(to: file)
    let h2 = try Harness()
    try h2.tracker.restore(from: file)
    #expect(try h2.tracker.browserProfiles(bundleID: helium) == ["Profile 1": s.openCom.id!])
}
