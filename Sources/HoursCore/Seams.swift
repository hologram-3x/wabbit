import Foundation

/// The only source of "now" for the core. Nothing in HoursCore reads the system time directly.
public protocol WallClock {
    func now() -> Date
}

public struct SystemClock: WallClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// OS signals the shell turns into events for the core (spec: "Detection input").
/// Idle (07) uses `userIdle` / `userActive`; later tickets (08–11) cover the rest.
public enum DetectionEvent: Equatable, Sendable {
    case microphone(on: Bool)
    case camera(on: Bool)
    case calendarEventCurrent(title: String, attendeeEmails: [String])
    case activeAppChanged(bundleID: String, windowTitle: String?)
    case userIdle(since: Date)
    case userActive
}

/// A source of DetectionEvents: the macOS adapters in the app, a fake in tests.
public protocol DetectionFeed: AnyObject {
    func subscribe(_ handler: @escaping (DetectionEvent) -> Void)
}
