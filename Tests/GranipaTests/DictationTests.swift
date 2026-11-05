import AVFoundation
import Testing

@testable import Granipa

@Suite struct DictationTests {
    @Test func resolvedTextPrefersFinalsThenPartial() {
        #expect(DictationText.resolved(finals: "Hola", partial: "Ho") == "Hola")
        #expect(DictationText.resolved(finals: "  ", partial: "hola qué") == "hola qué")
        #expect(DictationText.resolved(finals: "", partial: "") == "")
    }

    @Test func realtimeDeliveryRequestsFastVolatileResults() {
        let realtime = TranscriptionDelivery.realtime.reportingOptions
        #expect(realtime.contains(.volatileResults))
        #expect(realtime.contains(.fastResults))
        #expect(!TranscriptionDelivery.efficient.reportingOptions.contains(.fastResults))
        #expect(TranscriptionDelivery.realtime.taskPriority == .high)
        #expect(TranscriptionDelivery.efficient.taskPriority == .medium)
    }

    @Test func batchDeliverySkipsVolatileResultsBelowForegroundWork() {
        #expect(TranscriptionDelivery.batch.reportingOptions.isEmpty)
        #expect(TranscriptionDelivery.batch.taskPriority == .utility)
    }

    @Test func shortHoldBecomesToggle() {
        for heard in [true, false] {
            #expect(DictationTrigger.actionOnRelease(held: 0.05, heardSpeech: heard) == .keepAsToggle)
            #expect(DictationTrigger.actionOnRelease(held: 0.21, heardSpeech: heard) == .keepAsToggle)
        }
    }

    @Test func longHoldStopsOnRelease() {
        #expect(DictationTrigger.actionOnRelease(held: 0.22, heardSpeech: true) == .stop)
        #expect(DictationTrigger.actionOnRelease(held: 1.4, heardSpeech: true) == .stop)
        #expect(DictationTrigger.actionOnRelease(held: 1.5, heardSpeech: false) == .stop)
        #expect(DictationTrigger.actionOnRelease(held: 6.5, heardSpeech: false) == .stop)
    }

    @Test func slowTapWithNothingHeardKeepsListening() {
        // Right ⌘ taps measured on the user's Mac: 0.40–0.60 s, before the
        // AirPods mic was even running.
        for held in [0.40, 0.60, 1.09, 1.49] {
            #expect(DictationTrigger.actionOnRelease(held: held, heardSpeech: false) == .keepAsToggle)
        }
    }

    @Test func eventTimestampsClassifyTapEvenWhenHandlingIsLate() {
        let press = 10.0
        let release = 10.05
        let handlingDelay: TimeInterval = 1.5
        #expect(handlingDelay > DictationTrigger.toggleThreshold)
        #expect(
            DictationTrigger.actionOnRelease(press: press, release: release, heardSpeech: true)
                == .keepAsToggle)
        #expect(
            DictationTrigger.actionOnRelease(
                held: (release + handlingDelay) - press, heardSpeech: true) == .stop)
    }

    @Test func eventTimestampHoldBoundaryMatchesDurationPolicy() {
        #expect(
            DictationTrigger.actionOnRelease(press: 10.0, release: 10.219, heardSpeech: true)
                == .keepAsToggle)
        #expect(
            DictationTrigger.actionOnRelease(press: 10.0, release: 10.22, heardSpeech: true)
                == .stop)
        #expect(
            DictationTrigger.actionOnRelease(press: 10.0, release: 9.5, heardSpeech: true)
                == .keepAsToggle)
    }

    @Test func museParsesHandshakeWithoutType() {
        let event = MuseEventParser.parse(#"{"sessionId":"abc-123"}"#)
        #expect(event == .handshake(sessionID: "abc-123"))
    }

    @Test func museParsesPartialAndFinalTranscripts() {
        let partial = MuseEventParser.parse(
            #"{"type":"transcript","transcript":"hola que","final":false}"#)
        let final = MuseEventParser.parse(
            #"{"type":"transcript","transcript":"hola qué tal","final":true}"#)
        #expect(partial == .transcript(text: "hola que", isFinal: false))
        #expect(final == .transcript(text: "hola qué tal", isFinal: true))
    }

    @Test func museParsesSpeechCompleteAndError() {
        let done = MuseEventParser.parse(
            #"{"type":"speechComplete","turnId":1,"transcript":"Listo."}"#)
        let error = MuseEventParser.parse(#"{"type":"error","message":"rate limited"}"#)
        #expect(done == .speechComplete(text: "Listo."))
        #expect(error == .error("rate limited"))
    }

    @Test func museIgnoresUnknownEvents() {
        #expect(MuseEventParser.parse(#"{"type":"audioProgress","audioProcessedMs":80}"#) == .ignored)
        #expect(MuseEventParser.parse("not-json") == .ignored)
    }

    @Test func languageBiasMapsBcp47AndDedupes() {
        let names = MuseLanguages.bias(forLocaleIDs: ["es-ES", "en-US", "es-MX", "xx-XX"])
        #expect(names == ["Spanish", "English"])
    }

    @Test func keywordsSplitTrimAndDedup() {
        let words = MuseLanguages.keywords(from: "Grañipa, grañipa,  Muse,")
        #expect(words == ["Grañipa", "Muse"])
    }

    @Test func pcm16EncodesSilenceAndPeaks() throws {
        let silence = try #require(PCM16Encoder.data(from: floatBuffer([0, 0, 0])))
        let samples = silence.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(samples == [0, 0, 0])

        let peak = try #require(PCM16Encoder.data(from: floatBuffer([1, -1, 0.5])))
        let peakSamples = peak.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(peakSamples[0] == Int16.max)
        #expect(peakSamples[1] == -Int16.max)
        #expect(peakSamples[2] == Int16((0.5 * Float(Int16.max)).rounded()))
    }

    @Test func museParsesSpeakerAndSpeechStart() {
        #expect(MuseEventParser.parse(#"{"type":"speechStart","turnId":1}"#) == .speechStart)
        #expect(MuseEventParser.parse(#"{"type":"speaker","label":"B"}"#) == .speaker(label: "B"))
    }

    @Test func rewriteCompletionsURLNormalizes() {
        #expect(
            RewriteClient.completionsURL(from: "http://192.168.1.10:11434/v1")?.absoluteString
                == "http://192.168.1.10:11434/v1/chat/completions")
        #expect(
            RewriteClient.completionsURL(from: "https://api.x.ai/v1/chat/completions")?
                .absoluteString == "https://api.x.ai/v1/chat/completions")
    }

    @Test func rewriteParsesChatCompletionContent() {
        let json = """
            {"choices":[{"message":{"role":"assistant","content":"Hola, ¿qué tal?"}}]}
            """
        #expect(RewriteClient.parseContent(from: json) == "Hola, ¿qué tal?")
        #expect(RewriteClient.parseContent(from: "{}") == nil)
    }

    @Test func pcm16DownmixesStereo() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2
        buffer.floatChannelData![0][0] = 1
        buffer.floatChannelData![1][0] = -1
        buffer.floatChannelData![0][1] = 0.5
        buffer.floatChannelData![1][1] = 0.5
        let data = try #require(PCM16Encoder.data(from: buffer))
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(samples[0] == 0)
        #expect(samples[1] == Int16((0.5 * Float(Int16.max)).rounded()))
    }

    /// Meeting recording owns the mic. Dictation must fail with micBusy before
    /// constructing an AsyncStream or MicRecorder — the catch-mapping after
    /// recorder.start is not exclusion, and this path must not touch hardware.
    @Test @MainActor func beginCaptureRejectsWhileMeetingUsesMicWithoutOpeningHardware() throws {
        let controller = DictationController.shared
        let previous = controller.meetingIsRecording
        defer {
            controller.meetingIsRecording = previous
            if controller.hasOpenCapture { controller.cancel() }
        }

        controller.meetingIsRecording = true
        #expect(!controller.hasOpenCapture)
        do {
            _ = try controller.beginCapture()
            Issue.record("expected DictationError.micBusy")
        } catch let error as DictationError {
            guard case .micBusy = error else {
                Issue.record("expected micBusy, got \(error)")
                return
            }
            #expect(
                error.errorDescription
                    == "Can't use the microphone while a meeting is recording.")
            #expect(
                error.localizedDescription
                    == "Can't use the microphone while a meeting is recording.")
        } catch {
            Issue.record("expected DictationError.micBusy, got \(error)")
        }
        #expect(!controller.hasOpenCapture)
    }
}

private func floatBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (i, sample) in samples.enumerated() {
        buffer.floatChannelData![0][i] = sample
    }
    return buffer
}
