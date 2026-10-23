import AppKit
import CoreGraphics
import WabbitCore
import ServiceManagement
import Sparkle
import SwiftUI

@main
struct WabbitApp: App {
    @State private var model = TrayModel()

    var body: some Scene {
        MenuBarExtra {
            TrayView(model: model)
        } label: {
            if let running = model.running {
                // `model.now` ticks once a minute while a Session runs (footprint budget).
                Label {
                    Text("\(model.shortName(for: running.projectId)) \(Self.hm(model.now.timeIntervalSince(running.start)))")
                } icon: {
                    Self.trayIcon(Self.runningIcon, fallback: "stop.circle.fill")
                }
            } else {
                Self.trayIcon(Self.idleIcon, fallback: "clock")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Wabbit", id: "main") {
            MainView(model: model)
        }
    }
}

extension WabbitApp {
    /// Menu-bar icons from the SVGs in the bundle (scripts/build-app.sh copies icons/), loaded once and drawn
    /// as templates so macOS tints them; nil under `swift run`, which has no bundle resources.
    static let idleIcon = templateSVG("wabbit-idle"), runningIcon = templateSVG("wabbit-running")

    private static func templateSVG(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"), let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 16 * img.size.width / img.size.height, height: 16)
        return img
    }

    @ViewBuilder static func trayIcon(_ image: NSImage?, fallback: String) -> some View {
        if let image { Image(nsImage: image) } else { Image(systemName: fallback) }
    }

    static func hm(_ t: TimeInterval) -> String {
        let m = max(0, Int(t / 60))
        return m < 60 ? "\(m)m" : "\(m / 60)h\(String(format: "%02d", m % 60))"
    }
}

enum Pane: Hashable, Identifiable {
    case overview, sessions, export, clients, watched, config, notifications, backup
    var id: Self { self }
    static let sections: [(title: String, panes: [Pane])] = [
        ("Data", [.overview, .sessions, .export]),
        ("Setup", [.clients, .watched]),
        ("Settings", [.config, .notifications, .backup]),
    ]
    var title: String {
        switch self {
        case .overview: "Overview"
        case .sessions: "Sessions"
        case .export: "Export"
        case .clients: "Clients & Projects"
        case .watched: "Watched Apps"
        case .config: "Config"
        case .notifications: "Notifications"
        case .backup: "Backup & Restore"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "chart.bar"
        case .sessions: "list.bullet.rectangle"
        case .export: "square.and.arrow.up"
        case .clients: "person.2"
        case .watched: "macwindow"
        case .config: "gearshape"
        case .notifications: "bell"
        case .backup: "externaldrive"
        }
    }
}

extension View {
    /// macOS 26+: native scroll-edge effect under the toolbar. macOS 14-15: hide the toolbar band, which is wider than the content.
    @ViewBuilder func toolbarEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { toolbarBackground(.hidden, for: .windowToolbar) }
    }

    /// A pane's primary toolbar action: prominent Liquid Glass on macOS 26+, default toolbar button before.
    @ViewBuilder func primaryToolbarButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { self }
    }

    /// Editor sheets: the system form size on macOS 26+, a fixed width before.
    @ViewBuilder func formSheet(width: CGFloat) -> some View {
        if #available(macOS 26, *) { presentationSizing(.form) } else { frame(width: width) }
    }
}

/// The one app window: sidebar of panes, detail on the right.
struct MainView: View {
    @Bindable var model: TrayModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.pane) {
                ForEach(Pane.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.panes) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail.navigationTitle(model.pane.title).errorAlert($model.error).toolbarEdge()
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder private var detail: some View {
        switch model.pane {
        case .overview: OverviewView(model: model)
        case .sessions: SessionsView(model: model)
        case .export: ExportView(model: model)
        case .clients: ManageView(model: model)
        case .watched: WatchedAppsView(model: model)
        case .config: ConfigView(model: model)
        case .notifications: NotificationsView(model: model)
        case .backup: BackupView(model: model)
        }
    }
}

extension View {
    /// Shows `error` as an alert; dismissing it clears it.
    func errorAlert(_ error: Binding<String?>) -> some View {
        alert(error.wrappedValue ?? "", isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {}
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
    private var lastInputBeforeSleep: Date?

    private(set) var projects: [Project] = []
    private(set) var clients: [Int64: String] = [:]
    private(set) var running: Session?
    /// Top N Open Projects by recent use; the rest of `projects` go under "Other…".
    private(set) var quickStart: [Project] = []
    /// Refreshed every 60 s while a Session runs, and on wake; drives the tray label.
    private(set) var now = Date()
    private var tick: Timer?
    static let quickStartCount = 3
    private(set) var allProjects: [Project] = []
    private(set) var allClients: [Client] = []
    private(set) var closedIds: Set<Int64> = []
    private(set) var domains: [Int64: [String]] = [:]
    private(set) var folders: [Int64: [ProjectFolder]] = [:]
    private(set) var addresses: [Int64: [ProjectAddress]] = [:]
    var hasOpenAddresses: Bool { addresses.contains { !closedIds.contains($0.key) && !$0.value.isEmpty } }
    private(set) var idleThresholdMinutes: Int = 15
    private(set) var idlePrompt: IdlePrompt? { didSet { if idlePrompt != oldValue { notifyIdle() } } }
    private(set) var watchedPrompt: WatchedAppPrompt? { didSet { if watchedPrompt != oldValue { notifyWatched(); watchedPanel?.close(); watchedPanel = nil } } }
    /// Prompts that also post a macOS notification (Notifications.swift).
    private(set) var notifyOn: Set<NotifiedPrompt> = []
    let notifier = Notifier()
    private(set) var watchedApps: [WatchedApp] = []
    private(set) var watchedDelaySeconds = 30
    /// Folder signals from developer tools (herdr, Claude Code hook via `signalSocket`); off by default.
    private(set) var folderSignals = false
    private(set) var workingHours = WorkingHours()
    private var signalSocket: FolderSignalSocket?
    private(set) var titleRules: [String: [TitleRule]] = [:]
    /// Idle Session left by Split, awaiting assign or drop.
    private(set) var splitIdleSession: Session?
    var error: String?
    /// Main window's selected pane; the tray can open it at a given one.
    var pane: Pane = .overview
    /// Clients & Projects' selected Client, kept while the app runs (nil: the first one).
    var selectedClientId: Int64?
    private(set) var amountMode = AmountMode.gross
    private(set) var taxBps = 0
    private(set) var defaultRateCents: Int?
    private(set) var roundingStepMinutes = 60
    private(set) var roundingThresholdMinutes = 15
    /// Meeting Prompt (ticket 08): see MediaDetection.swift.
    var meetingPrompt: MeetingPrompt? { didSet { if meetingPrompt != oldValue { notifyMeeting() } } }
    var meetingPanel: NSPanel?
    var watchedPanel: NSPanel?
    let calendar = CalendarAccess()
    private var media: MediaDetection?
    /// Sparkle (ticket 13). Started only when the build embedded an EdDSA public key
    /// (scripts/build-app.sh, SPARKLE_PUBLIC_ED_KEY); dev builds without one never check.
    let updater = SPUStandardUpdaterController(
        startingUpdater: TrayModel.updatesEnabled, updaterDelegate: nil, userDriverDelegate: nil)
    static let updatesEnabled = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.isEmpty == false

    /// Idle is polled at most every 30 s (footprint budget / ticket 07).
    static let idlePollInterval: TimeInterval = 30

    init() {
        do {
            let fm = FileManager.default, dir = URL.applicationSupportDirectory.appending(path: "Wabbit"), old = URL.applicationSupportDirectory.appending(path: "Hours")
            // One-time move of the pre-rename data folder; never deletes on failure, leaves "Hours" alone if both exist.
            if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: old.path) {
                do { try fm.moveItem(at: old, to: dir) } catch { try? fm.copyItem(at: old, to: dir) }
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            tracker = try Tracker(path: dir.appending(path: "hours.sqlite").path, clock: SystemClock())
        } catch {
            fatalError("Cannot open the Wabbit database: \(error)")
        }
        tracker.connect(feed)
        notifier.model = self
        notifier.start()  // delegate set before any notification is posted
        Self.registerLoginItemOnFirstInstall()
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
        startIdlePolling()
        media = MediaDetection { [weak self] in self?.mediaChanged($0) }
        activeApp = ActiveAppObserver(feed: feed, isWatched: { [weak self] id in
            self?.watchedApps.contains { $0.bundleID == id } == true
        }, signalsOn: { [weak self] in self?.folderSignals == true },
           addressesOn: { [weak self] in self?.hasOpenAddresses == true }) { [weak self] in self?.scheduleWatchedCheck() }
        scheduleWatchedCheck()
        updateSignalSocket()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.signalSocket?.stop() } }
        // After sleep, timers are stale: re-read the running Session and the clock.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.lastInputBeforeSleep = Date().addingTimeInterval(-Self.secondsSinceInput()) } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.didWake() } }
    }

    /// One-shot timer for when the front app's delay is up; nothing runs while no app is waiting.
    /// When a snooze or working hours hold the prompt back, the check is set for when they end.
    func scheduleWatchedCheck() {
        watchedTimer?.invalidate()
        watchedPrompt = tracker.pendingWatchedAppPrompt()
        var delay = TimeInterval(watchedDelaySeconds)
        if let resume = tracker.watchedPromptResumeAt() { delay = max(delay, resume.timeIntervalSinceNow) }
        watchedTimer = Timer.scheduledTimer(withTimeInterval: delay + 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.watchedPrompt = self?.tracker.pendingWatchedAppPrompt() }
        }
    }

    func setWorkingHours(_ w: WorkingHours) {
        act { try tracker.setWorkingHours(w) }
        scheduleWatchedCheck()
    }

    func setFolderSignals(_ on: Bool) {
        act { try tracker.setFolderSignalsEnabled(on) }
        updateSignalSocket()
    }

    /// The socket exists only while folder signals are on.
    private func updateSignalSocket() {
        if folderSignals, signalSocket == nil {
            signalSocket = FolderSignalSocket { [weak self] line in
                self?.feed.emit(.folderSignal(path: line))
                self?.scheduleWatchedCheck()
            }
        } else if !folderSignals {
            signalSocket?.stop()
            signalSocket = nil
            unlink(FolderSignalSocket.path)  // one left by a crash or kill
        }
    }

    func color(for projectId: Int64) -> ProjectColor? {
        allProjects.first { $0.id == projectId }?.color
    }

    func client(for projectId: Int64) -> Client? {
        allProjects.first { $0.id == projectId }.flatMap { p in allClients.first { $0.id == p.clientId } }
    }

    /// A Client's tile colour where no Project is beside it: its first Open Project's, else gray.
    func clientColor(_ c: Client) -> ProjectColor {
        allProjects.first { $0.clientId == c.id && $0.closedAt == nil }?.color ?? .gray
    }

    func setIcon(_ c: Client, _ svg: String?) {
        act {
            do { try tracker.setIcon(clientId: c.id!, svg: svg) } catch ClientIconError.tooLarge {
                throw FolderLinked(message: "That SVG is larger than 256 KB.")
            } catch ClientIconError.notSVG {
                throw FolderLinked(message: "That file isn't an SVG.")
            }
        }
    }

    func setColor(_ p: Project, _ c: ProjectColor) { act { try tracker.setColor(projectId: p.id!, c) } }

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
            folders = Dictionary(uniqueKeysWithValues: try allProjects.map { ($0.id!, try tracker.projectFolders(projectId: $0.id!)) })
            addresses = Dictionary(uniqueKeysWithValues: try allProjects.map { ($0.id!, try tracker.projectAddresses(projectId: $0.id!)) })
            clients = Dictionary(uniqueKeysWithValues: try tracker.clients().map { ($0.id!, $0.name) })
            running = try tracker.runningSession()
            quickStart = try tracker.quickStartProjects(limit: Self.quickStartCount)
            notifyOn = Set(try NotifiedPrompt.allCases.filter { try tracker.notifies($0) })
            idleThresholdMinutes = Int(try tracker.idleThreshold() / 60)
            idlePrompt = tracker.pendingIdlePrompt()
            watchedPrompt = tracker.pendingWatchedAppPrompt()
            watchedApps = try tracker.watchedApps()
            watchedDelaySeconds = Int(try tracker.watchedAppDelay())
            folderSignals = try tracker.folderSignalsEnabled()
            workingHours = tracker.workingHours()
            titleRules = Dictionary(uniqueKeysWithValues: try watchedApps.map { ($0.bundleID, try tracker.titleRules(bundleID: $0.bundleID)) })
            amountMode = try tracker.amountMode()
            taxBps = try tracker.taxRateBps()
            defaultRateCents = try tracker.defaultRateCents()
            roundingStepMinutes = Int(try tracker.roundingStep() / 60)
            roundingThresholdMinutes = Int(try tracker.roundingThreshold() / 60)
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
    func removeFolder(_ f: ProjectFolder) { act { try tracker.removeProjectFolder(id: f.id!) } }
    /// Folder picker (directories only), then links the folder to `p`.
    func addFolder(_ p: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        act {
            do { try tracker.addProjectFolder(projectId: p.id!, path: url.path) } catch ProjectFolderError.alreadyLinked(let other) {
                throw FolderLinked(message: "That folder is already linked to \(label(forAny: other)).")
            }
        }
    }
    func removeAddress(_ a: ProjectAddress) { act { try tracker.removeProjectAddress(id: a.id!) } }
    func addAddress(_ p: Project, _ address: String) {
        act {
            do { try tracker.addProjectAddress(projectId: p.id!, address: address) } catch ProjectAddressError.alreadyLinked(let other) {
                throw FolderLinked(message: "That website is already linked to \(label(forAny: other)).")
            } catch ProjectAddressError.invalid {
                throw FolderLinked(message: "That isn't a website or web address.")
            }
        }
    }
    private struct FolderLinked: Error, CustomStringConvertible { let message: String; var description: String { message } }
    /// Runs `body`, then refreshes; a failure stays in `error` (refresh would otherwise clear it).
    func act(_ body: () throws -> Void) {
        let ok = attempt(body), e = error
        refresh()
        if !ok { error = e }
    }
    func createClient(_ name: String, firstProject: String) -> Bool {
        attempt { selectedClientId = try tracker.createClient(name: name, firstProject: firstProject).0.id }
    }

    func setIdleThresholdMinutes(_ minutes: Int) { act { try tracker.setIdleThreshold(TimeInterval(minutes * 60)) } }
    func setAmountMode(_ m: AmountMode) { act { try tracker.setAmountMode(m) } }
    func setTaxRateBps(_ bps: Int) { act { try tracker.setTaxRateBps(bps) } }
    func setDefaultRateCents(_ cents: Int?) { act { try tracker.setDefaultRateCents(cents) } }
    func setRoundingStepMinutes(_ m: Int) { act { try tracker.setRoundingStep(TimeInterval(m * 60)) } }
    func setRoundingThresholdMinutes(_ m: Int) { act { try tracker.setRoundingThreshold(TimeInterval(m * 60)) } }

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

    /// Sleep counts as Idle: the input clock restarts on wake, so the stretch since the last input before
    /// sleep is reported here; the next poll sees fresh input and raises the usual Idle prompt.
    private func didWake() {
        refresh()
        if let last = lastInputBeforeSleep, Date().timeIntervalSince(last) >= TimeInterval(idleThresholdMinutes * 60) {
            feed.emit(.userIdle(since: last))
            wasPastIdleThreshold = true
        }
        lastInputBeforeSleep = nil
        pollIdle()
    }

    private static func secondsSinceInput() -> TimeInterval {
        // ~0 as event type = any input (keyboard, mouse, …). No permission needed.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func pollIdle() {
        let idleSeconds = Self.secondsSinceInput()
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

    /// Turn launch at login on once, the first time Wabbit runs from /Applications.
    /// Dev builds elsewhere never register themselves.
    private static func registerLoginItemOnFirstInstall() {
        let key = "didOfferLaunchAtLogin"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }
}

extension Color {
    private static func adaptive(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
    static let trayBody = adaptive(light: 0xFAFAF8, dark: 0x232325)
    static let trayBand = adaptive(light: 0xF1F0EE, dark: 0x2C2C2E)
    static let trayHover = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.07)
    static let footerHover = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.15, darkAlpha: 0.15)
}

extension View {
    /// Compact card for a tray prompt, sitting in the header band.
    func trayCard() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.trayBody, in: RoundedRectangle(cornerRadius: 8))
            .controlSize(.small)
    }
}

/// Footer icon button: rounded highlight on hover (15% black in light mode, 15% white in dark).
private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverLabel(configuration: configuration) }

    private struct HoverLabel: View {  // hover state lives in a view; ButtonStyle can't hold @State
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(hovering || configuration.isPressed ? Color.footerHover : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
        }
    }
}

/// Keeps the MenuBarExtra panel as tall as its content: macOS grows the panel when content grows
/// but never shrinks it, leaving an empty band (e.g. after an Idle prompt is resolved). Top edge stays put.
private struct PanelFitter: NSViewRepresentable {
    let height: CGFloat
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let height = height
        DispatchQueue.main.async {
            guard let window = view.window, height > 0 else { return }
            var frame = window.frame
            let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: frame.width, height: height))).height
            guard abs(target - frame.height) > 0.5 else { return }
            frame.origin.y += frame.height - target
            frame.size.height = target
            window.setFrame(frame, display: true)
        }
    }
}

/// A full-width row with a hover highlight.
private struct TrayRow<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovering = false
    var body: some View {
        content
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.trayHover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct TrayView: View {
    let model: TrayModel
    @Environment(\.openWindow) private var openWindow

    /// Opens the main window at a pane (nil: its last one).
    private func open(_ pane: Pane?) {
        if let pane { model.pane = pane }
        let panel = NSApp.keyWindow  // the MenuBarExtra panel
        openWindow(id: "main")
        panel?.orderOut(nil)
        NSApplication.shared.activate()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 2) { recent }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.trayBody)
            Divider()
            footer
        }
        .frame(width: 320)
        .background(Color.trayBody.ignoresSafeArea())
        .background { GeometryReader { PanelFitter(height: $0.size.height) } }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if model.meetingPrompt != nil { MeetingPromptView(model: model) }
            if let prompt = model.idlePrompt {
                idlePromptSection(prompt)
            } else if let split = model.splitIdleSession {
                splitFollowUpSection(split)
            } else if let watched = model.watchedPrompt {
                WatchedAppPromptSection(model: model, prompt: watched)
            }
            if let running = model.running {
                HStack(spacing: 10) {
                    ClientIcon(client: model.client(for: running.projectId), color: model.color(for: running.projectId), size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.client(for: running.projectId)?.name ?? "?").font(.body.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            ProjectDot(color: model.color(for: running.projectId))
                            Text(model.shortName(for: running.projectId)).lineLimit(1)
                            Text("·")
                            Text(running.start, style: .timer).monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.stop(); model.refresh() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 28)).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .help("Stop")
                    .accessibilityLabel("Stop")
                }
            } else {
                Text("Not tracking").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.trayBand.ignoresSafeArea())
    }

    @ViewBuilder
    private var recent: some View {
        if model.projects.isEmpty {
            Text("Add a Client and its first Project to start tracking.")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        } else {
            Text("Recent").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 2)
        }
        ForEach(model.quickStart) { project in
            let isRunning = model.running?.projectId == project.id
            Button { model.start(project); model.refresh() } label: {
                TrayRow {
                    HStack(spacing: 10) {
                        ClientIcon(client: model.client(for: project.id!), color: project.color, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.clients[project.clientId] ?? "?").font(.body.weight(.semibold)).lineLimit(1)
                            HStack(spacing: 5) {
                                ProjectDot(color: project.color)
                                Text(project.name).lineLimit(1)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isRunning ? "checkmark.circle.fill" : "play.circle")
                            .font(.system(size: 18)).foregroundStyle(isRunning ? Color.accentColor : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
        let others = model.projects.filter { p in !model.quickStart.contains { $0.id == p.id } }
        if !others.isEmpty {
            TrayRow {
                Menu {
                    ForEach(others) { project in
                        Button("\(model.clients[project.clientId] ?? "?") › \(project.name)") { model.start(project); model.refresh() }
                    }
                } label: {
                    HStack { Text("Other…"); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        if let error = model.error {
            Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal, 8).padding(.top, 4)
        }
    }

    private var footer: some View {
        HStack {
            footerButton("plus", "New Client or Project") { open(.clients) }
            Spacer()
            footerButton("hare", "Open Wabbit") { open(nil) }.keyboardShortcut(",")
            Spacer()
            footerButton("power", "Quit Wabbit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(.horizontal, 32).padding(.vertical, 10)
        .background(Color.trayBand.ignoresSafeArea())
    }

    private func footerButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 18)).frame(width: 40, height: 32) }
            .buttonStyle(FooterButtonStyle())
            .help(title)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private func idlePromptSection(_ prompt: IdlePrompt) -> some View {
        let minutes = Int(prompt.idleEnd.timeIntervalSince(prompt.idleStart) / 60)
        VStack(alignment: .leading, spacing: 6) {
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
        .trayCard()
    }

    @ViewBuilder
    private func splitFollowUpSection(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Idle Session").font(.headline)
            Text("Assign to a Project or drop it.")
                .foregroundStyle(.secondary)
                .font(.caption)
            HStack {
                Menu("Assign to") {
                    // Open Projects only (`model.projects`), grouped by Client.
                    ForEach(Dictionary(grouping: model.projects, by: \.clientId).sorted { (model.clients[$0.key] ?? "") < (model.clients[$1.key] ?? "") }, id: \.key) { clientId, projects in
                        Section(model.clients[clientId] ?? "?") {
                            ForEach(projects) { project in
                                Button(project.name) { model.assignSplitIdle(to: project) }
                                    .disabled(project.id == session.projectId)
                            }
                        }
                    }
                }
                .fixedSize()
                Button("Drop", role: .destructive) { model.dropSplitIdle() }
            }
        }
        .trayCard()
    }
}

/// Clients & Projects: Clients in a secondary sidebar on the left, the selected Client's details on the right.
/// A Client in the Clients list: icon, name, Project count; hover highlight (selection is the list's own).
private struct ClientListRow: View {
    let client: Client
    let color: ProjectColor
    let projects: Int
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            ClientIcon(client: client, color: color, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(client.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(projects == 1 ? "1 Project" : "\(projects) Projects").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(client.closedAt == nil ? 1 : 0.5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .listRowBackground(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.06) : .clear).padding(.horizontal, 6))
    }
}

/// HSplitView rather than a nested NavigationSplitView: a second split view inside the outer one's detail
/// fights it for the window toolbar and sidebar toggle; HSplitView is a plain AppKit split.
struct ManageView: View {
    @Bindable var model: TrayModel
    @State private var creating = false
    @State private var editing: Project?

    /// Open Clients first, Closed ones at the bottom; each group by name.
    private var clients: [Client] { model.allClients.filter { $0.closedAt == nil } + model.allClients.filter { $0.closedAt != nil } }
    private var selected: Client? { clients.first { $0.id == model.selectedClientId } ?? clients.first }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                // Tags must be the non-optional id: an `Int64?` tag never matches the selection, so clicks did nothing.
                List(selection: Binding(get: { selected?.id }, set: { model.selectedClientId = $0 })) {
                    ForEach(clients) { c in
                        ClientListRow(client: c, color: model.clientColor(c),
                                      projects: model.allProjects.filter { $0.clientId == c.id }.count)
                            .tag(c.id!)
                    }
                }
                .listStyle(.inset)
                Divider()
                HStack {
                    Button("New Client…", systemImage: "plus") { creating = true }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("New Client")
                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 150, idealWidth: 180, maxWidth: 220)
            Group {
                if let client = selected { details(client) } else {
                    Text("Add a Client and its first Project with +.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editing) { p in MoneyEditor(model: model, project: p) { editing = nil } }
        .sheet(isPresented: $creating) { NewClientSheet(model: model) { creating = false } }
    }

    private func details(_ client: Client) -> some View {
        List {
            Section {
                ClientRow(model: model, client: client)
            }
            ForEach(model.allProjects.filter { $0.clientId == client.id }) { p in
                Section {
                    HStack {
                        ClientIcon(client: client, color: p.color, size: 20)
                        ProjectColorMenu(color: p.color) { model.setColor(p, $0) }
                        NameField(text: p.name) { model.renameProject(p, $0) }
                            .opacity(model.closedIds.contains(p.id!) ? 0.5 : 1)
                        Button("Rate & Billing…") { editing = p }
                        Button(p.closedAt == nil ? "Close" : "Reopen") { model.setClosed(p, p.closedAt == nil) }
                        InfoButton("""
                            The dot sets the Project's colour, shown in Overview, Sessions and the tray.
                            Rate & Billing: the hourly Rate, and whether it's billed Hourly or for a Fixed price with estimated hours.
                            Close: archive the Project. Its time stays in reports, but it can't be tracked and leaves the tray.
                            """)
                    }
                    ProjectFoldersRow(model: model, project: p)
                }
            }
            Section {
                NameField(text: "", prompt: "Add Project") { model.addProject(client, $0) }
            }
        }
        .id(client.id)  // fresh field state per Client
    }
}

/// The New Client form, in a sheet from the Clients list's +.
struct NewClientSheet: View {
    let model: TrayModel
    let done: () -> Void
    @State private var name = ""
    @State private var firstProject = ""

    var body: some View {
        Form {
            Section("New Client") {
                TextField("Client name", text: $name)
                TextField("First Project", text: $firstProject)
            }
        }
        .formStyle(.grouped)
        .formSheet(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done).keyboardShortcut(.cancelAction) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { if model.createClient(name, firstProject: firstProject) { model.refresh(); done() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || firstProject.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// A Project's folders and Project-related websites (`ProjectAddress`): a Watched App's front document inside a
/// folder, or a Watched browser's front tab under a website, suggests this Project.
/// A small ⓘ that shows a short explanation in a popover.
struct InfoButton: View {
    let text: String
    @State private var shown = false
    init(_ text: String) { self.text = text }
    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("What is this?")
            .accessibilityLabel("Info")
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).font(.callout).frame(width: 280, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(12)
            }
    }
}

struct ProjectFoldersRow: View {
    let model: TrayModel
    let project: Project
    @State private var address = ""
    var body: some View {
        HStack(spacing: 4) {
            Text("Project folders").font(.caption).foregroundStyle(.secondary)
            InfoButton("When a Watched App has a file from one of these folders in front (or a Watched terminal is in one), Wabbit suggests this Project. Subfolders count; the deepest match wins.")
        }
        .padding(.leading, 24)
        ForEach(model.folders[project.id!] ?? []) { f in
            HStack {
                Label((f.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                Button("Remove", systemImage: "minus.circle") { model.removeFolder(f) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            .padding(.leading, 24)
        }
        Button("Add Folder…") { model.addFolder(project) }
            .buttonStyle(.link).padding(.leading, 24)
        HStack(spacing: 4) {
            Text("Project-related websites").font(.caption).foregroundStyle(.secondary)
            InfoButton("When a Watched browser (Safari or a Chrome-based one, after you allow it in Watched Apps) shows a page on one of these sites, Wabbit suggests this Project. Paths match whole segments; the longest match wins. Firefox can't report its address.")
        }
        .padding(.leading, 24)
        ForEach(model.addresses[project.id!] ?? []) { a in
            HStack {
                Label(a.display, systemImage: "globe")
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                Button("Remove", systemImage: "minus.circle") { model.removeAddress(a) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            .padding(.leading, 24)
        }
        LabeledContent("Add Website…") { TextField("Add Website…", text: $address, prompt: Text("github.com/acme or a full URL")).labelsHidden() }
            .onSubmit {
                model.addAddress(project, address)
                if model.error == nil { address = "" }
            }
            .padding(.leading, 24)
    }
}

struct ClientRow: View {
    let model: TrayModel
    let client: Client
    @State private var domain = ""
    var body: some View {
        ClientIconWell(model: model, client: client)
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
