#if DEBUG
import AppKit
import Foundation
import SwiftUI

/// One-shot self-view snapshot for the debug fixture, `--v2-snapshot`.
/// Renders the app's own main-window content view via NSView
/// `cacheDisplay` — no screen capture, no TCC surface — and writes PNG
/// into the root of the validated fixture home. Only runs inside an
/// honored `--v2-fixture` launch; compiled out of release builds.
enum V2SnapshotHook {
    /// Hosting window reported by the probe placed inside MainWindow.
    /// Weak so a closed window can deinit if the app outlives the fixture.
    @MainActor
    enum HostWindow {
        static weak var current: NSWindow?
    }

    /// Zero-footprint probe placed inside MainWindow on fixture launches.
    /// Its view's own `window` is by definition the main window's host —
    /// no keyWindow/first-visible guessing, no title heuristics.
    struct MainWindowProbe: NSViewRepresentable {
        final class ProbeView: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                HostWindow.current = window
            }
        }

        func makeNSView(context: Context) -> ProbeView { ProbeView() }
        func updateNSView(_ view: ProbeView, context: Context) {}
    }

    static let flag = "--v2-snapshot"
    static let destinationFlag = "--v2-destination"
    static let widthFlag = "--v2-width"

    static let defaultWidth: Double = 1440
    static let maxWidth: Double = 2560
    static let captureHeight: Double = 900

    /// Matches MainWindow's own `minHeight: 600`. A capture smaller than
    /// the shell minimum is a HUD/utility window, not the fixture shell —
    /// refuse instead of emitting a near-empty PNG.
    static let minimumContentHeight: CGFloat = 600

    static func isMeaningfulContentSize(_ size: NSSize) -> Bool {
        size.width >= ShellLayout.minWidth && size.height >= minimumContentHeight
    }


    struct Request: Equatable, Sendable {
        var width: Double
        var destination: SidebarDestination
    }

    enum Launch: Equatable, Sendable {
        case off
        case run(Request)
        case refuse(String)
    }

    /// Pure parser. Widths stay between the shell's own minimum and a
    /// bounded maximum; the closed range also rejects nan/inf.
    static func resolve(arguments: [String]) -> Launch {
        guard arguments.contains(flag) else {
            if arguments.contains(destinationFlag) || arguments.contains(widthFlag) {
                return .refuse("\(destinationFlag)/\(widthFlag) require \(flag).")
            }
            return .off
        }
        var destination = SidebarDestination.home
        if arguments.contains(destinationFlag) {
            guard let raw = value(after: destinationFlag, in: arguments),
                let parsed = SidebarDestination(rawValue: raw)
            else {
                let options = SidebarDestination.allCases.map(\.rawValue)
                    .joined(separator: "|")
                return .refuse("Missing or unknown value after \(destinationFlag). Use \(options).")
            }
            destination = parsed
        }
        var width = defaultWidth
        if arguments.contains(widthFlag) {
            guard let raw = value(after: widthFlag, in: arguments),
                let parsed = Double(raw),
                Double(ShellLayout.minWidth)...maxWidth ~= parsed
            else {
                return .refuse(
                    "Missing or unsafe value after \(widthFlag). Use a number between "
                        + "\(Int(ShellLayout.minWidth)) and \(Int(maxWidth)).")
            }
            width = parsed
        }
        return .run(Request(width: width, destination: destination))
    }

    /// Schedules the single delayed capture. The app stays alive after
    /// writing so the runner's temp home (and the PNG in it) survives
    /// until the operator inspects it.
    static func captureIfRequested(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard V2FixtureRuntime.isActive,
            case .run(let request) = resolve(arguments: arguments),
            let home = environment["CFFIXED_USER_HOME"],
            V2FixtureRuntime.isIsolatedTempRoot(home)
        else { return }
        Task { @MainActor in
            guard let window = await Self.awaitHostWindow() else {
                Self.fail(Self.hostWindowMissingDiagnostic())
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
            window.setContentSize(NSSize(width: request.width, height: Self.captureHeight))
            try? await Task.sleep(for: .seconds(0.8))
            guard let view = window.contentView else {
                Self.fail("the main window lost its content view before capture")
                return
            }
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let size = view.bounds.size
            Self.log("window '\(window.title)' content \(Int(size.width))x\(Int(size.height))")
            guard Self.isMeaningfulContentSize(size) else {
                Self.fail(
                    "content is \(Int(size.width))x\(Int(size.height)); the shell minimum is "
                        + "\(Int(ShellLayout.minWidth))x\(Int(Self.minimumContentHeight))")
                return
            }
            let rect = view.bounds
            guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else {
                Self.fail("could not allocate the fixture bitmap")
                return
            }
            view.cacheDisplay(in: rect, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                Self.fail("could not encode the fixture window content")
                return
            }
            let url = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("snapshot.png")
            do {
                try png.write(to: url, options: .atomic)
            } catch {
                Self.fail("could not write \(url.path): \(error.localizedDescription)")
                return
            }
            print("v2-snapshot: \(url.path)")
        }
    }

    /// Waits out window creation instead of assuming the launch always
    /// shows the main window (restoration can suppress it).
    @MainActor
    private static func awaitHostWindow(timeout: Duration = .seconds(6)) async -> NSWindow? {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let window = HostWindow.current { return window }
            if ContinuousClock.now >= deadline { return nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @MainActor
    private static func hostWindowMissingDiagnostic() -> String {
        let inventory = NSApp.windows
            .map {
                "'\($0.title)' \(Int($0.frame.width))x\(Int($0.frame.height))"
                    + " visible=\($0.isVisible)"
            }
            .joined(separator: ", ")
        return inventory.isEmpty
            ? "MainWindow was never created (no windows exist)"
            : "MainWindow was never created; windows: \(inventory)"
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data(("ERROR: v2-snapshot: \(message)\n").utf8))
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data(("v2-snapshot: \(message)\n").utf8))
    }
}
#endif
