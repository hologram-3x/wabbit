import AppKit
import HoursCore
import SwiftUI

/// Turns `NSWorkspace.didActivateApplicationNotification` into `activeAppChanged` events.
/// Notification-driven: no polling. Window titles (for title rules) need Accessibility; without it they are nil. Hours itself is ignored so opening its
/// own windows doesn't count as leaving the Watched App.
@MainActor
final class ActiveAppObserver {
    private var token: NSObjectProtocol?
    private let feed: AppDetectionFeed
    private let titles = WindowTitleWatcher()
    private let onChange: @MainActor () -> Void

    init(feed: AppDetectionFeed, onChange: @escaping @MainActor () -> Void) {
        self.feed = feed
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
        titles.watch(pid: app.processIdentifier) { [weak self] title in
            self?.feed.emit(.activeAppChanged(bundleID: id, windowTitle: title))
            self?.onChange()
        }
    }
}

struct InstalledApp: Hashable {
    let bundleID: String
    let name: String

    /// Apps in the usual application folders (one level deep), by bundle identifier.
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", "/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        var found: [String: InstalledApp] = [:]
        for dir in dirs {
            for file in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appending(path: file)
                guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
                found[id] = InstalledApp(bundleID: id, name: file.replacingOccurrences(of: ".app", with: ""))
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct WatchedAppsView: View {
    let model: TrayModel
    @State private var installed: [InstalledApp] = []

    var body: some View {
        Form {
            Section("Window titles") {
                if AccessibilityAccess.granted {
                    Text("Accessibility is on: title rules can pick the Project.").font(.caption)
                } else {
                    Text("Title rules read the front window's title of a Watched App, which macOS only allows with the Accessibility permission. Hours reads nothing else and never records screens. Without it, prompts use the app's default Project.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Grant Accessibility…") { AccessibilityAccess.requestWithPrompt() }
                }
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
