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

    /// The browser's data folder, which holds `Local State`.
    static func dir(_ bundleID: String) -> URL? {
        dirs[bundleID].map { URL.applicationSupportDirectory.appending(path: $0) }
    }

    /// Folder → name; nil for an unsupported browser or an unreadable file.
    static func names(_ bundleID: String) -> [String: String]? {
        guard let dir = dir(bundleID),
              let data = try? Data(contentsOf: dir.appending(path: "Local State")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]]
        else { return nil }
        return cache.compactMapValues { $0["name"] as? String }
    }
}

/// Re-reads a browser's profile names when its `Local State` changes, so a profile added or renamed while the
/// browser stays in front counts at once. Chromium replaces the file atomically (temp file + rename), so the
/// browser's data folder is watched, not the file. Its writes come in bursts: one read 1 s after the last event,
/// handed on only when the names changed.
@MainActor
final class ChromiumProfilesWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pending: [String: DispatchWorkItem] = [:]
    private var last: [String: [String: String]?] = [:]
    private let changed: @MainActor (String, [String: String]?) -> Void

    init(changed: @escaping @MainActor (String, [String: String]?) -> Void) { self.changed = changed }

    /// Watches exactly these browsers (unsupported ones are skipped). A folder that doesn't exist yet (browser never
    /// run) is not watched; bringing the browser to the front still reads its names.
    func watch(_ bundleIDs: Set<String>) {
        let wanted = bundleIDs.filter(ChromiumProfiles.isSupported)
        for id in Set(sources.keys).subtracting(wanted) {
            sources.removeValue(forKey: id)?.cancel()
            pending.removeValue(forKey: id)?.cancel()
            last[id] = nil
        }
        for id in wanted.subtracting(sources.keys) {
            guard let dir = ChromiumProfiles.dir(id) else { continue }
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.schedule(id) } }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources[id] = source
            last.updateValue(ChromiumProfiles.names(id), forKey: id)
        }
    }

    private func schedule(_ id: String) {
        pending[id]?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.read(id) } }
        pending[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func read(_ id: String) {
        pending[id] = nil
        guard sources[id] != nil else { return }
        let names = ChromiumProfiles.names(id)
        guard last[id] != .some(names) else { return }
        last.updateValue(names, forKey: id)
        changed(id, names)
    }
}
