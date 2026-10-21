import AppKit
import WabbitCore
import SwiftUI

/// Turns `NSWorkspace.didActivateApplicationNotification` into `activeAppChanged` events.
/// Notification-driven: no polling. Window titles and documents are read for Watched Apps only (other apps are never
/// observed beyond their bundle ID) and need Accessibility; without it they are nil. Wabbit itself is ignored so opening its
/// own windows doesn't count as leaving the Watched App.
/// With folder signals on, a Watched terminal in front also asks herdr for its focused pane's folder, on the same events.
@MainActor
final class ActiveAppObserver {
    private var token: NSObjectProtocol?
    private let feed: AppDetectionFeed
    private let titles = WindowTitleWatcher()
    private let onChange: @MainActor () -> Void
    private let isWatched: @MainActor (String) -> Bool
    private let signalsOn: @MainActor () -> Bool
    /// pid + title herdr was last read for: re-read only when they change (herdr retitles on pane focus).
    private var herdrKey: String?
    private var herdrBusy = false, herdrAgain: pid_t?

    init(feed: AppDetectionFeed, isWatched: @escaping @MainActor (String) -> Bool, signalsOn: @escaping @MainActor () -> Bool,
         onChange: @escaping @MainActor () -> Void) {
        self.feed = feed
        self.isWatched = isWatched
        self.signalsOn = signalsOn
        self.onChange = onChange
        let me = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier, id != me {
            follow(front, id)
        }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let app, let id = app.bundleIdentifier, id != me else { return }
            MainActor.assumeIsolated { self?.follow(app, id) }
        }
    }

    /// Emits the app now and again on every window or title change while it stays in front.
    private func follow(_ app: NSRunningApplication, _ id: String) {
        guard isWatched(id) else {
            titles.stop()
            feed.emit(.activeAppChanged(bundleID: id, windowTitle: nil))
            return onChange()
        }
        herdrKey = nil
        let pid = app.processIdentifier
        titles.watch(pid: pid) { [weak self] title, doc in
            guard let self else { return }
            feed.emit(.activeAppChanged(bundleID: id, windowTitle: title, documentPath: doc))
            onChange()
            let key = "\(pid)|\(title ?? "")"
            if Tracker.terminalBundleIDs.contains(id), signalsOn(), key != herdrKey {
                herdrKey = key
                readHerdr(pid)
            }
        }
    }

    /// One `herdr api snapshot` at a time; changes meanwhile coalesce into one more read.
    private func readHerdr(_ pid: pid_t) {
        guard !herdrBusy else { herdrAgain = pid; return }
        herdrBusy = true
        Task { [weak self] in
            let folder = await Task.detached { Herdr.focusedFolder(terminalPid: pid) }.value
            guard let self else { return }
            herdrBusy = false
            if let folder { feed.emit(.folderSignal(path: folder)); onChange() }
            if let again = herdrAgain { herdrAgain = nil; readHerdr(again) }
        }
    }
}

struct InstalledApp: Hashable {
    let bundleID: String
    let name: String

    /// Apps in the usual application folders (one level deep), by bundle identifier.
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        var found: [String: InstalledApp] = [:]
        for dir in dirs {
            for file in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".app") {
                if let app = at(URL(fileURLWithPath: dir).appending(path: file)) { found[app.bundleID] = app }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func at(_ url: URL) -> InstalledApp? {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        return InstalledApp(bundleID: id, name: url.deletingPathExtension().lastPathComponent)
    }

    /// Any app, anywhere (e.g. apps kept on an external drive): an open panel limited to applications.
    @MainActor static func choose() -> InstalledApp? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Watch"
        return panel.runModal() == .OK ? panel.url.flatMap(at) : nil
    }
}

struct WatchedAppsView: View {
    let model: TrayModel
    @State private var installed: [InstalledApp] = []

    var body: some View {
        Form {
            Section("Window titles and documents") {
                if AccessibilityAccess.granted {
                    Text("Accessibility is on: Project folders and title rules can pick the Project.").font(.caption)
                } else {
                    Text("Project folders and title rules read the front window's document and title of a Watched App (other apps are never read), which macOS only allows with the Accessibility permission. Wabbit reads nothing else and never records screens. Without it, prompts use the app's default Project.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Grant Accessibility…") { AccessibilityAccess.requestWithPrompt() }
                }
            }
            Section("Developer tools") {
                Toggle("Use folder signals from developer tools (herdr, Claude Code hook)", isOn: Binding(
                    get: { model.folderSignals }, set: { model.setFolderSignals($0) }))
                Text("When a Watched terminal is in front, the folder you're working in (herdr's focused pane, or a folder sent by a Claude Code hook in the last 5 minutes) picks the Project through Project folders. Setup: docs/developer-tools.md in the Wabbit repository.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Watched Apps") {
                ForEach(model.watchedApps, id: \.bundleID) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Picker("Default Project", selection: Binding(
                            get: { app.projectId },
                            set: { model.setWatchedApp(app.bundleID, app.name, $0) }
                        )) {
                            Text("None").tag(Int64?.none)
                            ForEach(model.projects) { p in Text(model.label(for: p.id!)).tag(Int64?.some(p.id!)) }
                        }
                        .labelsHidden()
                        Button("Remove") { model.removeWatchedApp(app.bundleID) }
                    }
                    TitleRulesEditor(model: model, app: app)
                }
                Menu("Add app…") {
                    ForEach(installed.filter { app in !model.watchedApps.contains { $0.bundleID == app.bundleID } },
                            id: \.bundleID) { app in
                        Button(app.name) { model.setWatchedApp(app.bundleID, app.name, nil) }
                    }
                    Divider()
                    Button("Choose App…") {
                        if let app = InstalledApp.choose() { model.setWatchedApp(app.bundleID, app.name, nil) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { installed = InstalledApp.scan() }
        .onDisappear { installed = [] }
    }
}

/// Ordered rules for one Watched App: the first match picks the Project, else the default applies.
struct TitleRulesEditor: View {
    let model: TrayModel
    let app: WatchedApp
    @State private var kind = TitleRule.Kind.contains
    @State private var text = ""
    @State private var projectId: Int64?

    var body: some View {
        DisclosureGroup("Title rules (\(model.titleRules[app.bundleID]?.count ?? 0))") {
            let rules = model.titleRules[app.bundleID] ?? []
            ForEach(Array(rules.enumerated()), id: \.element.id) { i, rule in
                HStack {
                    Text("\(rule.kind == .contains ? "contains" : "matches") “\(rule.text)” → \(model.label(for: rule.projectId))")
                        .lineLimit(1)
                    Spacer()
                    Button("Up", systemImage: "arrow.up") { model.moveTitleRule(app.bundleID, rules, from: i, by: -1) }
                        .disabled(i == 0)
                    Button("Down", systemImage: "arrow.down") { model.moveTitleRule(app.bundleID, rules, from: i, by: 1) }
                        .disabled(i == rules.count - 1)
                    Button("Delete", systemImage: "trash") { model.removeTitleRule(rule.id!) }
                }
                .labelStyle(.iconOnly)
            }
            HStack {
                Picker("Match", selection: $kind) {
                    Text("Title contains").tag(TitleRule.Kind.contains)
                    Text("Matches pattern").tag(TitleRule.Kind.pattern)
                }
                .labelsHidden()
                TextField("acme-site", text: $text)
                Picker("Project", selection: $projectId) {
                    Text("Project…").tag(Int64?.none)
                    ForEach(model.projects) { p in Text(model.label(for: p.id!)).tag(Int64?.some(p.id!)) }
                }
                .labelsHidden()
                Button("Add") {
                    guard let projectId else { return }
                    model.addTitleRule(app.bundleID, kind, text, projectId)
                    if model.error == nil { text = "" }
                }
                .disabled(projectId == nil || text.isEmpty)
            }
        }
    }
}

/// Tray section for a due Watched App prompt.
struct WatchedAppPromptSection: View {
    let model: TrayModel
    let prompt: WatchedAppPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Track time for \(prompt.appName)?").font(.headline)
            if let id = prompt.projectId {
                Button((model.running == nil ? "Start " : "Switch to ") + model.label(for: id)) {
                    model.acceptWatchedPrompt(projectId: id)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Text("Pick a Project below to start.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Not now") { model.snoozeWatched(today: false) }
                Button("Not today") { model.snoozeWatched(today: true) }
            }
        }
        .trayCard()
    }
}

extension TrayModel {
    func setWatchedApp(_ id: String, _ name: String, _ projectId: Int64?) {
        act { try tracker.setWatchedApp(bundleID: id, name: name, projectId: projectId) }
    }
    func removeWatchedApp(_ id: String) { act { try tracker.removeWatchedApp(bundleID: id) } }
    func addTitleRule(_ id: String, _ kind: TitleRule.Kind, _ text: String, _ projectId: Int64) {
        act { try tracker.addTitleRule(bundleID: id, kind: kind, text: text, projectId: projectId) }
    }
    func removeTitleRule(_ id: Int64) { act { try tracker.removeTitleRule(id: id) } }
    func moveTitleRule(_ bundleID: String, _ rules: [TitleRule], from i: Int, by d: Int) {
        var ids = rules.compactMap(\.id)
        ids.swapAt(i, i + d)
        act { try tracker.setTitleRuleOrder(bundleID: bundleID, ids: ids) }
    }
    func setWatchedDelay(_ seconds: Int) { act { try tracker.setWatchedAppDelay(TimeInterval(seconds)) } }
    func acceptWatchedPrompt(projectId: Int64) { act { try tracker.start(projectId: projectId) } }
    func snoozeWatched(today: Bool) {
        today ? tracker.snoozeWatchedAppNotToday() : tracker.snoozeWatchedAppNotNow()
        refresh()
    }
}
