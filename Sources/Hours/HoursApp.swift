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

@MainActor @Observable
final class TrayModel {
    private let tracker: Tracker
    private(set) var projects: [Project] = []
    private(set) var clients: [Int64: String] = [:]
    private(set) var running: Session?
    var error: String?

    init() {
        do {
            let dir = URL.applicationSupportDirectory.appending(path: "Hours")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            tracker = try Tracker(path: dir.appending(path: "hours.sqlite").path, clock: SystemClock())
        } catch {
            fatalError("Cannot open the Hours database: \(error)")
        }
        Self.registerLoginItemOnFirstInstall()
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
    }

    func refresh() {
        attempt {
            projects = try tracker.projects()
            clients = Dictionary(uniqueKeysWithValues: try tracker.clients().map { ($0.id!, $0.name) })
            running = try tracker.runningSession()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Button("Quit Hours") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 300)
    }
}
