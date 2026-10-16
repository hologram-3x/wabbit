import Foundation
import Testing
import WabbitCore

final class FakeClock: WallClock {
    var current = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { current }
    func advance(by seconds: TimeInterval) { current += seconds }
}

final class FakeDetectionFeed: DetectionFeed {
    private var handlers: [(DetectionEvent) -> Void] = []
    func subscribe(_ handler: @escaping (DetectionEvent) -> Void) { handlers.append(handler) }
    func emit(_ event: DetectionEvent) { handlers.forEach { $0(event) } }
}

/// The test seam: fake clock, fake detection feed, real in-memory SQLite.
struct Harness {
    let clock = FakeClock()
    let feed = FakeDetectionFeed()
    let tracker: Tracker
    init(path: String? = nil) throws {
        tracker = try Tracker(path: path, clock: clock)
        tracker.connect(feed)
    }
}

@Test func creatingAClientCreatesItsFirstProject() throws {
    let h = try Harness()
    let (client, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    #expect(try h.tracker.clients() == [client])
    #expect(try h.tracker.projects() == [project])
    #expect(project.clientId == client.id)
}

@Test func aClientNeedsANamedFirstProject() throws {
    let h = try Harness()
    #expect(throws: WabbitError.emptyName) { try h.tracker.createClient(name: "ACME", firstProject: "  ") }
    #expect(throws: WabbitError.emptyName) { try h.tracker.createClient(name: "", firstProject: "Website") }
    #expect(try h.tracker.clients().isEmpty)
}

@Test func startAndStopRecordOneSessionWithExactInstants() throws {
    let h = try Harness()
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let started = h.clock.now()
    let running = try h.tracker.start(projectId: project.id!)
    h.clock.advance(by: 90 * 60 + 7)
    #expect(h.tracker.duration(of: running) == 90 * 60 + 7)

    let stopped = try #require(try h.tracker.stop())
    h.clock.advance(by: 600)
    #expect(stopped.start == started)
    #expect(stopped.end == started + 90 * 60 + 7)
    #expect(h.tracker.duration(of: stopped) == 90 * 60 + 7)
    #expect(try h.tracker.sessions(projectId: project.id!) == [stopped])
    #expect(try h.tracker.runningSession() == nil)
    #expect(try h.tracker.stop() == nil)
}

@Test func startingAgainStopsTheRunningSessionAtTheSameInstant() throws {
    let h = try Harness()
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let first = try h.tracker.start(projectId: project.id!)
    h.clock.advance(by: 60)
    let second = try h.tracker.start(projectId: project.id!)
    let sessions = try h.tracker.sessions(projectId: project.id!)
    #expect(sessions.count == 2)
    #expect(sessions[0].id == first.id && sessions[0].end == second.start)
    #expect(try h.tracker.runningSession() == second)
}

@Test func aRunningSessionSurvivesARestart() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("hours-\(UUID()).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    var running: Session
    do {
        let h = try Harness(path: path)
        let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
        running = try h.tracker.start(projectId: project.id!)
    }
    let relaunched = try Harness(path: path)
    #expect(try relaunched.tracker.runningSession() == running)
}

@Test func detectionEventsDoNotTouchSessionsYet() throws {
    let h = try Harness()
    let (_, project) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let running = try h.tracker.start(projectId: project.id!)
    h.feed.emit(.microphone(on: true))
    h.feed.emit(.userIdle(since: h.clock.now()))
    #expect(try h.tracker.runningSession() == running)
}
