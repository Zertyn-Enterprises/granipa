import CoreGraphics
import SwiftUI

enum InspectorPresentation: Equatable, Sendable {
    case hidden
    case column
    case overlay
}

enum ShellLayout {
    static let minWidth: CGFloat = 960
    static let sidebarWidth: CGFloat = 248
    static let inspectorColumnWidth: CGFloat = 300
    static let inspectorOverlayMinWidth: CGFloat = 280
    static let inspectorBreakWidth: CGFloat = 1280
    static let defaultWindowWidth: CGFloat = 1120

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

private struct GranipaWindowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = ShellLayout.defaultWindowWidth
}

extension EnvironmentValues {
    var granipaWindowWidth: CGFloat {
        get { self[GranipaWindowWidthKey.self] }
        set { self[GranipaWindowWidthKey.self] = newValue }
    }
}
