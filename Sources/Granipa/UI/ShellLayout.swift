import CoreGraphics
import SwiftUI

enum InspectorPresentation: Equatable, Sendable {
    case hidden
    case column
    case overlay
}

enum ShellLayout {
    static let minWidth: CGFloat = 960
    static let minHeight: CGFloat = 600
    static let sidebarWidth: CGFloat = 248
    static let inspectorColumnWidth: CGFloat = 300
    static let inspectorOverlayMinWidth: CGFloat = 280
    static let inspectorBreakWidth: CGFloat = 1280
    static let defaultWindowWidth: CGFloat = 1320
    static let defaultWindowHeight: CGFloat = 820

    static func clampedDefaultSize(visible: CGSize? = nil) -> CGSize {
        let screen = visible ?? CGSize(width: defaultWindowWidth, height: defaultWindowHeight)
        return CGSize(
            width: min(defaultWindowWidth, max(minWidth, screen.width)),
            height: min(defaultWindowHeight, max(minHeight, screen.height)))
    }

    static func defaultInspectorExpanded(windowWidth: CGFloat) -> Bool {
        windowWidth >= inspectorBreakWidth
    }

    static func presentation(
        windowWidth: CGFloat,
        userExpanded: Bool?,
        hasContent: Bool
    ) -> InspectorPresentation {
        presentation(
            windowWidth: windowWidth,
            userExpanded: userExpanded,
            kind: hasContent ? .meeting : .none)
    }

    /// Occupancy (`kind`) is separate from docking. Idle Dictation can be
    /// opened explicitly; it does not inherit the wide-window default used
    /// by live Dictation and the meeting inspector.
    static func presentation(
        windowWidth: CGFloat,
        userExpanded: Bool?,
        kind: InspectorContentKind
    ) -> InspectorPresentation {
        guard kind.hasContent else { return .hidden }
        let expanded =
            userExpanded
            ?? (kind.expandsByDefault && defaultInspectorExpanded(windowWidth: windowWidth))
        guard expanded else { return .hidden }
        return windowWidth >= inspectorBreakWidth ? .column : .overlay
    }
}
