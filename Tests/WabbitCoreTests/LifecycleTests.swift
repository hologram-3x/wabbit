import Foundation
import Testing
import WabbitCore

@Test func renameClientAndProject() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    try h.tracker.renameClient(id: c.id!, to: " Acme Inc ")
    try h.tracker.renameProject(id: p.id!, to: "Site")
    #expect(try h.tracker.clients().first?.name == "Acme Inc")
    #expect(try h.tracker.projects().first?.name == "Site")
    #expect(throws: WabbitError.emptyName) { try h.tracker.renameProject(id: p.id!, to: "  ") }
}

@Test func lastProjectCannotBeRemovedOrClosed() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    #expect(throws: WabbitError.lastProject) { try h.tracker.removeProject(id: p.id!) }
    #expect(throws: WabbitError.lastProject) { try h.tracker.closeProject(id: p.id!) }
    let p2 = try h.tracker.addProject(clientId: c.id!, name: "App")
    try h.tracker.closeProject(id: p.id!)
    // p2 is now the last Open Project, and p is Closed.
    #expect(throws: WabbitError.lastProject) { try h.tracker.closeProject(id: p2.id!) }
    #expect(throws: WabbitError.lastProject) { try h.tracker.removeProject(id: p2.id!) }
    try h.tracker.reopenProject(id: p.id!)
    try h.tracker.removeProject(id: p2.id!)
    #expect(try h.tracker.projects().count == 1)
}

@Test func closedProjectRejectsStartedSessionsAndReopenAllowsThem() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    let p2 = try h.tracker.addProject(clientId: c.id!, name: "App")
    try h.tracker.closeProject(id: p.id!)
    #expect(throws: WabbitError.projectClosed) { try h.tracker.start(projectId: p.id!) }
    #expect(throws: WabbitError.projectClosed) { try h.tracker.requireOpen(projectId: p.id!) }
    try h.tracker.start(projectId: p2.id!)
    try h.tracker.reopenProject(id: p.id!)
    try h.tracker.start(projectId: p.id!)
    #expect(try h.tracker.runningSession()?.projectId == p.id)
}

@Test func closedProjectsAreHiddenFromOpenListButStillListed() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    try h.tracker.addProject(clientId: c.id!, name: "App")
    try h.tracker.closeProject(id: p.id!)
    #expect(try h.tracker.openProjects().map(\.name) == ["App"])
    #expect(try h.tracker.closedProjects().map(\.name) == ["Web"])
    #expect(try h.tracker.projects().count == 2)
}

@Test func closingAProjectStopsItsRunningSession() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    try h.tracker.addProject(clientId: c.id!, name: "App")
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 60)
    try h.tracker.closeProject(id: p.id!)
    #expect(try h.tracker.runningSession() == nil)
    #expect(try h.tracker.duration(of: h.tracker.sessions(projectId: p.id!)[0]) == 60)
}

@Test func closingAClientClosesItsProjectsAndReopenRestoresThem() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    try h.tracker.start(projectId: p.id!)
    try h.tracker.closeClient(id: c.id!)
    #expect(try h.tracker.runningSession() == nil)
    #expect(try h.tracker.openProjects().isEmpty)
    #expect(try h.tracker.closedProjects().count == 1)
    #expect(throws: WabbitError.projectClosed) { try h.tracker.start(projectId: p.id!) }
    try h.tracker.reopenClient(id: c.id!)
    try h.tracker.start(projectId: p.id!)
}

@Test func emailDomainsAddRemoveNormalizeAndPersist() throws {
    let path = NSTemporaryDirectory() + "hours-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let h = try Harness(path: path)
    let (c, _) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    try h.tracker.addDomain(clientId: c.id!, "@Acme.com")
    try h.tracker.addDomain(clientId: c.id!, "acme.com")
    try h.tracker.addDomain(clientId: c.id!, "acme.io")
    #expect(try h.tracker.domains(clientId: c.id!) == ["acme.com", "acme.io"])
    try h.tracker.removeDomain(clientId: c.id!, "acme.com")
    let reopened = try Harness(path: path)
    #expect(try reopened.tracker.domains(clientId: c.id!) == ["acme.io"])
}

@Test func newProjectsGetPaletteColourAndHourlyBilling() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    let p2 = try h.tracker.addProject(clientId: c.id!, name: "App")
    #expect(p.color != nil && p2.color != nil && p.color != p2.color)
    #expect(try h.tracker.projects().allSatisfy { $0.color != nil })
    #expect(try h.tracker.money(projectId: p.id!).billing == .hourly)
    #expect(try h.tracker.money(projectId: p2.id!).billing == .hourly)
}

@Test func setColorPersists() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    try h.tracker.setColor(projectId: p.id!, .purple)
    #expect(try h.tracker.projects().first?.color == .purple)
}
