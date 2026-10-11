import AppKit
import HoursCore
import SwiftUI

/// Turns `NSWorkspace.didActivateApplicationNotification` into `activeAppChanged` events.
/// Notification-driven: no polling, no permission. Hours itself is ignored so opening its
/// own windows doesn't count as leaving the Watched App.
@MainActor
final class ActiveAppObserver {
    private var token: NSObjectProtocol?
    private let feed: AppDetectionFeed
    private let onChange: @MainActor () -> Void

    init(feed: AppDetectionFeed, onChange: @escaping @MainActor () -> Void) {
        self.feed = feed
        self.onChange = onChange
        let me = Bundle.main.bundleIdentifier
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, id != me {
            feed.emit(.activeAppChanged(bundleID: id, windowTitle: nil))
        }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier, id != me else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.feed.emit(.activeAppChanged(bundleID: id, windowTitle: nil))
                self.onChange()
            }
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
            Stepper("Prompt after \(model.watchedDelaySeconds) s in front",
                    value: Binding(get: { model.watchedDelaySeconds }, set: { model.setWatchedDelay($0) }),
                    in: 5...600, step: 5)
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
                }
                Menu("Add app…") {
                    ForEach(installed.filter { app in !model.watchedApps.contains { $0.bundleID == app.bundleID } },
                            id: \.bundleID) { app in
                        Button(app.name) { model.setWatchedApp(app.bundleID, app.name, nil) }
                    }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 320)
        .onAppear { installed = InstalledApp.scan() }
        .onDisappear { installed = [] }
    }
}

/// Tray section for a due Watched App prompt.
struct WatchedAppPromptSection: View {
    let model: TrayModel
    let prompt: WatchedAppPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension TrayModel {
    func setWatchedApp(_ id: String, _ name: String, _ projectId: Int64?) {
        act { try tracker.setWatchedApp(bundleID: id, name: name, projectId: projectId) }
    }
    func removeWatchedApp(_ id: String) { act { try tracker.removeWatchedApp(bundleID: id) } }
    func setWatchedDelay(_ seconds: Int) { act { try tracker.setWatchedAppDelay(TimeInterval(seconds)) } }
    func acceptWatchedPrompt(projectId: Int64) { act { try tracker.start(projectId: projectId) } }
    func snoozeWatched(today: Bool) {
        today ? tracker.snoozeWatchedAppNotToday() : tracker.snoozeWatchedAppNotNow()
        refresh()
    }
}
