import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct FolderTests {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    @Test func folderAssignmentAndCounts() throws {
        let db = try makeDatabase()
        let folder = Folder.new(name: "Engineering", team: "Acme HQ")
        try db.save(folder)

        var meeting = Meeting.new(title: "Sync", language: "auto")
        meeting.folderID = folder.id
        try db.save(meeting)
        try db.save(Meeting.new(title: "Loose", language: "auto"))

        let counts = try db.folderMeetingCounts()
        #expect(counts == [folder.id: 1])
    }

    @Test func deletingFolderUnassignsMeetings() throws {
        let db = try makeDatabase()
        let folder = Folder.new(name: "Temp", team: nil)
        try db.save(folder)
        var meeting = Meeting.new(title: "M", language: "auto")
        meeting.folderID = folder.id
        try db.save(meeting)

        try db.deleteFolder(id: folder.id)
        let fetched = try db.fetchMeeting(id: meeting.id)
        #expect(fetched?.folderID == nil)
    }

    @Test func apiExposesFoldersAndFilters() throws {
        let db = try makeDatabase()
        let folder = Folder.new(name: "Carbon", team: "Acme HQ")
        try db.save(folder)
        var inFolder = Meeting.new(title: "Carbon sync", language: "auto")
        inFolder.folderID = folder.id
        try db.save(inFolder)
        try db.save(Meeting.new(title: "Other", language: "auto"))

        func get(_ path: String, query: [String: String] = [:]) -> HTTPResponse {
            APIRouter.route(
                HTTPRequest(
                    method: "GET", path: path, query: query,
                    headers: ["authorization": "Bearer tok"], body: Data()),
                token: "tok", database: db, enhanceTrigger: { _ in })
        }

        let folders = get("/v1/folders")
        #expect(folders.status == 200)
        let foldersBody = String(decoding: folders.body, as: UTF8.self)
        #expect(foldersBody.contains("\"name\":\"Carbon\""))
        #expect(foldersBody.contains("\"team\":\"Acme HQ\""))
        #expect(foldersBody.contains("\"meetingCount\":1"))

        let filtered = get("/v1/meetings", query: ["folder": folder.id])
        let filteredBody = String(decoding: filtered.body, as: UTF8.self)
        #expect(filteredBody.contains("Carbon sync"))
        #expect(!filteredBody.contains("Other"))

        let detail = get("/v1/meetings/\(inFolder.id)")
        let detailBody = String(decoding: detail.body, as: UTF8.self)
        #expect(detailBody.contains("\"folder\":{"))
        #expect(detailBody.contains("\"team\":\"Acme HQ\""))
    }
}
