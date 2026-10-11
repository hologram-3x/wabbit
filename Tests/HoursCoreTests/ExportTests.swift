import Foundation
import Testing
import HoursCore

@Test func roundedExactlyFifteenMinutesPastTheHour() {
    // 1h15:00 → remainder = threshold → round down to 1h
    #expect(ExportRounding.roundDuration(seconds: 3600 + 15 * 60) == 3600)
}

@Test func roundedFifteenMinutesAndOneSecond() {
    // 1h15:01 → round up to 2h
    #expect(ExportRounding.roundDuration(seconds: 3600 + 15 * 60 + 1) == 7200)
}

@Test func roundedSubHourSessions() {
    // 10 min ≤ 15 → 0; 20 min > 15 → 1h
    #expect(ExportRounding.roundDuration(seconds: 10 * 60) == 0)
    #expect(ExportRounding.roundDuration(seconds: 20 * 60) == 3600)
}

@Test func customThresholdAndStep() {
    let step: TimeInterval = 30 * 60
    let threshold: TimeInterval = 5 * 60
    #expect(ExportRounding.roundDuration(seconds: 35 * 60, step: step, threshold: threshold) == 30 * 60)
    #expect(ExportRounding.roundDuration(seconds: 35 * 60 + 1, step: step, threshold: threshold) == 60 * 60)
}

@Test func roundedExportUsesSettingsAndLeavesSessionsPrecise() throws {
    let h = try Harness()
    #expect(try h.tracker.roundingStep() == 3600)
    #expect(try h.tracker.roundingThreshold() == 15 * 60)
    try h.tracker.setRoundingStep(30 * 60)
    try h.tracker.setRoundingThreshold(5 * 60)

    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    try h.tracker.setMoney(projectId: p.id!, ProjectMoney(rateCents: 6000, billing: .hourly))
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 35 * 60 + 1)
    let stopped = try #require(try h.tracker.stop())
    #expect(h.tracker.duration(of: stopped) == 35 * 60 + 1)

    let csv = try h.tracker.exportCSV(scope: .project(p.id!), mode: .rounded)
    #expect(csv.contains("1.0000")) // 60 min after custom round-up
    #expect(h.tracker.duration(of: try h.tracker.sessions(projectId: p.id!)[0]) == 35 * 60 + 1)
}

@Test func preciseExportTotalsMatchOverview() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    try h.tracker.setMoney(projectId: p.id!, ProjectMoney(rateCents: 5000, billing: .hourly))
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 90 * 60 + 7)
    try h.tracker.stop()
    try h.tracker.start(projectId: p.id!)
    h.clock.advance(by: 30 * 60)
    try h.tracker.stop()

    let overview = try h.tracker.overview()[0].projects[0].revenueCents
    let csv = try h.tracker.exportCSV(scope: .project(p.id!), mode: .precise)
    let total = sumCSVAmounts(csv)
    #expect(total == overview)
    #expect(total == Money.revenue(seconds: 90 * 60 + 7, rateCents: 5000)
            + Money.revenue(seconds: 30 * 60, rateCents: 5000))
}

@Test func exportByProjectClientOrDateRange() throws {
    let h = try Harness()
    let (c, web) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let api = try h.tracker.addProject(clientId: c.id!, name: "API")
    let (_, other) = try h.tracker.createClient(name: "Beta", firstProject: "App")
    try h.tracker.setMoney(projectId: web.id!, ProjectMoney(rateCents: 1000))
    try h.tracker.setMoney(projectId: api.id!, ProjectMoney(rateCents: 2000))
    try h.tracker.setMoney(projectId: other.id!, ProjectMoney(rateCents: 3000))

    try h.tracker.start(projectId: web.id!)
    h.clock.advance(by: 3600)
    try h.tracker.stop()
    let split = h.clock.now()
    h.clock.advance(by: 60)
    try h.tracker.start(projectId: api.id!)
    h.clock.advance(by: 7200)
    try h.tracker.stop()
    try h.tracker.start(projectId: other.id!)
    h.clock.advance(by: 1800)
    try h.tracker.stop()

    let byProject = try h.tracker.exportCSV(scope: .project(web.id!), mode: .precise)
    #expect(countDataRows(byProject) == 1 && byProject.contains("Website"))

    let byClient = try h.tracker.exportCSV(scope: .client(c.id!), mode: .precise)
    #expect(countDataRows(byClient) == 2 && byClient.contains("Website") && byClient.contains("API"))
    #expect(!byClient.contains("Beta"))

    let byRange = try h.tracker.exportCSV(scope: .dateRange(split ..< .distantFuture), mode: .precise)
    #expect(countDataRows(byRange) == 2)
    #expect(byRange.contains("API") && byRange.contains("App"))
    #expect(!byRange.contains("Website"))
}

@Test func csvHasExpectedHeaderAndBom() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let csv = try h.tracker.exportCSV(scope: .project(p.id!), mode: .precise)
    #expect(csv.hasPrefix("\u{FEFF}date,client,project,start,end,duration,rate,amount,manual\n"))
}

@Test func manualSessionsAreMarkedInTheCSV() throws {
    let h = try Harness()
    let (_, p) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let start = h.clock.now().addingTimeInterval(-7200)
    _ = try h.tracker.addManualSession(projectId: p.id!, start: start, end: start.addingTimeInterval(3600))
    let csv = try h.tracker.exportCSV(scope: .project(p.id!), mode: .precise)
    #expect(csv.split(whereSeparator: \.isNewline).last?.hasSuffix(",true") == true)
}

// MARK: - helpers

private func countDataRows(_ csv: String) -> Int {
    csv.split(whereSeparator: \.isNewline).dropFirst().filter { !$0.isEmpty }.count
}

private func sumCSVAmounts(_ csv: String) -> Int {
    var total = 0
    for line in csv.split(whereSeparator: \.isNewline).dropFirst() where !line.isEmpty {
        let cols = String(line).split(separator: ",", omittingEmptySubsequences: false)
        guard cols.count >= 8, let euros = Double(cols[7]) else { continue }
        total += Int((euros * 100).rounded())
    }
    return total
}
