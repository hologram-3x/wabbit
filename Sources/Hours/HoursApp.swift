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
            if let running = model.running {
                // `model.now` ticks once a minute while a Session runs (footprint budget).
                Label("\(model.shortName(for: running.projectId)) \(Self.hm(model.now.timeIntervalSince(running.start)))",
                      systemImage: "stop.circle.fill")
            } else {
                Image(systemName: "clock")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Manage Clients", id: "manage") {
            ManageView(model: model)
        }

        Window("Overview", id: "overview") {
            OverviewView(model: model)
        }

        Window("Sessions", id: "sessions") {
            SessionsView(model: model)
        }

        Window("Export", id: "export") {
            ExportView(model: model)
        }

        Window("Backup", id: "backup") {
            BackupView(model: model)
        }

        Window("Watched Apps", id: "watched") {
            WatchedAppsView(model: model)
        }
    }
}

extension HoursApp {
    static func hm(_ t: TimeInterval) -> String {
        let m = max(0, Int(t / 60))
        return m < 60 ? "\(m)m" : "\(m / 60)h\(String(format: "%02d", m % 60))"
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
    let tracker: Tracker
    let feed = AppDetectionFeed()
    private var activeApp: ActiveAppObserver?
    private var watchedTimer: Timer?
    private var idlePoll: Timer?
    private var wasPastIdleThreshold = false

    private(set) var projects: [Project] = []
    private(set) var clients: [Int64: String] = [:]
    private(set) var running: Session?
    /// Top N Open Projects by recent use; the rest of `projects` go under "Other…".
    private(set) var quickStart: [Project] = []
    /// Refreshed every 60 s while a Session runs, and on wake; drives the tray label.
    private(set) var now = Date()
    private var tick: Timer?
    static let quickStartCount = 5
    private(set) var allProjects: [Project] = []
    private(set) var allClients: [Client] = []
    private(set) var closedIds: Set<Int64> = []
    private(set) var domains: [Int64: [String]] = [:]
    private(set) var idleThresholdMinutes: Int = 15
    private(set) var idlePrompt: IdlePrompt?
    private(set) var watchedPrompt: WatchedAppPrompt?
    private(set) var watchedApps: [WatchedApp] = []
    private(set) var watchedDelaySeconds = 30
    private(set) var titleRules: [String: [TitleRule]] = [:]
    /// Idle Session left by Split, awaiting assign or drop.
    private(set) var splitIdleSession: Session?
    var error: String?
    /// Meeting Prompt (ticket 08): see MediaDetection.swift.
    var meetingPrompt: MeetingPrompt?
    var meetingPanel: NSPanel?
    let calendar = CalendarAccess()
    private var media: MediaDetection?

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
        media = MediaDetection { [weak self] in self?.mediaChanged($0) }
        activeApp = ActiveAppObserver(feed: feed) { [weak self] in self?.scheduleWatchedCheck() }
        scheduleWatchedCheck()
        // After sleep, timers are stale: re-read the running Session and the clock.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    /// One-shot timer for when the front app's delay is up; nothing runs while no app is waiting.
    private func scheduleWatchedCheck() {
        watchedTimer?.invalidate()
        watchedPrompt = tracker.pendingWatchedAppPrompt()
        let delay = TimeInterval(watchedDelaySeconds)
        watchedTimer = Timer.scheduledTimer(withTimeInterval: delay + 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.watchedPrompt = self?.tracker.pendingWatchedAppPrompt() }
        }
    }

    func shortName(for projectId: Int64) -> String {
        allProjects.first { $0.id == projectId }?.name ?? "?"
    }

    private func updateTick() {
        now = Date()
        if running == nil { tick?.invalidate(); tick = nil; return }
        guard tick == nil else { return }
        tick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    func refresh() {
        attempt {
            projects = try tracker.openProjects()
            allProjects = try tracker.projects()
            closedIds = Set(try tracker.closedProjects().compactMap(\.id))
            allClients = try tracker.clients()
            domains = Dictionary(uniqueKeysWithValues: try allClients.map { ($0.id!, try tracker.domains(clientId: $0.id!)) })
            clients = Dictionary(uniqueKeysWithValues: try tracker.clients().map { ($0.id!, $0.name) })
            running = try tracker.runningSession()
            quickStart = try tracker.quickStartProjects(limit: Self.quickStartCount)
            idleThresholdMinutes = Int(try tracker.idleThreshold() / 60)
            idlePrompt = tracker.pendingIdlePrompt()
            watchedPrompt = tracker.pendingWatchedAppPrompt()
            watchedApps = try tracker.watchedApps()
            watchedDelaySeconds = Int(try tracker.watchedAppDelay())
            titleRules = Dictionary(uniqueKeysWithValues: try watchedApps.map { ($0.bundleID, try tracker.titleRules(bundleID: $0.bundleID)) })
        }
        updateTick()
        updateMeetingPanel()
    }

    func label(for projectId: Int64) -> String {
        guard let p = projects.first(where: { $0.id == projectId }) else { return "?" }
        return "\(clients[p.clientId] ?? "?") / \(p.name)"
    }

    /// Client / Project for any Project, Closed ones included (Open ones only in `label(for:)`).
    func label(forAny projectId: Int64) -> String {
        guard let p = allProjects.first(where: { $0.id == projectId }) else { return "?" }
        return "\(clients[p.clientId] ?? "?") / \(p.name)"
    }

    func start(_ project: Project) { attempt { try tracker.start(projectId: project.id!) } }
    func stop() { attempt { try tracker.stop() } }
    func renameClient(_ c: Client, _ name: String) { act { try tracker.renameClient(id: c.id!, to: name) } }
    func renameProject(_ p: Project, _ name: String) { act { try tracker.renameProject(id: p.id!, to: name) } }
    func addProject(_ c: Client, _ name: String) { act { try tracker.addProject(clientId: c.id!, name: name) } }
    func setClosed(_ p: Project, _ closed: Bool) {
        act { closed ? try tracker.closeProject(id: p.id!) : try tracker.reopenProject(id: p.id!) }
    }
    func setClosed(_ c: Client, _ closed: Bool) {
        act { closed ? try tracker.closeClient(id: c.id!) : try tracker.reopenClient(id: c.id!) }
    }
    func addDomain(_ c: Client, _ d: String) { act { try tracker.addDomain(clientId: c.id!, d) } }
    func removeDomain(_ c: Client, _ d: String) { act { try tracker.removeDomain(clientId: c.id!, d) } }
    func act(_ body: () throws -> Void) { attempt(body); refresh() }
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
        watchedPrompt = tracker.pendingWatchedAppPrompt()
        let current = try? tracker.runningSession()
        if current != running { running = current; updateTick() }
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
    @Environment(\.openWindow) private var openWindow
    @State private var newClient = ""
    @State private var firstProject = ""

    private static let thresholdChoices = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.meetingPrompt != nil {
                MeetingPromptView(model: model)
                Divider()
            }
            if let prompt = model.idlePrompt {
                idlePromptSection(prompt)
                Divider()
            } else if let split = model.splitIdleSession {
                splitFollowUpSection(split)
                Divider()
            } else if let watched = model.watchedPrompt {
                WatchedAppPromptSection(model: model, prompt: watched)
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
            ForEach(model.quickStart) { project in
                HStack {
                    Text(model.label(for: project.id!))
                    Spacer()
                    Button("Start") { model.start(project); model.refresh() }
                        .disabled(model.running?.projectId == project.id)
                }
            }
            let others = model.projects.filter { p in !model.quickStart.contains { $0.id == p.id } }
            if !others.isEmpty {
                Menu("Other…") {
                    ForEach(others) { project in
                        Button(model.label(for: project.id!)) { model.start(project); model.refresh() }
                    }
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
            Button("Manage Clients…") {
                openWindow(id: "manage")
                NSApplication.shared.activate()
            }
            Button("Overview…") {
                openWindow(id: "overview")
                NSApplication.shared.activate()
            }
            Button("Sessions…") {
                openWindow(id: "sessions")
                NSApplication.shared.activate()
            }
            Button("Watched Apps…") {
                openWindow(id: "watched")
                NSApplication.shared.activate()
            }
            Button("Export…") {
                openWindow(id: "export")
                NSApplication.shared.activate()
            }
            Button("Backup & Restore…") {
                openWindow(id: "backup")
                NSApplication.shared.activate()
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

struct ManageView: View {
    let model: TrayModel
    var body: some View {
        List {
            ForEach(model.allClients) { client in
                Section {
                    ClientRow(model: model, client: client)
                    ForEach(model.allProjects.filter { $0.clientId == client.id }) { p in
                        HStack {
                            NameField(text: p.name) { model.renameProject(p, $0) }
                                .opacity(model.closedIds.contains(p.id!) ? 0.5 : 1)
                            Button(p.closedAt == nil ? "Close" : "Reopen") { model.setClosed(p, p.closedAt == nil) }
                        }
                    }
                    NameField(text: "", prompt: "Add Project") { model.addProject(client, $0) }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        .frame(minWidth: 460, minHeight: 360)
    }
}

struct ClientRow: View {
    let model: TrayModel
    let client: Client
    @State private var domain = ""
    var body: some View {
        HStack {
            NameField(text: client.name) { model.renameClient(client, $0) }.font(.headline)
            Button(client.closedAt == nil ? "Close Client" : "Reopen Client") {
                model.setClosed(client, client.closedAt == nil)
            }
        }
        HStack {
            ForEach(model.domains[client.id!] ?? [], id: \.self) { d in
                Button("\(d) \u{2715}") { model.removeDomain(client, d) }.buttonStyle(.bordered)
            }
            TextField("Add email domain", text: $domain).onSubmit {
                model.addDomain(client, domain); domain = ""
            }
        }
    }
}

/// Edits on Return; empty `text` plus a prompt makes it an "add" field that clears itself.
struct NameField: View {
    let text: String
    var prompt = "Name"
    let commit: (String) -> Void
    @State private var value = ""
    var body: some View {
        TextField(prompt, text: $value)
            .onAppear { value = text }
            .onChange(of: text) { value = text }
            .onSubmit { commit(value); if text.isEmpty { value = "" } }
    }
}
