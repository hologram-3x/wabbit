import AppKit
import HoursCore
import SwiftUI
import UniformTypeIdentifiers

/// Minimal Export UI: pick scope and Precise/Rounded, then NSSavePanel for the file.
struct ExportView: View {
    let model: TrayModel
    @State private var kind = ScopeKind.project
    @State private var projectId: Int64?
    @State private var clientId: Int64?
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var to = Date.now
    @State private var mode = ExportMode.precise
    @State private var message: String?

    private enum ScopeKind: String, CaseIterable, Identifiable {
        case project, client, dateRange
        var id: String { rawValue }
        var label: String {
            switch self {
            case .project: "Project"
            case .client: "Client"
            case .dateRange: "Date range"
            }
        }
    }

    var body: some View {
        Form {
            Picker("Export", selection: $kind) {
                ForEach(ScopeKind.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)

            switch kind {
            case .project:
                Picker("Project", selection: $projectId) {
                    Text("Select…").tag(Optional<Int64>.none)
                    ForEach(model.allProjects) { p in
                        Text(fullLabel(p)).tag(Optional(p.id!))
                    }
                }
            case .client:
                Picker("Client", selection: $clientId) {
                    Text("Select…").tag(Optional<Int64>.none)
                    ForEach(model.allClients) { c in
                        Text(c.name).tag(Optional(c.id!))
                    }
                }
            case .dateRange:
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("To", selection: $to, displayedComponents: .date)
            }

            Picker("Mode", selection: $mode) {
                Text("Precise").tag(ExportMode.precise)
                Text("Rounded").tag(ExportMode.rounded)
            }.pickerStyle(.segmented)

            if mode == .rounded {
                Text("Each Session rounds to \(model.roundingStepMinutes < 60 ? "\(model.roundingStepMinutes) min" : "1 h") steps, down when at most \(model.roundingThresholdMinutes) min past. Change in Config.")
                    .foregroundStyle(.secondary).font(.caption)
            }

            if let message {
                Text(message).foregroundStyle(.secondary).font(.caption)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save CSV…") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .onAppear {
            projectId = model.allProjects.first?.id
            clientId = model.allClients.first?.id
        }
    }

    private var canSave: Bool {
        switch kind {
        case .project: projectId != nil
        case .client: clientId != nil
        case .dateRange: from <= to
        }
    }

    private func fullLabel(_ p: Project) -> String {
        let client = model.allClients.first { $0.id == p.clientId }?.name ?? "?"
        return "\(client) / \(p.name)"
    }

    private func save() {
        do {
            let scope: ExportScope = switch kind {
            case .project: .project(projectId!)
            case .client: .client(clientId!)
            case .dateRange:
                .dateRange(from ..< Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!)
            }
            let csv = try model.tracker.exportCSV(scope: scope, mode: mode)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = "hours-export.csv"
            panel.title = "Export Sessions"
            guard panel.runModal() == .OK, let url = panel.url else {
                message = "Save cancelled."
                return
            }
            try csv.data(using: .utf8)!.write(to: url)
            message = "Saved \(url.lastPathComponent)."
            model.error = nil
        } catch {
            model.error = "\(error)"
            message = nil
        }
    }
}
