import Foundation
import Testing
import WabbitCore

private let code = "com.microsoft.VSCode"

private func setup(default useDefault: Bool = true) throws -> (Harness, Project, Project) {
    let h = try Harness()
    let (client, a) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let b = try h.tracker.addProject(clientId: client.id!, name: "App")
    try h.tracker.setWatchedApp(bundleID: code, name: "VS Code", projectId: useDefault ? a.id : nil)
    try h.tracker.setWatchedAppDelay(30)
    return (h, a, b)
}

private func front(_ h: Harness, _ id: String) { h.feed.emit(.activeAppChanged(bundleID: id, windowTitle: nil)) }

@Test func watchedAppsStoreDefaultProjectAndDelayClamps() throws {
    let (h, a, _) = try setup()
    #expect(try h.tracker.watchedApps() == [WatchedApp(bundleID: code, name: "VS Code", projectId: a.id)])
    try h.tracker.setWatchedAppDelay(1)
    #expect(try h.tracker.watchedAppDelay() == 5)
    try h.tracker.removeWatchedApp(bundleID: code)
    #expect(try h.tracker.watchedApps().isEmpty)
}

@Test func promptAppearsOnlyAfterDelay() throws {
    let (h, a, _) = try setup()
    front(h, code)
    h.clock.advance(by: 29)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    h.clock.advance(by: 1)
    #expect(h.tracker.pendingWatchedAppPrompt() == WatchedAppPrompt(bundleID: code, appName: "VS Code", projectId: a.id))
}

@Test func unwatchedAppNeverPrompts() throws {
    let (h, _, _) = try setup()
    front(h, "com.apple.finder")
    h.clock.advance(by: 600)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
}

@Test func noPromptWhenAlreadyTrackingMatchedProject() throws {
    let (h, a, b) = try setup()
    try h.tracker.start(projectId: a.id!)
    front(h, code)
    h.clock.advance(by: 60)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    // A different running Project does prompt (offer to switch).
    try h.tracker.start(projectId: b.id!)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == a.id)
}

@Test func appWithoutDefaultPromptsOnlyWhenNothingRuns() throws {
    let (h, a, _) = try setup(default: false)
    front(h, code)
    h.clock.advance(by: 60)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == nil)
    try h.tracker.start(projectId: a.id!)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
}

@Test func notNowSnoozesUntilAppLeavesFront() throws {
    let (h, _, _) = try setup()
    front(h, code)
    h.clock.advance(by: 30)
    h.tracker.snoozeWatchedAppNotNow()
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    h.clock.advance(by: 3600)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    front(h, "com.apple.finder")
    h.clock.advance(by: 60) // away longer than the delay: a new stay
    front(h, code)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil) // delay restarts
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt() != nil)
}

@Test func notTodaySnoozesUntilLocalMidnight() throws {
    let (h, _, _) = try setup()
    front(h, code)
    h.clock.advance(by: 30)
    h.tracker.snoozeWatchedAppNotToday()
    front(h, "com.apple.finder")
    h.clock.advance(by: 60)
    front(h, code)
    h.clock.advance(by: 60)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    let midnight = Calendar.current.nextDate(
        after: h.clock.now(), matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)!
    h.clock.current = midnight.addingTimeInterval(-1)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    h.clock.current = midnight
    #expect(h.tracker.pendingWatchedAppPrompt() != nil)
}

@Test func altTabbingDoesNotRepeatOrResetThePrompt() throws {
    let (h, _, _) = try setup()
    // Quick alt-tabs before the delay never prompt on their own.
    front(h, code)
    h.clock.advance(by: 10)
    front(h, "com.apple.finder")
    h.clock.advance(by: 5)
    front(h, code)
    h.clock.advance(by: 10)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    h.clock.advance(by: 5) // 30 s of the same stay (grace)
    #expect(h.tracker.pendingWatchedAppPrompt() != nil)
    // Snoozed "not now", a quick alt-tab back stays snoozed.
    h.tracker.snoozeWatchedAppNotNow()
    front(h, "com.apple.finder")
    h.clock.advance(by: 5)
    front(h, code)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
}

@Test func closedDefaultProjectIsNoSuggestion() throws {
    let (h, a, _) = try setup()
    try h.tracker.closeProject(id: a.id!)
    front(h, code)
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == nil)
}
