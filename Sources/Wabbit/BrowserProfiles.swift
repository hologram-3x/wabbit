import Foundation

/// Browser Profile names of Chromium browsers (browser-profiles 01), from `Local State` → `profile.info_cache`
/// (`{"Profile 1": {"name": "OpenCom"}, …}`). The core matches the front window's title against them.
/// Arc is left out: it keeps no `Local State` (its profiles live in its Spaces) and its titles carry no profile.
enum ChromiumProfiles {
    private static let dirs = [
        "com.google.Chrome": "Google/Chrome", "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge", "com.vivaldi.Vivaldi": "Vivaldi", "net.imput.helium": "net.imput.helium",
    ]

    static func isSupported(_ bundleID: String) -> Bool { dirs[bundleID] != nil }

    /// Folder → name; nil for an unsupported browser or an unreadable file.
    static func names(_ bundleID: String) -> [String: String]? {
        guard let dir = dirs[bundleID],
              let data = try? Data(contentsOf: URL.applicationSupportDirectory.appending(path: dir).appending(path: "Local State")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]]
        else { return nil }
        return cache.compactMapValues { $0["name"] as? String }
    }
}
