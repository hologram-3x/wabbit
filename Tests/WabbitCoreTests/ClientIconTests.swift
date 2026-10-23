import Foundation
import Testing
import WabbitCore

private let svg = #"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#

@Test func iconIsSetAndCleared() throws {
    let h = try Harness()
    let (c, _) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    #expect(try h.tracker.clients().first?.icon == nil)
    try h.tracker.setIcon(clientId: c.id!, svg: svg)
    #expect(try h.tracker.clients().first?.icon == svg)
    try h.tracker.setIcon(clientId: c.id!, svg: nil)
    #expect(try h.tracker.clients().first?.icon == nil)
}

@Test func oversizedOrNonSVGIconsAreRefused() throws {
    let h = try Harness()
    let (c, _) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
    let big = "<svg>" + String(repeating: " ", count: Tracker.maxIconBytes) + "</svg>"
    #expect(throws: ClientIconError.tooLarge) { try h.tracker.setIcon(clientId: c.id!, svg: big) }
    #expect(throws: ClientIconError.notSVG) { try h.tracker.setIcon(clientId: c.id!, svg: "\u{89}PNG not an svg") }
    #expect(try h.tracker.clients().first?.icon == nil)
}

@Test func iconPersistsAcrossLaunches() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "wabbit-icon-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let id = try {
        let h = try Harness(path: path)
        let (c, _) = try h.tracker.createClient(name: "ACME", firstProject: "Website")
        try h.tracker.setIcon(clientId: c.id!, svg: svg)
        return c.id!
    }()
    #expect(try Harness(path: path).tracker.clients().first { $0.id == id }?.icon == svg)
}
