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

        Window("Manage Clients", id: "manage") {
            ManageView(model: model)
        }
    }
}

@MainActor @Observable
final class TrayModel {
    private let tracker: Tracker
    private(set) var projects: [Project] = []
    private(set) var clients: [Int64: String] = [:]
    private(set) var running: Session?
    private(set) var allProjects: [Project] = []
    private(set) var allClients: [Client] = []
    private(set) var closedIds: Set<Int64> = []
    private(set) var domains: [Int64: [String]] = [:]
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
            projects = try tracker.openProjects()
            allProjects = try tracker.projects()
            closedIds = Set(try tracker.closedProjects().compactMap(\.id))
            allClients = try tracker.clients()
            domains = Dictionary(uniqueKeysWithValues: try allClients.map { ($0.id!, try tracker.domains(clientId: $0.id!)) })
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
    private func act(_ body: () throws -> Void) { attempt(body); refresh() }
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
    @Environment(\.openWindow) private var openWindow
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
            Button("Manage Clients…") {
                openWindow(id: "manage")
                NSApplication.shared.activate()
            }
            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Button("Quit Hours") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 300)
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
