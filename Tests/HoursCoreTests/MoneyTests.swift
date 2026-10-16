import Foundation
import Testing
import HoursCore

@Test func taxRoundsToTheCentOnce() {
    #expect(Money.net(ofGross: 20_000, taxBps: 2200) == 15_600)
    #expect(Money.gross(ofNet: 20_000, taxBps: 2200) == 25_641)
    #expect(Money.display(20_000, mode: .gross, taxBps: 2200) == 15_600)
    #expect(Money.display(20_000, mode: .net, taxBps: 2200) == 25_641)
}

@Test func fixedEffectiveRateAgainstRateWarns() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Site")
    try h.tracker.setMoney(projectId: p.id!, ProjectMoney(rateCents: 5000, billing: .fixed(priceCents: 200_000, estimatedHours: 100)))
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 80 * 3600)
    try h.tracker.stop()
    let o = try h.tracker.overview()[0].projects[0]
    #expect(o.effectiveRateCents == 2500)
    #expect(o.percentOfEstimate == 80)
    #expect(o.underRate && !o.overEstimate && o.hasWarning)
    #expect(o.revenueCents == 200_000)
}

@Test func noBillingMeansNoWarnings() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Site")
    try h.tracker.setMoney(projectId: p.id!, ProjectMoney(rateCents: 5000))
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 90 * 60)
    try h.tracker.stop()
    let o = try h.tracker.overview()[0].projects[0]
    #expect(o.revenueCents == 7500 && !o.hasWarning)
}

@Test func overEstimateWarnsAndHourlyNeverUnderRate() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Site")
    try h.tracker.setMoney(projectId: p.id!, ProjectMoney(rateCents: 1000, billing: .fixed(priceCents: 100_000, estimatedHours: 10)))
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 11 * 3600)
    try h.tracker.stop()
    #expect(try h.tracker.overview()[0].projects[0].overEstimate)
    try h.tracker.setMoney(projectId: p.id!, ProjectMoney(rateCents: 1000, billing: .hourly))
    #expect(try !h.tracker.overview()[0].projects[0].hasWarning)
}

@Test func overviewFiltersByDateRangeAndKeepsClosedProjects() throws {
    let h = try Harness()
    let (c, p) = try h.tracker.createClient(name: "ACME", firstProject: "Site")
    let p2 = try h.tracker.addProject(clientId: c.id!, name: "Old")
    try h.tracker.setMoney(projectId: p.id!, ProjectMoney(rateCents: 6000, billing: .hourly))
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 3600)
    try h.tracker.stop()
    let split = h.clock.now()
    h.clock.advance(by: 86_400)
    try h.tracker.start(projectId: p2.id!)
    h.clock.advance(by: 7200)
    try h.tracker.stop()
    try h.tracker.closeProject(id: p2.id!)

    let all = try h.tracker.overview()[0]
    #expect(all.seconds == 3 * 3600 && all.projects.count == 2)
    #expect(all.projects.first { $0.project.name == "Old" }?.closed == true)
    let early = try h.tracker.overview(range: .distantPast ..< split)[0]
    #expect(early.seconds == 3600 && early.revenueCents == 6000)
}

@Test func settingsPersistWithDefaults() throws {
    let h = try Harness()
    #expect(try h.tracker.taxRateBps() == 0 && h.tracker.amountMode() == .gross)
    try h.tracker.setTaxRateBps(2200)
    try h.tracker.setAmountMode(.net)
    #expect(try h.tracker.taxRateBps() == 2200 && h.tracker.amountMode() == .net)
    #expect(throws: HoursError.invalidMoney) { try h.tracker.setTaxRateBps(10_000) }
}

@Test func defaultRateFillsNewAndRatelessProjectsOnly() throws {
    let h = try Harness()
    let t = h.tracker
    #expect(try t.defaultRateCents() == nil)
    let (c, p0) = try t.createClient(name: "ACME", firstProject: "Site")
    let p1 = try t.addProject(clientId: c.id!, name: "App")
    try t.setMoney(projectId: p1.id!, ProjectMoney(rateCents: 3000))
    #expect(try t.money(projectId: p0.id!).rateCents == nil)

    try t.setDefaultRateCents(5000)  // backfills NULL, keeps p1
    #expect(try t.defaultRateCents() == 5000)
    #expect(try t.money(projectId: p0.id!).rateCents == 5000)
    #expect(try t.money(projectId: p1.id!).rateCents == 3000)
    let p2 = try t.addProject(clientId: c.id!, name: "Blog")
    #expect(try t.money(projectId: p2.id!).rateCents == 5000)

    try t.setDefaultRateCents(7000)  // everything has a Rate now: untouched
    #expect(try t.money(projectId: p0.id!).rateCents == 5000)

    try t.setDefaultRateCents(nil)  // does not clear Project rates
    #expect(try t.defaultRateCents() == nil)
    #expect(try t.money(projectId: p0.id!).rateCents == 5000)
    let p3 = try t.addProject(clientId: c.id!, name: "Docs")
    #expect(try t.money(projectId: p3.id!).rateCents == nil)
    #expect(throws: HoursError.invalidMoney) { try t.setDefaultRateCents(-1) }
}

@Test func notificationsDefaultOnAndPersist() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "hours-test-notify-\(UUID()).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let h = try Harness(path: path)
    #expect(try NotifiedPrompt.allCases.allSatisfy { try h.tracker.notifies($0) })
    try h.tracker.setNotifies(.idle, false)
    let reopened = try Harness(path: path)
    #expect(try !reopened.tracker.notifies(.idle))
    #expect(try reopened.tracker.notifies(.meeting) && reopened.tracker.notifies(.watched))
}
