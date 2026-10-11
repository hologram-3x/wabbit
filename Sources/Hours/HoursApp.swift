import AppKit
import CoreGraphics
import HoursCore
import ServiceManagement
import SwiftUI

@main
struct HoursApp: App {
    @State private var model = TrayModel()

    var body: some Scene {
        MenuBarExtra {
            TrayView(model: model)
        } label: {
            Image(systemName: model.running == nil ? "clock" : "stop.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Shell-side detection feed: OS adapters emit here; the core subscribes.
final class AppDetectionFeed: DetectionFeed {
    private var handlers: [(DetectionEvent) -> Void] = []
    func subscribe(_ handler: @escaping (DetectionEvent) -> Void) { handlers.append(handler) }
    func emit(_ event: DetectionEvent) { handlers.forEach { $0(event) } }
}

@MainActor @Observable
final class TrayModel {
    private let tracker: Tracker
    private let feed = AppDetectionFeed()
    private var idlePoll: Timer?
    private var wasPastIdleThreshold = false

    private(set) var projects: [Project] = []
    private(set) var clients: [Int64: String] = [:]
    private(set) var running: Session?
    private(set) var idleThresholdMinutes: Int = 15
    private(set) var idlePrompt: IdlePrompt?
    /// Idle Session left by Split, awaiting assign or drop.
    private(set) var splitIdleSession: Session?
    var error: String?

    /// Idle is polled at most every 30 s (footprint budget / ticket 07).
    static let idlePollInterval: TimeInterval = 30

    init() {
        do {
            let dir = URL.applicationSupportDirectory.appending(path: "Hours")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            tracker = try Tracker(path: dir.appending(path: "hours.sqlite").path, clock: SystemClock())
        } catch {
            fatalError("Cannot open the Hours database: \(error)")
        }
        tracker.connect(feed)
        Self.registerLoginItemOnFirstInstall()
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
        startIdlePolling()
    }

    func refresh() {
        attempt {
            projects = try tracker.projects()
            clients = Dictionary(uniqueKeysWithValues: try tracker.clients().map { ($0.id!, $0.name) })
            running = try tracker.runningSession()
            idleThresholdMinutes = Int(try tracker.idleThreshold() / 60)
            idlePrompt = tracker.pendingIdlePrompt()
        }
    }

    func label(for projectId: Int64) -> String {
        guard let p = projects.first(where: { $0.id == projectId }) else { return "?" }
        return "\(clients[p.clientId] ?? "?") / \(p.name)"
    }

    func start(_ project: Project) { attempt { try tracker.start(projectId: project.id!) } }
    func stop() { attempt { try tracker.stop() } }
    func createClient(_ name: String, firstProject: String) -> Bool {
        attempt { try tracker.createClient(name: name, firstProject: firstProject) }
    }

    func setIdleThresholdMinutes(_ minutes: Int) {
        attempt { try tracker.setIdleThreshold(TimeInterval(minutes * 60)) }
        refresh()
    }

    func resolveIdle(_ resolution: IdleResolution) {
        attempt {
            let result = try tracker.resolveIdle(resolution)
            if case .split(_, let idle, _) = result {
                splitIdleSession = idle
            } else {
                splitIdleSession = nil
            }
        }
        refresh()
    }

    func dropSplitIdle() {
        guard let id = splitIdleSession?.id else { return }
        attempt { try tracker.dropSession(id: id) }
        splitIdleSession = nil
        refresh()
    }

    func assignSplitIdle(to project: Project) {
        guard let id = splitIdleSession?.id else { return }
        attempt { try tracker.assignSession(id: id, toProjectId: project.id!) }
        splitIdleSession = nil
        refresh()
    }

    @discardableResult
    private func attempt(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            error = nil
        } catch {
            self.error = "\(error)"
            return false
        }
        return true
    }

    // MARK: Idle polling (macOS only)

    private func startIdlePolling() {
        pollIdle()
        idlePoll = Timer.scheduledTimer(withTimeInterval: Self.idlePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollIdle() }
        }
    }

    private func pollIdle() {
        // ~0 as event type = any input (keyboard, mouse, …). No permission needed.
        let anyEvent = CGEventType(rawValue: ~0)!
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
        let threshold = TimeInterval(idleThresholdMinutes * 60)
        if idleSeconds >= threshold {
            let since = Date().addingTimeInterval(-idleSeconds)
            feed.emit(.userIdle(since: since))
            wasPastIdleThreshold = true
        } else if wasPastIdleThreshold {
            feed.emit(.userActive)
            wasPastIdleThreshold = false
        }
        idlePrompt = tracker.pendingIdlePrompt()
        if let running = try? tracker.runningSession() {
            self.running = running
        }
    }

    // MARK: Launch at login

    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    func setLaunchAtLogin(_ on: Bool) {
        attempt { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Turn launch at login on once, the first time Hours runs from /Applications.
    /// Dev builds elsewhere never register themselves.
    private static func registerLoginItemOnFirstInstall() {
        let key = "didOfferLaunchAtLogin"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }
}

struct TrayView: View {
    let model: TrayModel
    @State private var newClient = ""
    @State private var firstProject = ""

    private static let thresholdChoices = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let prompt = model.idlePrompt {
                idlePromptSection(prompt)
                Divider()
            } else if let split = model.splitIdleSession {
                splitFollowUpSection(split)
                Divider()
            }

            if let running = model.running {
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.label(for: running.projectId)).bold()
                        Text(running.start, style: .timer).monospacedDigit()
                    }
                    Spacer()
                    Button("Stop") { model.stop(); model.refresh() }
                        .keyboardShortcut(.defaultAction)
                }
                Divider()
            }

            if model.projects.isEmpty {
                Text("Create a Client and its first Project to start tracking.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.projects) { project in
                HStack {
                    Text(model.label(for: project.id!))
                    Spacer()
                    Button("Start") { model.start(project); model.refresh() }
                        .disabled(model.running?.projectId == project.id)
                }
            }

            Divider()
            Text("New Client").font(.headline)
            TextField("Client name", text: $newClient)
            TextField("First Project", text: $firstProject)
            Button("Create Client") {
                if model.createClient(newClient, firstProject: firstProject) {
                    newClient = ""
                    firstProject = ""
                    model.refresh()
                }
            }
            .disabled(newClient.trimmingCharacters(in: .whitespaces).isEmpty
                || firstProject.trimmingCharacters(in: .whitespaces).isEmpty)

            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Divider()
            Picker("Idle Threshold", selection: Binding(
                get: { model.idleThresholdMinutes },
                set: { model.setIdleThresholdMinutes($0) }
            )) {
                ForEach(Self.thresholdChoices, id: \.self) { minutes in
                    Text(minutes < 60 ? "\(minutes) min" : "1 h").tag(minutes)
                }
            }
            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Button("Quit Hours") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 300)
    }

    @ViewBuilder
    private func idlePromptSection(_ prompt: IdlePrompt) -> some View {
        let minutes = Int(prompt.idleEnd.timeIntervalSince(prompt.idleStart) / 60)
        VStack(alignment: .leading, spacing: 8) {
            Text("You were idle \(minutes) min").font(.headline)
            Text("While tracking \(model.label(for: prompt.projectId)).")
                .foregroundStyle(.secondary)
                .font(.caption)
            HStack {
                Button("Keep") { model.resolveIdle(.keep) }
                Button("Discard") { model.resolveIdle(.discard) }
                Button("Split") { model.resolveIdle(.split) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func splitFollowUpSection(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Idle Session").font(.headline)
            Text("Assign to a Project or drop it.")
                .foregroundStyle(.secondary)
                .font(.caption)
            ForEach(model.projects) { project in
                Button("Assign to \(model.label(for: project.id!))") {
                    model.assignSplitIdle(to: project)
                }
                .disabled(project.id == session.projectId)
            }
            Button("Drop", role: .destructive) { model.dropSplitIdle() }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
