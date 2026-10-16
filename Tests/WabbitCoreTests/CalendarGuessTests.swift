import Foundation
import Testing
import WabbitCore

/// ACME/Website (domain acme.com), ACME/Blog, Beta/App; last used: Beta/App, then ACME/Website, then ACME/Blog.
private func setup(_ h: Harness) throws -> (acmeWebsite: Int64, acmeBlog: Int64, betaApp: Int64, acme: Int64) {
    let (acme, website) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let blog = try h.tracker.addProject(clientId: acme.id!, name: "Blog")
    let (_, app) = try h.tracker.createClient(name: "Beta", firstProject: "App")
    try h.tracker.addDomain(clientId: acme.id!, "acme.com")
    for p in [blog, website, app] {
        try h.tracker.start(projectId: p.id!)
        h.clock.advance(by: 3600)
    }
    try h.tracker.stop()
    return (website.id!, blog.id!, app.id!, acme.id!)
}

private func call(_ h: Harness, title: String, emails: [String]) {
    h.feed.emit(.microphone(on: true))
    h.feed.emit(.calendarEventCurrent(title: title, attendeeEmails: emails))
    h.clock.advance(by: 10)
}

@Test func attendeeDomainPicksTheClientsMostRecentlyUsedOpenProject() throws {
    let h = try Harness()
    let p = try setup(h)
    call(h, title: "Sync", emails: ["Anna@Acme.com", "me@gmail.com"])
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.acmeWebsite)) // not Blog: used less recently
}

@Test func domainBeatsTitleKeyword() throws {
    let h = try Harness()
    let p = try setup(h)
    call(h, title: "App review", emails: ["x@acme.com"])
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.acmeWebsite))
}

@Test func titleKeywordIsUsedWithoutAMatchingDomain() throws {
    let h = try Harness()
    let p = try setup(h)
    call(h, title: "Weekly BLOG planning", emails: ["x@other.org"])
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.acmeBlog))
}

@Test func lastUsedIsTheFallback() throws {
    let h = try Harness()
    let p = try setup(h)
    call(h, title: "Lunch", emails: ["x@other.org"])
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.betaApp))
}

@Test func noCalendarEventFallsBackToLastUsed() throws {
    let h = try Harness()
    let p = try setup(h)
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.betaApp))
}

@Test func closedProjectsAreNeverGuessed() throws {
    let h = try Harness()
    let p = try setup(h)
    try h.tracker.closeProject(id: p.acmeWebsite)
    call(h, title: "Sync", emails: ["x@acme.com"])
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.acmeBlog)) // Client's other Open Project

    let h2 = try Harness()
    let q = try setup(h2)
    try h2.tracker.closeClient(id: q.acme)
    call(h2, title: "Website sync", emails: ["x@acme.com"])
    #expect(h2.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: q.betaApp))
}

@Test func theEventDoesNotLeakIntoTheNextCall() throws {
    let h = try Harness()
    let p = try setup(h)
    call(h, title: "Sync", emails: ["x@acme.com"])
    h.feed.emit(.microphone(on: false))
    h.feed.emit(.microphone(on: true))
    h.clock.advance(by: 10)
    #expect(h.tracker.pendingMeetingPrompt() == .start(suggestedProjectId: p.betaApp))
}
