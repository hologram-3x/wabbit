import AppKit
import HoursCore
import SwiftUI
import UserNotifications

/// macOS notifications for the Meeting, Idle and Watched App prompts. One per prompt, keyed by
/// `NotifiedPrompt.rawValue`; the tray keeps showing the prompt either way.
@MainActor @Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    weak var model: TrayModel?
    private(set) var status = UNAuthorizationStatus.notDetermined
    /// Categories are static per identifier: the current one per prompt, re-registered before each post.
    private var categories: [String: UNNotificationCategory] = [:]
    /// Latest content per prompt, so an older post finishing late doesn't resurrect a cleared prompt.
    private var current: [String: UNNotificationContent] = [:]
    /// `swift run` has no bundle, and UNUserNotificationCenter traps without one.
    private let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()

    func start() {
        center?.delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        guard let center else { return }
        // Callback forms here and below: Swift 6.0/6.1 (CI) rejects sending these non-Sendable types across actors.
        status = await withCheckedContinuation { c in center.getNotificationSettings { c.resume(returning: $0.authorizationStatus) } }
    }

    func requestAuthorization() async {
        guard let center else { return }
        await withCheckedContinuation { c in center.requestAuthorization(options: [.alert, .sound]) { _, _ in c.resume() } }
        await refreshStatus()
    }

    /// Synchronous on purpose: the async `add` sends the request across actors, which Swift 6.0/6.1 rejects.
    private static func enqueue(_ request: UNNotificationRequest, on center: UNUserNotificationCenter) {
        center.add(request)
    }

    /// Posts (or replaces) the notification for `prompt`; actions are (identifier, title) pairs.
    func post(_ prompt: NotifiedPrompt, title: String, body: String, actions: [(String, String)]) {
        guard let center else { return }
        let id = prompt.rawValue
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = id
        current[id] = content
        categories[id] = UNNotificationCategory(
            identifier: id, actions: actions.map { UNNotificationAction(identifier: $0.0, title: $0.1) },
            intentIdentifiers: [])
        center.setNotificationCategories(Set(categories.values))
        Task {
            await requestAuthorization()  // prompts only the first time; afterwards returns the stored answer
            guard status == .authorized || status == .provisional, current[id] === content else { return }
            center.removeDeliveredNotifications(withIdentifiers: [id])
            Self.enqueue(UNNotificationRequest(identifier: id, content: content, trigger: nil), on: center)
        }
    }

    func remove(_ prompt: NotifiedPrompt) {
        current[prompt.rawValue] = nil
        center?.removePendingNotificationRequests(withIdentifiers: [prompt.rawValue])
        center?.removeDeliveredNotifications(withIdentifiers: [prompt.rawValue])
    }

    // Hours is an accessory app that counts as active: show banners anyway.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier, action = response.actionIdentifier
        await model?.handleNotification(id: id, action: action)
    }
}

extension TrayModel {
    func setNotifies(_ prompt: NotifiedPrompt, _ on: Bool) {
        act { try tracker.setNotifies(prompt, on) }
        if !on { notifier.remove(prompt) }
    }

    func notifies(_ prompt: NotifiedPrompt) -> Bool { notifyOn.contains(prompt) }

    // Called from the didSet of meetingPrompt / idlePrompt / watchedPrompt.

    func notifyMeeting() {
        guard let prompt = meetingPrompt, notifies(.meeting) else { return notifier.remove(.meeting) }
        switch prompt {
        case .start(let p):
            notifier.post(.meeting, title: "Meeting started", body: "Start \(label(for: p))?",
                          actions: [("start", "Start \(label(for: p))"), ("other", "Other Project…"), ("dismiss", "Not now")])
        case .switchTo(let p, _):
            notifier.post(.meeting, title: "Switch to \(label(for: p))?",
                          body: running.map { "Now tracking \(label(for: $0.projectId))." } ?? "",
                          actions: [("start", "Switch to \(label(for: p))"), ("other", "Other Project…"), ("dismiss", "Not now")])
        case .stop:
            notifier.post(.meeting, title: "Meeting ended. Stop tracking?",
                          body: running.map { label(for: $0.projectId) } ?? "",
                          actions: [("stop", "Stop"), ("dismiss", "Not now")])
        }
    }

    func notifyIdle() {
        guard let prompt = idlePrompt, notifies(.idle) else { return notifier.remove(.idle) }
        let minutes = Int(prompt.idleEnd.timeIntervalSince(prompt.idleStart) / 60)
        notifier.post(.idle, title: "You were idle \(minutes) min", body: "While tracking \(label(for: prompt.projectId)).",
                      actions: [("keep", "Keep"), ("discard", "Discard"), ("split", "Split")])
    }

    func notifyWatched() {
        guard let prompt = watchedPrompt, notifies(.watched) else { return notifier.remove(.watched) }
        let start = prompt.projectId.map { [("accept", (running == nil ? "Start " : "Switch to ") + label(for: $0))] } ?? []
        notifier.post(.watched, title: "Track time for \(prompt.appName)?",
                      body: prompt.projectId == nil ? "Pick a Project in the tray to start." : "",
                      actions: start + [("notNow", "Not now"), ("notToday", "Not today")])
    }

    /// Acts on the prompt as it is now: a stale notification for a cleared prompt does nothing.
    func handleNotification(id: String, action: String) {
        switch (NotifiedPrompt(rawValue: id), action) {
        case (.meeting, "start"):
            switch meetingPrompt {
            case .start(let p), .switchTo(let p, _): resolveMeeting(.start(projectId: p))
            default: break
            }
        case (.meeting, "stop") where meetingPrompt != nil: resolveMeeting(.stop)
        case (.meeting, "dismiss") where meetingPrompt != nil: resolveMeeting(.dismiss)
        case (.meeting, "other"), (.meeting, UNNotificationDefaultActionIdentifier): showMeetingPanel()
        case (.idle, "keep") where idlePrompt != nil: resolveIdle(.keep)
        case (.idle, "discard") where idlePrompt != nil: resolveIdle(.discard)
        case (.idle, "split") where idlePrompt != nil: resolveIdle(.split)
        case (.watched, "accept"): if let p = watchedPrompt?.projectId { acceptWatchedPrompt(projectId: p) }
        case (.watched, "notNow") where watchedPrompt != nil: snoozeWatched(today: false)
        case (.watched, "notToday") where watchedPrompt != nil: snoozeWatched(today: true)
        default: break
        }
    }
}

/// Settings pane: which prompts also post a notification, and the macOS permission.
struct NotificationsView: View {
    let model: TrayModel

    var body: some View {
        Form {
            Section("Notify me when") {
                toggle(.meeting, "Meeting detected", "Microphone or camera turns on or off: start, switch or stop a Session.")
                toggle(.idle, "Back from idle", "You return after the Idle Threshold: keep, discard or split the idle time.")
                toggle(.watched, "Watched App in use", "A Watched App stays in front: start its Project.")
                Text("Prompts always show in the tray too.").foregroundStyle(.secondary).font(.caption)
            }
            Section("macOS permission") {
                HStack {
                    Text("Notifications")
                    Spacer()
                    switch model.notifier.status {
                    case .denied:
                        Text("Denied").foregroundStyle(.secondary)
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    case .notDetermined:
                        Text("Not determined").foregroundStyle(.secondary)
                        Button("Allow Notifications…") { Task { await model.notifier.requestAuthorization() } }
                    default:
                        Text("Authorized").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.notifier.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.notifier.refreshStatus() }
        }
    }

    private func toggle(_ prompt: NotifiedPrompt, _ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: Binding(get: { model.notifies(prompt) }, set: { model.setNotifies(prompt, $0) }))
            Text(caption).foregroundStyle(.secondary).font(.caption)
        }
    }
}
