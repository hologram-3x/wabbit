import Foundation
import Testing
import HoursCore

extension Harness {
    /// Start a Session, advance past threshold while "idle", then return. Leaves a pending Idle prompt.
    func goIdlePastThreshold(projectId: Int64, work: TimeInterval = 30 * 60, idle: TimeInterval = 40 * 60) throws -> (Session, IdlePrompt) {
        let running = try tracker.start(projectId: projectId)
        clock.advance(by: work)
        let idleStart = clock.now()
        feed.emit(.userIdle(since: idleStart))
        clock.advance(by: idle)
        // Re-emit so observation sees duration ≥ threshold (shell polls while idle).
        feed.emit(.userIdle(since: idleStart))
        feed.emit(.userActive)
        let prompt = try #require(tracker.pendingIdlePrompt())
        return (running, prompt)
    }
}

@Test func idleThresholdDefaultsAndClamps() throws {
    let h = try Harness()
    #expect(try h.tracker.idleThreshold() == IdleThreshold.defaultSeconds)
    try h.tracker.setIdleThreshold(60) // below 5 min
    #expect(try h.tracker.idleThreshold() == IdleThreshold.minimum)
    try h.tracker.setIdleThreshold(3 * 60 * 60) // above 1 h
    #expect(try h.tracker.idleThreshold() == IdleThreshold.maximum)
    try h.tracker.setIdleThreshold(20 * 60)
    #expect(try h.tracker.idleThreshold() == 20 * 60)
}

@Test func idleShorterThanThresholdIsIgnored() throws {
    let h = try Harness()
    try h.tracker.setIdleThreshold(15 * 60)
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let running = try h.tracker.start(projectId: project.id!)
    h.clock.advance(by: 10 * 60)
    let idleStart = h.clock.now()
    h.feed.emit(.userIdle(since: idleStart))
    h.clock.advance(by: 5 * 60) // 5 min < 15 min threshold
    h.feed.emit(.userIdle(since: idleStart))
    h.feed.emit(.userActive)
    #expect(h.tracker.pendingIdlePrompt() == nil)
    #expect(try h.tracker.runningSession() == running)
}

@Test func idleKeepLeavesSessionUnchanged() throws {
    let h = try Harness()
    try h.tracker.setIdleThreshold(5 * 60)
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let (running, _) = try h.goIdlePastThreshold(projectId: project.id!, work: 20 * 60, idle: 10 * 60)
    #expect(try h.tracker.resolveIdle(.keep) == .kept)
    #expect(h.tracker.pendingIdlePrompt() == nil)
    #expect(try h.tracker.runningSession() == running)
    let sessions = try h.tracker.sessions(projectId: project.id!)
    #expect(sessions.count == 1)
    #expect(sessions[0].end == nil)
}

@Test func idleDiscardEndsSessionAtIdleStart() throws {
    let h = try Harness()
    try h.tracker.setIdleThreshold(5 * 60)
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let start = h.clock.now()
    let (_, prompt) = try h.goIdlePastThreshold(projectId: project.id!, work: 20 * 60, idle: 40 * 60)
    #expect(prompt.idleStart == start + 20 * 60)

    let result = try h.tracker.resolveIdle(.discard)
    guard case .discarded(let ended) = result else {
        Issue.record("expected discarded"); return
    }
    #expect(ended.start == start)
    #expect(ended.end == prompt.idleStart)
    #expect(try h.tracker.runningSession() == nil)
    #expect(try h.tracker.sessions(projectId: project.id!) == [ended])
    #expect(h.tracker.duration(of: ended) == 20 * 60)
}

@Test func idleSplitEndsWorkAndCreatesIdleSession() throws {
    let h = try Harness()
    try h.tracker.setIdleThreshold(5 * 60)
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let (_, other) = try h.tracker.createClient(name: "Beta", firstProject: "API")
    let start = h.clock.now()
    let (_, prompt) = try h.goIdlePastThreshold(projectId: project.id!, work: 20 * 60, idle: 40 * 60)

    let result = try h.tracker.resolveIdle(.split)
    guard case .split(let work, let idleSession, let resumed) = result else {
        Issue.record("expected split"); return
    }
    #expect(work.start == start)
    #expect(work.end == prompt.idleStart)
    #expect(idleSession.start == prompt.idleStart)
    #expect(idleSession.end == prompt.idleEnd)
    #expect(idleSession.projectId == project.id)
    #expect(h.tracker.duration(of: idleSession) == 40 * 60)
    #expect(resumed.start == prompt.idleEnd)
    #expect(resumed.end == nil)
    #expect(try h.tracker.runningSession() == resumed)

    // Assign the idle stretch to another Project, then drop a second Split's idle via dropSession.
    try h.tracker.assignSession(id: idleSession.id!, toProjectId: other.id!)
    #expect(try h.tracker.sessions(projectId: other.id!).map(\.id) == [idleSession.id])
    try h.tracker.dropSession(id: idleSession.id!)
    #expect(try h.tracker.sessions(projectId: other.id!).isEmpty)
}

@Test func idleAcrossMidnightDoesNotCutOffSession() throws {
    let h = try Harness()
    try h.tracker.setIdleThreshold(5 * 60)
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")

    // 23:00 local-ish epoch offset — only relative spans matter; no midnight stop.
    let start = h.clock.now()
    let running = try h.tracker.start(projectId: project.id!)
    h.clock.advance(by: 2 * 60 * 60) // past a midnight boundary in wall time
    #expect(try h.tracker.runningSession() == running)
    #expect(running.start == start)

    let idleStart = h.clock.now()
    h.feed.emit(.userIdle(since: idleStart))
    h.clock.advance(by: 40 * 60)
    h.feed.emit(.userIdle(since: idleStart))
    h.feed.emit(.userActive)
    let prompt = try #require(h.tracker.pendingIdlePrompt())
    #expect(prompt.idleStart == idleStart)

    #expect(try h.tracker.resolveIdle(.keep) == .kept)
    let still = try #require(try h.tracker.runningSession())
    #expect(still.id == running.id)
    #expect(still.start == start)
    #expect(still.end == nil)
    // Session still belongs to the day it started (start unchanged; never auto-ended at midnight).
    #expect(Calendar.current.startOfDay(for: still.start) == Calendar.current.startOfDay(for: start))
}
