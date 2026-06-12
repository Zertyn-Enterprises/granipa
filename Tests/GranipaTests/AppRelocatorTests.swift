import Foundation
import Testing

@testable import Granipa

@Suite struct AppRelocatorTests {
    private let downloads = "/Users/dev/Downloads"

    @Test func offersWhenRunningFromDownloads() {
        #expect(
            AppRelocator.shouldOffer(
                bundlePath: "/Users/dev/Downloads/Grañipa.app",
                downloadsPath: downloads, declined: false))
    }

    @Test func offersWhenTranslocated() {
        #expect(
            AppRelocator.shouldOffer(
                bundlePath: "/private/var/folders/x/AppTranslocation/ABC/d/Grañipa.app",
                downloadsPath: downloads, declined: false))
    }

    @Test func skipsApplicationsFolder() {
        #expect(
            !AppRelocator.shouldOffer(
                bundlePath: "/Applications/Grañipa.app",
                downloadsPath: downloads, declined: false))
    }

    @Test func skipsDevBuildsAndOtherLocations() {
        #expect(
            !AppRelocator.shouldOffer(
                bundlePath: "/Users/dev/project/build/Grañipa.app",
                downloadsPath: downloads, declined: false))
        #expect(
            !AppRelocator.shouldOffer(
                bundlePath: "/Users/dev/.build/debug/Granipa",
                downloadsPath: downloads, declined: false))
    }

    @Test func respectsDecline() {
        #expect(
            !AppRelocator.shouldOffer(
                bundlePath: "/Users/dev/Downloads/Grañipa.app",
                downloadsPath: downloads, declined: true))
    }
}
