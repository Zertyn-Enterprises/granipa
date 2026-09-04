import AVFoundation
import CoreMedia
import Foundation
import Speech

enum TranscriptionDelivery {
    case efficient
    case realtime

    var reportingOptions: Set<SpeechTranscriber.ReportingOption> {
        switch self {
        case .efficient: [.volatileResults]
        case .realtime: [.volatileResults, .fastResults]
        }
    }

    var taskPriority: TaskPriority {
        switch self {
        case .efficient: .medium
        case .realtime: .high
        }
    }
}

struct LiveTranscriptionUpdate: Sendable {
    let channel: AudioChannel
    let localeID: String
    let text: String
    let startSeconds: Double?
    let endSeconds: Double?
    let isFinal: Bool
    let confidence: Double?
    let speaker: String?

    init(
        channel: AudioChannel,
        localeID: String,
        text: String,
        startSeconds: Double?,
        endSeconds: Double?,
        isFinal: Bool,
        confidence: Double?,
        speaker: String? = nil
    ) {
        self.channel = channel
        self.localeID = localeID
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.isFinal = isFinal
        self.confidence = confidence
        self.speaker = speaker
    }
}

func transcribeChannel(
    channel: AudioChannel,
    locale: Locale,
    chunks: AsyncStream<AudioChunk>,
    delivery: TranscriptionDelivery = .efficient,
    onReady: (@Sendable () -> Void)? = nil,
    gating: SpeechGate? = nil,
    onUpdate: @escaping @Sendable (LiveTranscriptionUpdate) -> Void
) async throws {
    let localeID = locale.identifier(.bcp47)
    let transcriber = SpeechTranscriber(
        locale: locale,
        transcriptionOptions: [],
        reportingOptions: delivery.reportingOptions,
        attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    // .medium keeps model load and inference below UI work — two userInitiated
    // analyzers at Record were starving the main thread (Not Responding).
    let analyzer = SpeechAnalyzer(
        modules: [transcriber],
        options: SpeechAnalyzer.Options(
            priority: delivery.taskPriority,
            modelRetention: .lingering))

    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
        throw TranscriptionError.noAudioFormat
    }

    let resultsTask = Task(priority: delivery.taskPriority) {
        for try await result in transcriber.results {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = result.range.start.seconds
            let end = result.range.end.seconds

            var confidenceSum = 0.0
            var confidenceWeight = 0.0
            for run in result.text.runs {
                if let confidence = run.transcriptionConfidence {
                    let length = Double(result.text[run.range].characters.count)
                    confidenceSum += confidence * length
                    confidenceWeight += length
                }
            }

            onUpdate(
                LiveTranscriptionUpdate(
                    channel: channel,
                    localeID: localeID,
                    text: text,
                    startSeconds: start.isFinite ? start : nil,
                    endSeconds: end.isFinite ? end : nil,
                    isFinal: result.isFinal,
                    confidence: confidenceWeight > 0 ? confidenceSum / confidenceWeight : nil))
        }
    }

    let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
    // A gated channel (system) must not prepareToAnalyze until the first
    // admitted chunk — that call is the model load that froze Record when two
    // analyzers warmed up together. Ungated channels (mic, dictation) preheat
    // immediately so the first word isn't delayed.
    var analyzerStarted = false
    if gating == nil {
        try? await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: inputSequence)
        analyzerStarted = true
        onReady?()
    }

    let converter = BufferConverter()
    // Only stamp a start time on the first buffer and after gaps; stamping every
    // buffer would mark all audio as discontiguous.
    var expectedNext: Double?
    var droppedSinceLastFed = false
    var gate = gating
    for await chunk in chunks {
        if gate?.admits(chunk) == false {
            droppedSinceLastFed = true
            continue
        }
        if !analyzerStarted {
            try? await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: inputSequence)
            analyzerStarted = true
            onReady?()
        }
        let duration = Double(chunk.buffer.frameLength) / chunk.buffer.format.sampleRate
        guard let converted = try? converter.convert(chunk.buffer, to: format) else {
            droppedSinceLastFed = true
            continue
        }
        if let start = chunk.startSeconds {
            // Gated-out silence is a real gap even when shorter than the
            // contiguity tolerance — always restamp after a drop, or the
            // analyzer clock drifts by every skipped pause.
            let contiguous = !droppedSinceLastFed
                && (expectedNext.map { abs(start - $0) < 0.5 } ?? false)
            expectedNext = start + duration
            if contiguous {
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            } else {
                let time = CMTime(seconds: start, preferredTimescale: 48_000)
                inputContinuation.yield(AnalyzerInput(buffer: converted, bufferStartTime: time))
            }
        } else {
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        }
        droppedSinceLastFed = false
    }
    inputContinuation.finish()

    if analyzerStarted {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try? await resultsTask.value
    } else {
        // No admitted audio the whole session: the analyzer never started, so
        // its finish methods are undefined territory — just stop the (empty)
        // results pump or the caller's wait would never end.
        resultsTask.cancel()
    }
}
