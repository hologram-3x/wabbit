import AppKit
import CoreAudio
import CoreMediaIO
import Foundation
import HoursCore
import SwiftUI

/// Microphone and camera "in use by any app" from OS property listeners, no polling (PLAN.md).
/// Reading these device properties needs no microphone/camera permission: Hours never opens a device.
/// Device-list listeners make newly plugged microphones and cameras watched too.
@MainActor
final class MediaDetection {
    private let emit: (DetectionEvent) -> Void
    private var micOn = false
    private var cameraOn = false
    private var watchedMics: Set<AudioObjectID> = []
    private var watchedCameras: Set<CMIOObjectID> = []

    init(emit: @escaping (DetectionEvent) -> Void) {
        self.emit = emit
        var devices = Self.audioAddress(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshMicrophones() }
        }
        var cameras = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameras, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshCameras() }
        }
        refreshMicrophones()
        refreshCameras()
    }

    // MARK: Microphone (Core Audio)

    // ponytail: device-level "running somewhere" also fires for a USB headset that only plays audio
    // (one device with input and output). Per-process kAudioProcessPropertyIsRunningInput (macOS 14+)
    // is the upgrade if that causes false prompts.
    private func refreshMicrophones() {
        let inputs = Self.audioDevices().filter(Self.hasInput)
        for id in inputs where !watchedMics.contains(id) {
            watchedMics.insert(id)
            var running = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(id, &running, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshMicrophones() }
            }
        }
        let on = inputs.contains { Self.audioIsRunning($0) }
        if on != micOn { micOn = on; emit(.microphone(on: on)) }
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector,
                                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioDevices() -> [AudioObjectID] {
        var address = audioAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ id: AudioObjectID) -> Bool {
        var address = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func audioIsRunning(_ id: AudioObjectID) -> Bool {
        var address = audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    // MARK: Camera (CoreMediaIO)

    private func refreshCameras() {
        let cameras = Self.cmioDevices()
        for id in cameras where !watchedCameras.contains(id) {
            watchedCameras.insert(id)
            var running = Self.cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            CMIOObjectAddPropertyListenerBlock(id, &running, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshCameras() }
            }
        }
        let on = cameras.contains { Self.cmioIsRunning($0) }
        if on != cameraOn { cameraOn = on; emit(.camera(on: on)) }
    }

    private static func cmioAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func cmioDevices() -> [CMIOObjectID] {
        var address = cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private static func cmioIsRunning(_ id: CMIOObjectID) -> Bool {
        var address = cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
            && value != 0
    }
}

// MARK: Meeting Prompt in the shell

extension TrayModel {
    func mediaChanged(_ event: DetectionEvent) {
        feed.emit(event)
        refresh()
        // One-shot re-check when the debounce elapses (not a poll).
        if event == .microphone(on: true) || event == .camera(on: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + MeetingDebounce.seconds + 0.5) { [weak self] in
                self?.refresh()
            }
        }
    }

    func resolveMeeting(_ choice: MeetingChoice) {
        do { try tracker.resolveMeetingPrompt(choice); error = nil } catch { self.error = "\(error)" }
        refresh()
    }

    /// The prompt also floats over other apps (a call app is usually in front); the panel exists only
    /// while a prompt is pending (footprint: no windows until needed).
    func updateMeetingPanel() {
        meetingPrompt = tracker.pendingMeetingPrompt()
        guard meetingPrompt != nil else {
            meetingPanel?.close()
            meetingPanel = nil
            return
        }
        guard meetingPanel == nil else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: true)
        panel.title = "Hours"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: MeetingPromptView(model: self).padding().frame(width: 300))
        panel.setContentSize(panel.contentView!.fittingSize)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - panel.frame.width - 16, y: screen.maxY - 16))
        }
        panel.orderFrontRegardless()
        meetingPanel = panel
    }
}

struct MeetingPromptView: View {
    let model: TrayModel
    /// The freelancer's pick; nil = the suggestion (spec: changing the guess costs one click).
    @State private var picked: Int64?

    var body: some View {
        switch model.meetingPrompt {
        case .start(let suggested):
            ask("Meeting started", suggested: suggested, action: "Start")
        case .switchTo(let suggested, _):
            let running = model.running.map { model.label(for: $0.projectId) }
            ask("Switch to …?", suggested: suggested, action: "Switch",
                detail: running.map { "Now tracking \($0)." })
        case .stop:
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting ended. Stop tracking?").font(.headline)
                if let running = model.running {
                    Text(model.label(for: running.projectId)).foregroundStyle(.secondary).font(.caption)
                }
                HStack {
                    Button("Not now") { model.resolveMeeting(.dismiss) }
                    Button("Stop") { model.resolveMeeting(.stop) }.keyboardShortcut(.defaultAction)
                }
            }
        case nil:
            EmptyView()
        }
    }

    private func ask(_ title: String, suggested: Int64, action: String, detail: String? = nil) -> some View {
        let chosen = picked ?? suggested
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let detail { Text(detail).foregroundStyle(.secondary).font(.caption) }
            Picker("Project", selection: Binding(get: { chosen }, set: { picked = $0 })) {
                ForEach(model.projects) { Text(model.label(for: $0.id!)).tag($0.id!) }
            }
            HStack {
                Button("Not now") { model.resolveMeeting(.dismiss) }
                Button(action) { model.resolveMeeting(.start(projectId: chosen)) }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
