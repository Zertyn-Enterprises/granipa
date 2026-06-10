import Foundation

enum AppPaths {
    static func supportDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Granipa", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func audioDirectory(meetingID: String) throws -> URL {
        let dir = try supportDirectory()
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(meetingID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
