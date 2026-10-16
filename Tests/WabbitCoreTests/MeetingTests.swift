import Foundation
import Testing
import WabbitCore

/// ACME / Website used first, then Beta / App used last.
private func twoProjects(_ h: Harness) throws -> (website: Int64, app: Int64) {
    let (_, website) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let (_, app) = try h.tracker.createClient(name: "Beta", firstProject: "App")
    try h.tracker.start(projectId: website.id!)
    h.clock.advance(by: 3600)
    try h.tracker.start(projectId: app.id!)
    h.clock.advance(by: 3600)
    try h.tracker.stop()
    return (website.id!, app.id!)
}

@Test func meetingPromptIsDebounced() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 9)
    #expect(h.tracker.pendingMeetingPrompt() == nil)
    h.clock.advance(by: 1)
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.app))
}

@Test func aShortMicTestNeverPrompts() throws {
    let h = try Harness()
    _ = try twoProjects(h)
    h.feed.emit(.camera(on: true))
    h.clock.advance(by: 5)
    h.feed.emit(.camera(on: false))
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingMeetingPrompt() == nil)
}

@Test func cameraJoiningDoesNotRestartTheDebounce() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 8)
    h.feed.emit(.camera(on: true))
    h.feed.emit(.microphone(on: false)) // camera still on: same call
    h.clock.advance(by: 2)
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.app))
}

@Test func suggestionIsTheLastUsedOpenProject() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    let beta = try #require(try h.tracker.projects().first { $0.id == p.app }?.clientId)
    try h.tracker.closeClient(id: beta) // Closed Projects are never suggested
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.website))
}

@Test func acceptingStartsTheChosenProjectAndHidesThePrompt() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    try h.tracker.resolveMeetingPrompt(.start(projectId: p.website)) // changed the suggestion
    #expect(try h.tracker.runningSession()?.projectId == p.website)
    #expect(h.tracker.pendingMeetingPrompt() == nil)
}

@Test func whileRunningThePromptOffersASwitchAndIgnoringChangesNothing() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    let running = try h.tracker.start(projectId: p.app)
    h.clock.advance(by: 600)
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    // The running Project is excluded: the next last-used one is offered.
    #expect(h.tracker.pendingMeetingPrompt() == .switchTo(suggestedProjectId: p.website, runningSessionId: running.id!))
    h.clock.advance(by: 1800) // ignored
    #expect(try h.tracker.runningSession() == running)
    try h.tracker.resolveMeetingPrompt(.dismiss)
    #expect(h.tracker.pendingMeetingPrompt() == nil)
    #expect(try h.tracker.runningSession() == running)
}

@Test func switchingStopsTheRunningSessionAtTheSameInstant() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    let running = try h.tracker.start(projectId: p.app)
    h.feed.emit(.camera(on: true))
    h.clock.advance(by: 10)
    guard case .switchTo(let suggested, _) = h.tracker.pendingMeetingPrompt() else {
        Issue.record("expected a switch offer"); return
    }
    try h.tracker.resolveMeetingPrompt(.start(projectId: suggested))
    let ended = try #require(try h.tracker.sessions(projectId: p.app).first { $0.id == running.id })
    #expect(ended.end == h.clock.now())
    #expect(try h.tracker.runningSession()?.projectId == p.website)
}

@Test func callEndingOffersStopButNeverStops() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    h.feed.emit(.microphone(on: true))
    h.feed.emit(.camera(on: true))
    h.clock.advance(by: 10)
    try h.tracker.resolveMeetingPrompt(.start(projectId: p.app))
    let running = try #require(try h.tracker.runningSession())
    h.clock.advance(by: 1800)
    h.feed.emit(.microphone(on: false))
    #expect(h.tracker.pendingMeetingPrompt() == nil) // camera still on
    h.feed.emit(.camera(on: false))
    #expect(h.tracker.pendingMeetingPrompt() == .stop(sessionId: running.id!))
    h.clock.advance(by: 600) // ignored: still running
    #expect(try h.tracker.runningSession() == running)
    try h.tracker.resolveMeetingPrompt(.stop)
    #expect(try h.tracker.runningSession() == nil)
    #expect(h.tracker.pendingMeetingPrompt() == nil)
}

@Test func noStopOfferWhenNothingRunsOrWhenStoppedByHand() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 60)
    h.feed.emit(.microphone(on: false))
    #expect(h.tracker.pendingMeetingPrompt() == nil) // nothing running

    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    try h.tracker.resolveMeetingPrompt(.start(projectId: p.app))
    h.feed.emit(.microphone(on: false))
    try h.tracker.stop() // stopped from the tray instead
    #expect(h.tracker.pendingMeetingPrompt() == nil)
}

@Test func aNewCallPromptsAgainAfterADismissedOne() throws {
    let h = try Harness()
    let p = try twoProjects(h)
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    try h.tracker.resolveMeetingPrompt(.dismiss)
    h.feed.emit(.microphone(on: false))
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.app))
}
