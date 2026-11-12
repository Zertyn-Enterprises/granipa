import AVFoundation
import Synchronization
import os

// One channel's m4a. Everything except audioFramesWritten is confined to the
// owning session's writer queue. The file keeps the format of its first
// buffer for the whole meeting; later buffers in another format (input device
// switch, system tap rebuilt at another rate) are converted into it, because
// AVAudioFile.write accepts a same-channel-count buffer at another sample rate
// and silently shrinks the timeline. Gaps (restarts, stalled routes, silence
// on the system tap) are padded with silence so file time == meeting time.
final class ChannelFileWriter {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "session")
    private let url: URL
    private let bitRate: Int
    private var file: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0
    private let converter = BufferConverter()
    private var padSeconds: Double = 0
    // Opening fails the same way for the same format; retry only on a new one.
    private var failedOpenFormat: AVAudioFormat?
    private let audioFrames = Mutex<AVAudioFramePosition>(0)

    /// Captured-audio frames (not silence padding) written so far, across file
    /// recreations. Safe to read from any thread.
    var audioFramesWritten: AVAudioFramePosition { audioFrames.withLock { $0 } }

    init(url: URL, bitRate: Int) {
        self.url = url
        self.bitRate = bitRate
    }

    func write(_ buffer: AVAudioPCMBuffer, startSeconds: Double?) {
        guard let file = openIfNeeded(format: buffer.format) else { return }
        let fileFormat = file.processingFormat
        if let start = startSeconds, start > 0 {
            let expectedFrame = AVAudioFramePosition((start * fileFormat.sampleRate).rounded())
            let gap = expectedFrame - framesWritten
            if gap > AVAudioFramePosition(fileFormat.sampleRate * 0.25) {
                framesWritten += appendSilence(to: file, frames: gap)
            }
        }
        let toWrite: AVAudioPCMBuffer
        do {
            toWrite = try converter.convert(buffer, to: fileFormat)
        } catch {
            Self.log.error(
                "\(self.url.lastPathComponent, privacy: .public) buffer dropped: conversion \(buffer.format.sampleRate)Hz/\(buffer.format.channelCount)ch -> \(fileFormat.sampleRate)Hz/\(fileFormat.channelCount)ch failed: \(String(describing: error))")
            return
        }
        do {
            try file.write(from: toWrite)
        } catch {
            Self.log.error(
                "\(self.url.lastPathComponent, privacy: .public) write failed: \(String(describing: error))")
            return
        }
        framesWritten += AVAudioFramePosition(toWrite.frameLength)
        audioFrames.withLock { $0 += AVAudioFramePosition(toWrite.frameLength) }
    }

    /// Starts a new file on the next buffer, led by `padSeconds` of silence.
    func reset(padSeconds: Double) {
        file = nil
        framesWritten = 0
        failedOpenFormat = nil
        self.padSeconds = padSeconds
    }

    func close() {
        file = nil
    }

    private func openIfNeeded(format: AVAudioFormat) -> AVAudioFile? {
        if let file { return file }
        if let failedOpenFormat, failedOpenFormat == format { return nil }
        guard let opened = Self.openAudioFile(url: url, format: format, bitRate: bitRate) else {
            failedOpenFormat = format
            return nil
        }
        file = opened
        failedOpenFormat = nil
        if padSeconds > 0 {
            let frames = (padSeconds * opened.processingFormat.sampleRate).rounded()
            framesWritten += appendSilence(to: opened, frames: AVAudioFramePosition(frames))
        }
        padSeconds = 0
        return opened
    }

    // Only frames that were actually written are counted, so a failed write
    // leaves the gap owed and the next buffer pads it again.
    private func appendSilence(
        to file: AVAudioFile, frames: AVAudioFramePosition
    ) -> AVAudioFramePosition {
        var remaining = frames
        var appended: AVAudioFramePosition = 0
        while remaining > 0 {
            let chunkFrames = AVAudioFrameCount(min(remaining, 16_384))
            guard
                let silence = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat, frameCapacity: chunkFrames)
            else { break }
            silence.frameLength = chunkFrames
            do {
                try file.write(from: silence)
            } catch {
                Self.log.error(
                    "\(self.url.lastPathComponent, privacy: .public) silence write failed: \(String(describing: error))")
                break
            }
            remaining -= AVAudioFramePosition(chunkFrames)
            appended += AVAudioFramePosition(chunkFrames)
        }
        return appended
    }

    // The AAC encoder rejects a bit rate outside the range its sample rate
    // allows: 96 kbps is refused at the 24 kHz / 16 kHz a Bluetooth headset
    // mic delivers, which left the file unopened and the whole channel
    // unrecorded. Fall back to the encoder's own default for that format.
    private static func openAudioFile(url: URL, format: AVAudioFormat, bitRate: Int) -> AVAudioFile?
    {
        for requestedBitRate in [bitRate, nil] {
            do {
                return try AVAudioFile(
                    forWriting: url,
                    settings: aacSettings(for: format, bitRate: requestedBitRate),
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved)
            } catch {
                log.error(
                    "open \(url.lastPathComponent, privacy: .public) failed at \(format.sampleRate, privacy: .public)Hz/\(format.channelCount)ch bitRate=\(requestedBitRate ?? 0): \(String(describing: error), privacy: .public)")
            }
        }
        return nil
    }

    private static func aacSettings(for format: AVAudioFormat, bitRate: Int?) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
        ]
        if let bitRate {
            settings[AVEncoderBitRateKey] = bitRate
        }
        return settings
    }
}
