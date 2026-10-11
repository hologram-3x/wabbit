import Foundation
import Testing
import HoursCore

private func names(_ h: Harness, _ limit: Int = 5) throws -> [String] {
    try h.tracker.quickStartProjects(limit: limit).map(\.name)
}

@Test func quickStartOrdersByMostRecentUseThenName() throws {
    let h = try Harness()
    let (c, a) = try h.tracker.createClient(name: "C", firstProject: "A")
    let b = try h.tracker.addProject(clientId: c.id!, name: "B")
    _ = try h.tracker.addProject(clientId: c.id!, name: "Z")
    _ = try h.tracker.addProject(clientId: c.id!, name: "D")
    #expect(try names(h) == ["A", "B", "D", "Z"])  // never used: by name
    try h.tracker.start(projectId: a.id!); h.clock.advance(by: 60)
    try h.tracker.start(projectId: b.id!); h.clock.advance(by: 60)
    try h.tracker.stop()
    #expect(try names(h) == ["B", "A", "D", "Z"])
    #expect(try names(h, 2) == ["B", "A"])
}

@Test func quickStartSkipsClosedProjects() throws {
    let h = try Harness()
    let (c, a) = try h.tracker.createClient(name: "C", firstProject: "A")
    let b = try h.tracker.addProject(clientId: c.id!, name: "B")
    try h.tracker.start(projectId: b.id!)
    try h.tracker.stop()
    try h.tracker.closeProject(id: b.id!)
    #expect(try names(h) == ["A"])
    _ = a
}

@Test func startingWhileRunningStopsTheRunningSessionAtTheSameInstant() throws {
    let h = try Harness()
    let (c, a) = try h.tracker.createClient(name: "C", firstProject: "A")
    let b = try h.tracker.addProject(clientId: c.id!, name: "B")
    let first = try h.tracker.start(projectId: a.id!)
    h.clock.advance(by: 300)
    let second = try h.tracker.start(projectId: b.id!)
    let stopped = try #require(try h.tracker.sessions(projectId: a.id!).first)
    #expect(stopped.id == first.id)
    #expect(stopped.end == second.start)
    #expect(try h.tracker.runningSession()?.id == second.id)
}
