import AppKit
import ApplicationServices

/// Accessibility permission (needed to read other apps' window titles; Screen Recording is not).
enum AccessibilityAccess {
    static var granted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt. Call only after Hours has explained why (see WatchedAppsView).
    static func requestWithPrompt() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// Reads the focused window title of one app and calls back when it changes
/// (`kAXFocusedWindowChangedNotification` + `kAXTitleChangedNotification`). Notification-driven, no polling.
/// Without the permission it reports nil and the core falls back to the app's default Project.
@MainActor
final class WindowTitleWatcher {
    private var observer: AXObserver?
    private var app: AXUIElement?
    private var window: AXUIElement?
    private var onChange: (@MainActor (String?) -> Void)?

    /// Starts watching `pid` (stopping any previous app) and reports the current title right away.
    func watch(pid: pid_t, onChange: @escaping @MainActor (String?) -> Void) {
        stop()
        self.onChange = onChange
        guard AccessibilityAccess.granted else { onChange(nil); return }
        let app = AXUIElementCreateApplication(pid)
        self.app = app
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<WindowTitleWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                if (notification as String) == kAXFocusedWindowChangedNotification { me.attachTitleNotification() }
                me.report()
            }
        }
        if AXObserverCreate(pid, callback, &obs) == .success, let obs {
            observer = obs
            AXObserverAddNotification(obs, app, kAXFocusedWindowChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            attachTitleNotification()
        }
        report()
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil; app = nil; window = nil; onChange = nil
    }

    /// Title changes are announced by the window element, so follow the focused window.
    private func attachTitleNotification() {
        guard let observer, let app else { return }
        if let old = window { AXObserverRemoveNotification(observer, old, kAXTitleChangedNotification as CFString) }
        window = Self.attribute(app, kAXFocusedWindowAttribute) as! AXUIElement?
        if let window {
            AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func report() {
        guard let app else { return }
        let win = Self.attribute(app, kAXFocusedWindowAttribute) as! AXUIElement?
        let title = win.flatMap { Self.attribute($0, kAXTitleAttribute) as? String }
        onChange?(title?.isEmpty == false ? title : nil)
    }

    private static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }
}
