import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct APIServerIntegrationTests {
    @Test func servesHealthAndAuthedRoutesOverTCP() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "Socket test", language: "en-US")
        try db.save(meeting)

        let port = UInt16.random(in: 20_000...40_000)
        let server = APIServer()
        try await server.start(port: port, token: "tok", database: db, enhanceTrigger: { _ in })
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(300))

        let health = try await fetch(
            url: "http://127.0.0.1:\(port)/v1/health", token: nil)
        #expect(health.0 == 200)

        let unauthorized = try await fetch(
            url: "http://127.0.0.1:\(port)/v1/meetings", token: nil)
        #expect(unauthorized.0 == 401)

        let list = try await fetch(
            url: "http://127.0.0.1:\(port)/v1/meetings", token: "tok")
        #expect(list.0 == 200)
        #expect(list.1.contains("Socket test"))
    }

    @Test(arguments: [(0, 7799), (8080, 8080), (65_535, 65_535), (-1, 7799), (70_000, 7799)])
    func storedPortOutsideUInt16FallsBackToDefault(stored: Int, expected: UInt16) {
        #expect(APIServer.port(stored: stored) == expected)
    }

    @Test func portInUseReportsFailure() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let port = UInt16.random(in: 40_001...50_000)
        let holder = APIServer()
        try await holder.start(port: port, token: "tok", database: db, enhanceTrigger: { _ in })
        defer { Task { await holder.stop() } }
        try await Task.sleep(for: .milliseconds(300))

        let second = APIServer()
        defer { Task { await second.stop() } }
        try await confirmation { reported in
            try await second.start(
                port: port, token: "tok", database: db, enhanceTrigger: { _ in },
                onFailure: { _ in reported() })
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func fetch(url: String, token: String?) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 5)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, String(decoding: data, as: UTF8.self))
    }
}
