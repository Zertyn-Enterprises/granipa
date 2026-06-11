import AVFoundation
import CoreAudio
import os

struct CoreAudioError: Error {
    let status: OSStatus
    let stage: String
}

final class SystemAudioTap {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "tap")
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

        // Tap-only aggregate: no physical sub-device, so no dependency on any
        // output device's clock or state. A Bluetooth device in call mode (AirPods
        // while their mic records) never ticks for our IOProc when used as the
        // aggregate clock — the tap times itself instead, and process taps capture
        // pre-routing, so output-device and route changes can't starve it.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Granipa-Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: false,
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
        Self.log.info(
            "tap running: tap-only aggregate, format=\(format.sampleRate)Hz ch=\(format.channelCount)")
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
