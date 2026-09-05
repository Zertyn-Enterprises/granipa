import CoreGraphics
import Testing

@testable import Granipa

@Suite struct ShellLayoutTests {
    @Test func geometryMatchesTheV2Contract() {
        #expect(ShellLayout.minWidth == 960)
        #expect(ShellLayout.minHeight == 600)
        #expect(ShellLayout.sidebarWidth == 248)
        #expect(ShellLayout.inspectorColumnWidth == 300)
        #expect(ShellLayout.inspectorOverlayMinWidth == 280)
        #expect(ShellLayout.inspectorBreakWidth == 1280)
        // Was 1120×720: first launch hid the inspector under the 1280 breakpoint.
        // Visual completion requires 1320×820 so three columns show on common
        // wide screens. Compact 960–1279 behavior is unchanged.
        #expect(ShellLayout.defaultWindowWidth == 1320)
        #expect(ShellLayout.defaultWindowHeight == 820)
    }

    @Test func defaultWidthShowsInspectorColumn() {
        #expect(
            ShellLayout.defaultInspectorExpanded(windowWidth: ShellLayout.defaultWindowWidth)
                == true)
        #expect(
            ShellLayout.presentation(
                windowWidth: ShellLayout.defaultWindowWidth, userExpanded: nil, hasContent: true)
                == .column)
    }

    @Test func compactWidthsKeepInspectorCollapsed() {
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

    @Test func clampedDefaultSizeFitsVisibleScreenAndKeepsMinimums() {
        let roomy = ShellLayout.clampedDefaultSize(visible: CGSize(width: 1920, height: 1080))
        #expect(roomy.width == 1320)
        #expect(roomy.height == 820)

        let laptop = ShellLayout.clampedDefaultSize(visible: CGSize(width: 1280, height: 800))
        #expect(laptop.width == 1280)
        #expect(laptop.height == 800)

        let tiny = ShellLayout.clampedDefaultSize(visible: CGSize(width: 800, height: 500))
        #expect(tiny.width == 960)
        #expect(tiny.height == 600)

        let unset = ShellLayout.clampedDefaultSize(visible: nil)
        #expect(unset.width == 1320)
        #expect(unset.height == 820)
    }
}
