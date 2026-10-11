import Foundation
import Testing
import HoursCore

private func at(_ h: Int, day: Int = 10) -> Date {
    var c = DateComponents(year: 2026, month: 3, day: day, hour: h)
    c.timeZone = Calendar.current.timeZone
    return Calendar.current.date(from: c)!
}

@Test func manualSessionIsFlaggedAndTrackedOneIsNot() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    let m = try h.tracker.addManualSession(projectId: p.id!, start: at(9), end: at(11))
    #expect(m.manual)
    #expect(h.tracker.duration(of: m) == 7200)
    let t = try h.tracker.start(projectId: p.id!)
    #expect(!t.manual)
    #expect(try h.tracker.sessions(projectId: p.id!).map(\.manual) == [true, false])
}

@Test func overlapIsRejectedAndNamesTheConflictingSession() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    let p2 = try h.tracker.addProject(clientId: c.id!, name: "App")
    let first = try h.tracker.addManualSession(projectId: p.id!, start: at(9), end: at(11))
    do {
        _ = try h.tracker.addManualSession(projectId: p2.id!, start: at(10), end: at(12))
        Issue.record("expected overlap")
    } catch HoursError.sessionOverlap(let other, let label) {
        #expect(other.id == first.id)
        #expect(label.contains("ACME / Web"))
    }
    // Touching edges are fine; editing within its own slot is fine; moving onto another is not.
    let next = try h.tracker.addManualSession(projectId: p.id!, start: at(11), end: at(12))
    _ = try h.tracker.editSession(id: next.id!, projectId: p.id!, start: at(11), end: at(13))
    #expect(throws: HoursError.self) { try h.tracker.editSession(id: next.id!, projectId: p.id!, start: at(10), end: at(13)) }
    #expect(throws: HoursError.invalidRange) { try h.tracker.addManualSession(projectId: p.id!, start: at(15), end: at(15)) }
}

@Test func overlapWithRunningSessionIsRejected() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    h.clock.current = at(10)
    try h.tracker.start(projectId: p.id!)
    h.clock.current = at(11)
    #expect(throws: HoursError.self) { try h.tracker.addManualSession(projectId: p.id!, start: at(9), end: at(10, day: 10).addingTimeInterval(60)) }
    try h.tracker.addManualSession(projectId: p.id!, start: at(8), end: at(10))
}

@Test func midnightCrossingSessionBelongsToItsStartDay() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    let s = try h.tracker.addManualSession(projectId: p.id!, start: at(23), end: at(2, day: 11))
    #expect(try h.tracker.sessions(onDay: at(12)).map(\.id) == [s.id])
    #expect(try h.tracker.sessions(onDay: at(12, day: 11)).isEmpty)
}

@Test func closedProjectRejectsManualSessionsAndEditsIntoIt() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    let p2 = try h.tracker.addProject(clientId: c.id!, name: "App")
    let s = try h.tracker.addManualSession(projectId: p.id!, start: at(9), end: at(10))
    try h.tracker.closeProject(id: p2.id!)
    #expect(throws: HoursError.projectClosed) { try h.tracker.addManualSession(projectId: p2.id!, start: at(12), end: at(13)) }
    #expect(throws: HoursError.projectClosed) { try h.tracker.editSession(id: s.id!, projectId: p2.id!, start: at(9), end: at(10)) }
}

@Test func deleteRemovesSession() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Web")
    let s = try h.tracker.addManualSession(projectId: p.id!, start: at(9), end: at(10))
    try h.tracker.deleteSession(id: s.id!)
    #expect(try h.tracker.allSessions().isEmpty)
    #expect(throws: HoursError.notFound) { try h.tracker.deleteSession(id: s.id!) }
}
