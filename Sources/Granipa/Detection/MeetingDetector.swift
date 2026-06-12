import CoreAudio
import Foundation
import Observation

enum MeetingApps {
    static let known: [(prefix: String, name: String)] = [
        ("us.zoom", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.cisco.webex", "Webex"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.google.Chrome", "a browser meeting"),
        ("com.apple.Safari", "a browser meeting"),
        // Safari captures microphone in the WebKit GPU helper, not the Safari process.
        ("com.apple.WebKit.GPU", "a browser meeting"),
        ("org.mozilla.firefox", "a browser meeting"),
        ("com.brave.Browser", "a browser meeting"),
        ("company.thebrowser.Browser", "a browser meeting"),
        ("com.microsoft.edgemac", "a browser meeting"),
    ]

    static func displayName(forBundleID bundleID: String) -> String? {
        known.first { bundleID.hasPrefix($0.prefix) }?.name
    }
}

@MainActor
@Observable
final class MeetingDetector {
    private(set) var detectedApp: String?
    private(set) var meetingAppActive = false
    var onMeetingDetected: ((String) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var lastActive = false

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                poll()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        detectedApp = nil
        lastActive = false
    }

    func dismiss() {
        detectedApp = nil
    }

    private func poll() {
        let active = Self.activeMeetingApp()
        let isActive = active != nil
        meetingAppActive = isActive
        if isActive, !lastActive, let name = active {
            detectedApp = name
            onMeetingDetected?(name)
        } else if !isActive {
            detectedApp = nil
        }
        lastActive = isActive
    }

    private nonisolated static func activeMeetingApp() -> String? {
        for (bundleID, capturing) in audioCaptureProcesses() where capturing {
            if let name = MeetingApps.displayName(forBundleID: bundleID) {
                return name
            }
        }
        return nil
    }

    private nonisolated static func audioCaptureProcesses() -> [(String, Bool)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processes = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr
        else {
            return []
        }

        return processes.compactMap { process in
            guard let bundleID = stringProperty(process, kAudioProcessPropertyBundleID) else {
                return nil
            }
            return (bundleID, boolProperty(process, kAudioProcessPropertyIsRunningInput))
        }
    }

    private nonisolated static func stringProperty(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = ref?.takeRetainedValue() else { return nil }
        return value as String
    }

    private nonisolated static func boolProperty(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }
}
