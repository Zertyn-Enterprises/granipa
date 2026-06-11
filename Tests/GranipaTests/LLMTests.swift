import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct LLMRunnerTests {
    @Test func echoesStdin() async throws {
        let output = try await LLMRunner.run(
            executable: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            stdin: "hello world",
            timeout: 10)
        #expect(output.stdout == "hello world")
    }

    @Test func nonZeroExitThrows() async {
        await #expect(throws: LLMError.self) {
            _ = try await LLMRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/false"),
                arguments: [],
                stdin: nil,
                timeout: 10)
        }
    }

    @Test func timeoutTerminatesProcess() async {
        await #expect(throws: LLMError.self) {
            _ = try await LLMRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                stdin: nil,
                timeout: 0.5)
        }
    }

    @Test func largeStdinDoesNotDeadlock() async throws {
        let big = String(repeating: "x", count: 300_000)
        let output = try await LLMRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/wc"),
            arguments: ["-c"],
            stdin: big,
            timeout: 15)
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "300000")
    }
}

@Suite struct EnhancementServiceTests {
    @Test func parsesPlainJSON() throws {
        let raw = """
            {"title": "Roadmap sync", "summary": "We synced.", "enhanced_notes": "## Notes",
             "action_items": [{"text": "Send deck", "owner": "Ana"}], "email_draft": "Hi all"}
            """
        let result = try EnhancementService.parse(raw)
        #expect(result.title == "Roadmap sync")
        #expect(result.actionItems?.first?.owner == "Ana")
    }

    @Test func parsesFencedJSONWithProse() throws {
        let raw = """
            Here is the JSON you asked for:
            ```json
            {"title": "T", "summary": "S", "enhanced_notes": "N", "action_items": [], "email_draft": "E"}
            ```
            Let me know if you need anything else.
            """
        let result = try EnhancementService.parse(raw)
        #expect(result.title == "T")
        #expect(result.emailDraft == "E")
    }

    @Test func parseFailsWithoutJSON() {
        #expect(throws: EnhancementError.self) {
            _ = try EnhancementService.parse("no json here")
        }
    }

    @Test func transcriptInterleavesByTime() {
        let segments = [
            TranscriptSegment.new(
                meetingID: "m", channel: .system, speaker: "Them", text: "second",
                startSeconds: 65, endSeconds: 67, isFinal: true),
            TranscriptSegment.new(
                meetingID: "m", channel: .mic, speaker: "Me", text: "first",
                startSeconds: 2, endSeconds: 4, isFinal: true),
        ]
        let text = EnhancementService.transcriptText(segments: segments)
        #expect(text == "[0:02] Me: first\n[1:05] Them: second")
    }

    @Test func promptIncludesNotesTemplateAndTranscript() {
        let prompt = EnhancementService.buildPrompt(
            template: MeetingTemplate.builtins[0],
            notes: "- my note",
            transcript: "[0:01] Me: hola")
        #expect(prompt.contains("- my note"))
        #expect(prompt.contains("Key points"))
        #expect(prompt.contains("[0:01] Me: hola"))
        #expect(prompt.contains("email_draft"))
    }

    @Test func templateSeedsExist() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let templates = try db.fetchTemplates()
        #expect(templates.count == MeetingTemplate.builtins.count)
        #expect(templates.allSatisfy { $0.isBuiltin })
        #expect(templates.contains { $0.name == "Interview" })
    }
}
