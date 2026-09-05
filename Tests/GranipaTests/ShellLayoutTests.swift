import Testing

@testable import Granipa

@Suite struct ShellLayoutTests {
    @Test func geometryMatchesTheV2Contract() {
        #expect(ShellLayout.minWidth == 960)
        #expect(ShellLayout.sidebarWidth == 248)
        #expect(ShellLayout.inspectorColumnWidth == 300)
        #expect(ShellLayout.inspectorOverlayMinWidth == 280)
        #expect(ShellLayout.inspectorBreakWidth == 1280)
        #expect(ShellLayout.defaultWindowWidth == 1120)
    }

    @Test func compactDefaultKeepsInspectorCollapsed() {
        #expect(
            ShellLayout.presentation(windowWidth: 1120, userExpanded: nil, hasContent: true)
                == .hidden)
        #expect(
            ShellLayout.presentation(windowWidth: 1279, userExpanded: nil, hasContent: true)
                == .hidden)
        #expect(ShellLayout.defaultInspectorExpanded(windowWidth: 1120) == false)
    }

    @Test func wideDefaultShowsColumnWhenContentExists() {
        #expect(
            ShellLayout.presentation(windowWidth: 1280, userExpanded: nil, hasContent: true)
                == .column)
        #expect(
            ShellLayout.presentation(windowWidth: 1440, userExpanded: nil, hasContent: true)
                == .column)
        #expect(ShellLayout.defaultInspectorExpanded(windowWidth: 1280) == true)
    }

    @Test func toolbarOverrideDoesNotDuplicateBreakpointState() {
        #expect(
            ShellLayout.presentation(windowWidth: 1120, userExpanded: true, hasContent: true)
                == .overlay)
        #expect(
            ShellLayout.presentation(windowWidth: 1280, userExpanded: false, hasContent: true)
                == .hidden)
        #expect(
            ShellLayout.presentation(windowWidth: 1280, userExpanded: true, hasContent: true)
                == .column)
    }

    @Test func missingContentHidesInspectorEvenWhenExpanded() {
        #expect(
            ShellLayout.presentation(windowWidth: 1440, userExpanded: true, hasContent: false)
                == .hidden)
        #expect(
            ShellLayout.presentation(windowWidth: 1120, userExpanded: true, hasContent: false)
                == .hidden)
    }

    @Test func meetingContentFitsTheShellMinimumWithoutInspector() {
        #expect(MeetingDetailLayout.minContentWidth == 711)
        #expect(!MeetingDetailLayout.compactPlayback(711))
        #expect(MeetingDetailLayout.compactPlayback(619))
        #expect(!MeetingDetailLayout.compactPlayback(620))
    }
}
