import Testing

@testable import Granipa

@Suite struct RewriteClientTests {
    @Test func completionsURLRejectsEmpty() {
        #expect(RewriteClient.completionsURL(from: "") == nil)
        #expect(RewriteClient.completionsURL(from: "   ") == nil)
    }

    @Test func completionsURLStripsTrailingSlashes() {
        #expect(
            RewriteClient.completionsURL(from: "http://127.0.0.1:11434/v1///")?.absoluteString
                == "http://127.0.0.1:11434/v1/chat/completions")
    }

    @Test func parseContentRejectsEmptyAndBrokenJSON() {
        #expect(RewriteClient.parseContent(from: "") == nil)
        #expect(RewriteClient.parseContent(from: "not-json") == nil)
        #expect(
            RewriteClient.parseContent(
                from: #"{"choices":[{"message":{"content":"   "}}]}"#) == nil)
        #expect(
            RewriteClient.parseContent(
                from: #"{"choices":[{"message":{"content":""}}]}"#) == nil)
    }

    @Test func rewriteErrorDescriptions() {
        #expect(RewriteError.http(502).errorDescription == "Rewrite failed: HTTP 502")
        #expect(RewriteError.empty.errorDescription == "Rewrite returned no text.")
    }
}
