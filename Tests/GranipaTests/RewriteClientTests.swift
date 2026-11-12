import Foundation
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

    @Test func customEndpointFallsBackToTheValuesSettingsShows() throws {
        let suite = "RewriteClientTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RewriteClient.customEndpoint(defaults) == (RewriteClient.defaultCustomURL, RewriteClient.defaultCustomModel))
        defaults.set("http://10.0.0.2:8080/v1", forKey: "rewriteCustomURL")
        defaults.set("", forKey: "rewriteCustomModel")
        #expect(RewriteClient.customEndpoint(defaults) == ("http://10.0.0.2:8080/v1", ""))
    }

    @Test func rewriteErrorDescriptions() {
        #expect(RewriteError.http(502).errorDescription == "Rewrite failed: HTTP 502")
        #expect(RewriteError.empty.errorDescription == "Rewrite returned no text.")
    }
}
