import AppKit
import HoursCore
import SwiftUI
import UniformTypeIdentifiers

/// Back up to / restore from a single file. Restore asks for confirmation first.
struct BackupView: View {
    let model: TrayModel
    @State private var message: String?

    var body: some View {
        Form {
            Button("Back Up…") { backUp() }
            Button("Restore…") { restore() }
            if let message { Text(message).foregroundStyle(.secondary) }
        }
        .padding()
        .frame(width: 340)
    }

    private func backUp() {
        let panel = NSSavePanel()
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Hours-backup-\(stamp).sqlite"
        panel.allowedContentTypes = [.database]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.tracker.backup(to: url)
            message = "Backed up to \(url.lastPathComponent)."
        } catch { message = "Backup failed: \(error.localizedDescription)" }
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.database]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Replace all current data?"
        alert.informativeText = "Clients, Projects and Sessions will be replaced by the contents of \(url.lastPathComponent). This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try model.tracker.restore(from: url)
            model.refresh()
            message = "Restored from \(url.lastPathComponent)."
        } catch BackupError.newerThanApp {
            message = "That backup was made by a newer version of Hours. Nothing was changed."
        } catch BackupError.notABackup {
            message = "That file isn't an Hours backup. Nothing was changed."
        } catch { message = "Restore failed: \(error.localizedDescription). Your data was kept." }
    }
}
