import EventKit
import Foundation
import WabbitCore

/// The calendar event current (or overlapping) when a call starts, via EventKit.
/// Access is requested lazily, the first time a call needs it. Denied or failed: no event, and
/// the Meeting Prompt falls back to the last-used Project.
@MainActor
final class CalendarAccess {
    private let store = EKEventStore()

    func currentEvent(at now: Date = Date()) async -> DetectionEvent? {
        guard await hasAccess() else { return nil }
        // Window around now catches events that started a bit early or late; the one that started
        // most recently wins. All-day events are ignored (not a call).
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-4 * 3600), end: now.addingTimeInterval(15 * 60), calendars: nil)
        let events = store.events(matching: predicate).filter { !$0.isAllDay && $0.endDate > now && $0.startDate <= now.addingTimeInterval(15 * 60) }
        guard let event = events.max(by: { $0.startDate < $1.startDate }) else { return nil }
        let emails = (event.attendees ?? []).compactMap { a -> String? in
            let s = a.url.absoluteString
            return s.lowercased().hasPrefix("mailto:") ? String(s.dropFirst(7)) : nil
        }
        return .calendarEventCurrent(title: event.title ?? "", attendeeEmails: emails)
    }

    private func hasAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        // Callback form: the async one sends the main-actor store off the actor, which Swift 6.0/6.1 rejects.
        case .notDetermined: return await withCheckedContinuation { c in store.requestFullAccessToEvents { ok, _ in c.resume(returning: ok) } }
        default: return false
        }
    }
}
