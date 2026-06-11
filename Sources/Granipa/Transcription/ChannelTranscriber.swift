import AVFoundation
import CoreMedia
import Foundation
import Speech

struct LiveTranscriptionUpdate: Sendable {
    let channel: AudioChannel
    let localeID: String
    let text: String
    let startSeconds: Double?
    let endSeconds: Double?
    let isFinal: Bool
    let confidence: Double?
}

func transcribeChannel(
    channel: AudioChannel,
    locale: Locale,
    chunks: AsyncStream<AudioChunk>,
    onUpdate: @escaping @Sendable (LiveTranscriptionUpdate) -> Void
) async throws {
    let localeID = locale.identifier(.bcp47)
    let transcriber = SpeechTranscriber(
        locale: locale,
        transcriptionOptions: [],
        reportingOptions: [.volatileResults, .fastResults],
        attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
        throw TranscriptionError.noAudioFormat
    }
    try? await analyzer.prepareToAnalyze(in: format)

    let resultsTask = Task {
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
    try await analyzer.start(inputSequence: inputSequence)

    let converter = BufferConverter()
    // Only stamp a start time on the first buffer and after gaps; stamping every
    // buffer would mark all audio as discontiguous.
    var expectedNext: Double?
    for await chunk in chunks {
        let duration = Double(chunk.buffer.frameLength) / chunk.buffer.format.sampleRate
        guard let converted = try? converter.convert(chunk.buffer, to: format) else { continue }
        if let start = chunk.startSeconds {
            let contiguous = expectedNext.map { abs(start - $0) < 0.5 } ?? false
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
    }
    inputContinuation.finish()

    try await analyzer.finalizeAndFinishThroughEndOfInput()
    try? await resultsTask.value
}
