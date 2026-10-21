import AppKit
import CoreServices

/// The front tab's address of a Watched browser, via Apple Events (project-folders 03). Asked only on events
/// (front app or window title change), only when a Project has an address; the result is handed to the core
/// as a String and only compared there, never stored or logged.
/// Firefox has no AppleScript URL support and builds its Accessibility tree only for assistive tech, so it
/// is not supported: title rules apply (see ticket 03 notes).
enum BrowserAddress {
    private static let scripts: [String: String] = {
        var s = ["com.apple.Safari": "URL of current tab of front window"]
        for id in ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
                   "com.vivaldi.Vivaldi"] { s[id] = "URL of active tab of front window" }
        return s
    }()
    static let firefoxBundleIDs: Set<String> = ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]

    static func isSupported(_ bundleID: String) -> Bool { scripts[bundleID] != nil }

    enum Access: Sendable { case allowed, notAsked, denied, notRunning }

    /// Automation permission for `bundleID`. `ask: true` shows macOS's prompt and blocks until answered:
    /// call off the main actor.
    nonisolated static func access(_ bundleID: String, ask: Bool) -> Access {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .notRunning }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound): return .notRunning
        default: return .denied
        }
    }

    /// Front tab URL, or nil (not allowed yet, no window, timeout after 2 s). Never prompts. Off the main actor.
    nonisolated static func frontURL(bundleID: String) -> String? {
        guard let body = scripts[bundleID], access(bundleID, ask: false) == .allowed else { return nil }
        let source = "with timeout of 2 seconds\ntell application id \"\(bundleID)\" to \(body)\nend timeout"
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }
}
