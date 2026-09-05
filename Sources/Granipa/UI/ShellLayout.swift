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
        guard hasContent else { return .hidden }
        let expanded = userExpanded ?? defaultInspectorExpanded(windowWidth: windowWidth)
        guard expanded else { return .hidden }
        return windowWidth >= inspectorBreakWidth ? .column : .overlay
    }
}
