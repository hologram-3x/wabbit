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

@Test func notNowIsQuietForAnHourAcrossSwitches() throws {
    let (h, _, _) = try setup()
    try h.tracker.setWatchedApp(bundleID: "com.apple.Notes", name: "Notes", projectId: nil)
    front(h, code)
    h.clock.advance(by: 30)
    h.tracker.snoozeWatchedAppNotNow()
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    front(h, "com.apple.finder")
    h.clock.advance(by: 60) // away longer than the delay
    front(h, code)
    h.clock.advance(by: 60)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil) // still snoozed
    #expect(h.tracker.watchedPromptResumeAt() != nil)
    front(h, "com.apple.Notes") // other apps unaffected
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt()?.bundleID == "com.apple.Notes")
    front(h, code)
    h.clock.advance(by: 3600 - 150 - 1)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    h.clock.advance(by: 1)
    #expect(h.tracker.pendingWatchedAppPrompt() != nil)
}

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Test func workingHoursOffMeansAlwaysAndPersist() throws {
    let (h, _, _) = try setup()
    #expect(h.tracker.workingHours() == WorkingHours())
    #expect(WorkingHours().contains(at(2026, 10, 24, 3))) // off: a Saturday night is fine
    let w = WorkingHours(enabled: true, weekdays: [2, 4], startMinute: 600, endMinute: 660)
    try h.tracker.setWorkingHours(w)
    #expect(h.tracker.workingHours() == w)
}

@Test func workingHoursBlockPromptOutsideWindow() throws {
    let (h, _, _) = try setup()
    try h.tracker.setWorkingHours(WorkingHours(enabled: true)) // Mon-Fri 9-18
    h.clock.current = at(2026, 10, 19, 9) // Monday
    front(h, code)
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt() != nil)
    h.clock.current = at(2026, 10, 19, 18, 0)
    front(h, "com.apple.finder"); front(h, code)
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    #expect(h.tracker.watchedPromptResumeAt() == at(2026, 10, 20, 9))
    h.clock.current = at(2026, 10, 24, 12) // Saturday
    front(h, "com.apple.finder"); front(h, code)
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt() == nil)
    #expect(h.tracker.watchedPromptResumeAt() == at(2026, 10, 26, 9))
}

@Test func overnightWorkingHours() {
    let w = WorkingHours(enabled: true, weekdays: [6], startMinute: 22 * 60, endMinute: 2 * 60) // Fridays 22-02
    #expect(w.contains(at(2026, 10, 23, 23))) // Friday night
    #expect(w.contains(at(2026, 10, 24, 1, 59))) // Saturday small hours
    #expect(!w.contains(at(2026, 10, 24, 2)))
    #expect(!w.contains(at(2026, 10, 24, 23))) // Saturday evening: not selected
    #expect(!w.contains(at(2026, 10, 23, 1))) // Friday small hours belong to Thursday
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
}

@Test func closedDefaultProjectIsNoSuggestion() throws {
    let (h, a, _) = try setup()
    try h.tracker.closeProject(id: a.id!)
    front(h, code)
    h.clock.advance(by: 30)
    #expect(h.tracker.pendingWatchedAppPrompt()?.projectId == nil)
}
