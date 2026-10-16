import Foundation

/// What the Meeting Prompt offers (spec: "Decisions out"). The shell only renders it.
public enum MeetingPrompt: Equatable, Sendable {
    /// No Session running: start the suggested Project.
    case start(suggestedProjectId: Int64)
    /// A Session runs on another Project: "Switch to …?".
    case switchTo(suggestedProjectId: Int64, runningSessionId: Int64)
    /// The call ended while a Session runs: "Stop tracking?". Never automatic.
    case stop(sessionId: Int64)
}

public enum MeetingChoice: Equatable, Sendable {
    /// Start (or switch to) this Project; the freelancer may have changed the suggestion.
    case start(projectId: Int64)
    case stop
    /// "Not now": hides the prompt for this call, changes nothing.
    case dismiss
}

public enum MeetingDebounce {
    /// The microphone or camera must stay on this long before the prompt shows (spec: ~10 s).
    public static let seconds: TimeInterval = 10
}

/// In-memory call state from microphone/camera events. Not persisted (re-detected after relaunch).
final class MeetingRuntime {
    var microphoneOn = false
    var cameraOn = false
    /// When the microphone or camera first came on for the current call.
    var callStart: Date?
    /// The start/switch prompt was answered for the current call.
    var answered = false
    /// The Session the "Stop tracking?" offer is about.
    var stopOfferSessionId: Int64?
    /// The calendar event current for this call (ticket 09). Cleared when the call ends.
    var calendarEvent: CalendarEvent?
}

extension Tracker {
    public func pendingMeetingPrompt() -> MeetingPrompt? {
        let running = try? runningSession()
        if let offered = meeting.stopOfferSessionId {
            // Gone once the Session stops some other way.
            return running?.id == offered ? .stop(sessionId: offered) : nil
        }
        guard let callStart = meeting.callStart, !meeting.answered,
              clock.now().timeIntervalSince(callStart) >= MeetingDebounce.seconds,
              let suggested = try? meetingSuggestion(excluding: running?.projectId)
        else { return nil }
        if let running, let id = running.id {
            return .switchTo(suggestedProjectId: suggested, runningSessionId: id)
        }
        return .start(suggestedProjectId: suggested)
    }

    public func resolveMeetingPrompt(_ choice: MeetingChoice) throws {
        switch choice {
        case .start(let projectId): try start(projectId: projectId)
        case .stop: try stop()
        case .dismiss: break
        }
        meeting.answered = true
        meeting.stopOfferSessionId = nil
    }

    /// The Project the Meeting Prompt suggests: the calendar guess, else the last-used Open Project.
    /// The running Project is excluded: a call on it needs no switch.
    func meetingSuggestion(excluding runningProjectId: Int64?) throws -> Int64? {
        if let event = meeting.calendarEvent, let id = try calendarGuess(event, excluding: runningProjectId) { return id }
        return try quickStartProjects(limit: .max).first { $0.id != runningProjectId }?.id
    }

    func handleMeetingEvent(_ event: DetectionEvent) {
        let wasOn = meeting.microphoneOn || meeting.cameraOn
        switch event {
        case .microphone(let on): meeting.microphoneOn = on
        case .camera(let on): meeting.cameraOn = on
        case .calendarEventCurrent(let title, let emails):
            meeting.calendarEvent = CalendarEvent(title: title, attendeeEmails: emails)
            return
        default: return
        }
        let isOn = meeting.microphoneOn || meeting.cameraOn
        if isOn, !wasOn {
            meeting.callStart = clock.now()
            meeting.calendarEvent = nil
            meeting.answered = false
            meeting.stopOfferSessionId = nil
        } else if !isOn, wasOn, let callStart = meeting.callStart {
            // ponytail: no debounce on "off"; a mic that blinks off mid-call shows the stop offer
            // until it comes back on. Add an off-debounce if real calls do that.
            let wasCall = clock.now().timeIntervalSince(callStart) >= MeetingDebounce.seconds
            meeting.callStart = nil
            meeting.calendarEvent = nil
            meeting.stopOfferSessionId = wasCall ? (try? runningSession())?.id : nil
        }
    }
}
