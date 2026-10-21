import Foundation

/// Folder signals (project-folders 04): "working in <folder>" from developer tools (herdr's focused pane,
/// the Claude Code hook via the local socket). Opt-in. They only refine a Watched terminal in front:
/// fresh signal > AXDocument > title rules > default Project. The newest signal wins; it expires after
/// `folderSignalLifetime` without a new one.
extension Tracker {
    public static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty",
    ]
    public static let folderSignalLifetime: TimeInterval = 5 * 60
    public static let folderSignalMaxBytes = 1024
    static let folderSignalsKey = "folderSignals"

    /// Off by default.
    public func folderSignalsEnabled() throws -> Bool {
        try db.read { try Self.setting($0, Self.folderSignalsKey) == "1" }
    }

    /// Turning it off also drops the current signal.
    public func setFolderSignalsEnabled(_ on: Bool) throws {
        try db.write { try Self.setSetting($0, Self.folderSignalsKey, on ? "1" : "0") }
        if !on { watched.signal = nil }
    }

    /// The path a signal may carry: absolute, at most `folderSignalMaxBytes`, an existing directory. Untrusted input.
    public static func validFolderSignal(_ raw: String) -> String? {
        let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDir: ObjCBool = false
        guard p.hasPrefix("/"), p.utf8.count <= folderSignalMaxBytes, !p.contains("\0"),
              FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        return p
    }

    func handleFolderSignal(_ event: DetectionEvent) {
        guard case .folderSignal(let raw) = event, (try? folderSignalsEnabled()) == true,
              let path = Self.validFolderSignal(raw) else { return }
        watched.signal = (Self.normalisedPath(path).lowercased(), clock.now())
    }

    /// The signal's path (normalised, lowercased) when the front app is a terminal and the signal is fresh.
    func freshFolderSignal(frontApp id: String) -> String? {
        guard Self.terminalBundleIDs.contains(id), let s = watched.signal,
              clock.now().timeIntervalSince(s.at) < Self.folderSignalLifetime else { return nil }
        return s.path
    }
}

/// `herdr api snapshot` output: the focused pane's folder (`foreground_cwd`, else `cwd`).
public enum HerdrSnapshot {
    private struct Root: Decodable { let result: Result }
    private struct Result: Decodable { let snapshot: Snapshot }
    private struct Snapshot: Decodable { let focused_pane_id: String?; let panes: [Pane] }
    private struct Pane: Decodable { let pane_id: String; let cwd: String?; let foreground_cwd: String? }

    public static func focusedFolder(_ json: Data) -> String? {
        guard let s = try? JSONDecoder().decode(Root.self, from: json).result.snapshot,
              let pane = s.panes.first(where: { $0.pane_id == s.focused_pane_id }) else { return nil }
        return pane.foreground_cwd ?? pane.cwd
    }
}
