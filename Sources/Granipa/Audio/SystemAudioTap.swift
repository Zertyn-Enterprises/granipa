import AVFoundation
import CoreAudio

struct CoreAudioError: Error {
    let status: OSStatus
    let stage: String
}

final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.zertyn.granipa.system-tap", qos: .userInitiated)

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AudioTimeStamp) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Grañipa System Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var err = AudioHardwareCreateProcessTap(description, &tapID)
        guard err == noErr else { throw CoreAudioError(status: err, stage: "create tap") }

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        err = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &asbdSize, &asbd)
        guard err == noErr else {
            stop()
            throw CoreAudioError(status: err, stage: "read tap format")
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            stop()
            throw CoreAudioError(status: -1, stage: "tap format init")
        }

        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var outputID = AudioDeviceID(kAudioObjectUnknown)
        var idSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &outputAddress, 0, nil, &idSize, &outputID)
        guard err == noErr else {
            stop()
            throw CoreAudioError(status: err, stage: "default output device")
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var outputUIDRef: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        err = withUnsafeMutablePointer(to: &outputUIDRef) { pointer in
            AudioObjectGetPropertyData(outputID, &uidAddress, 0, nil, &uidSize, pointer)
        }
        guard err == noErr, let outputUID = outputUIDRef?.takeRetainedValue() as String? else {
            stop()
            throw CoreAudioError(status: err, stage: "output device UID")
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Granipa-Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]
            ],
        ]
        err = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard err == noErr else {
            stop()
            throw CoreAudioError(status: err, stage: "create aggregate device")
        }

        let ioBlock: AudioDeviceIOBlock = { _, inInputData, inInputTime, _, _ in
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil)
            else { return }
            onBuffer(buffer, inInputTime.pointee)
        }
        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, ioBlock)
        guard err == noErr else {
            stop()
            throw CoreAudioError(status: err, stage: "create IO proc")
        }

        err = AudioDeviceStart(aggregateID, procID)
        guard err == noErr else {
            stop()
            throw CoreAudioError(status: err, stage: "start aggregate device")
        }
    }

    // Teardown order is load-bearing: stop -> destroy IOProc -> destroy aggregate -> destroy tap.
    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
                self.procID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        stop()
    }
}
