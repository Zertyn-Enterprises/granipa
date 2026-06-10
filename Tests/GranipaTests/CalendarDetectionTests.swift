import Foundation
import Testing

@testable import Granipa

@Suite struct CalendarDetectionTests {
    @Test func extractsZoomURLFromNotes() {
        let url = CalendarMeeting.extractJoinURL(from: [
            nil,
            "Agenda attached.",
            "Join: https://us02web.zoom.us/j/123456789?pwd=abc. See you!",
        ])
        #expect(url?.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc")
    }

    @Test func extractsMeetURL() {
        let url = CalendarMeeting.extractJoinURL(from: ["https://meet.google.com/abc-defg-hij"])
        #expect(url?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func returnsNilWithoutMeetingLink() {
        #expect(CalendarMeeting.extractJoinURL(from: ["https://example.com/doc", nil]) == nil)
    }

    @Test func mapsKnownMeetingApps() {
        #expect(MeetingApps.displayName(forBundleID: "us.zoom.xos") == "Zoom")
        #expect(MeetingApps.displayName(forBundleID: "com.microsoft.teams2") == "Microsoft Teams")
        #expect(MeetingApps.displayName(forBundleID: "com.google.Chrome.helper") == "a browser meeting")
        #expect(MeetingApps.displayName(forBundleID: "com.apple.dt.Xcode") == nil)
    }
}
