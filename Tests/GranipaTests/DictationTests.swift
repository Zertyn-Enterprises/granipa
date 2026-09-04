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

    @Test func shortHoldBecomesToggle() {
        #expect(DictationTrigger.actionOnRelease(held: 0.05) == .keepAsToggle)
        #expect(DictationTrigger.actionOnRelease(held: 0.21) == .keepAsToggle)
    }

    @Test func longHoldStopsOnRelease() {
        #expect(DictationTrigger.actionOnRelease(held: 0.22) == .stop)
        #expect(DictationTrigger.actionOnRelease(held: 1.4) == .stop)
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

    @Test func museForSystemRequiresKey() {
        #expect(MeetingASRPolicy.usesMuseForSystem(engine: "muse", hasMuseKey: true))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "muse", hasMuseKey: false))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "local", hasMuseKey: true))
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
