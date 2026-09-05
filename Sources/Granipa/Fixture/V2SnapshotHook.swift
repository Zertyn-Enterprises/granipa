#if DEBUG
import AppKit
import Foundation

/// One-shot self-view snapshot for the debug fixture, `--v2-snapshot`.
/// Renders the app's own main-window content view via NSView
/// `cacheDisplay` — no screen capture, no TCC surface — and writes PNG
/// into the root of the validated fixture home. Only runs inside an
/// honored `--v2-fixture` launch; compiled out of release builds.
enum V2SnapshotHook {
    static let flag = "--v2-snapshot"
    static let destinationFlag = "--v2-destination"
    static let widthFlag = "--v2-width"

    static let defaultWidth: Double = 1440
    static let maxWidth: Double = 2560
    static let captureHeight: Double = 900

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
            try? await Task.sleep(for: .seconds(1.5))
            guard
                let window = NSApp.keyWindow
                    ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                let view = window.contentView
            else {
                Self.fail("no visible fixture window to capture")
                return
            }
            window.setContentSize(NSSize(width: request.width, height: Self.captureHeight))
            try? await Task.sleep(for: .seconds(0.8))
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

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data(("ERROR: v2-snapshot: \(message)\n").utf8))
    }
}
#endif
