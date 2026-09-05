#if DEBUG
import Foundation

/// Deterministic UI fixture selected with `--v2-fixture shell|many`.
/// Debug builds only; the flag is ignored by release builds.
enum V2Fixture: String, CaseIterable, Sendable {
    case shell
    case many
}

enum V2FixtureLaunch: Equatable, Sendable {
    case off
    case run(V2Fixture)
    case refuse(String)
}

enum V2FixtureRuntime {
    static let flag = "--v2-fixture"

    /// True only for an honored `--v2-fixture` launch. Computed from the same
    /// argv/environment `GranipaApp.init` already resolves — not a mutable flag.
    static var isActive: Bool {
        isActive(
            resolve(
                arguments: CommandLine.arguments,
                environment: ProcessInfo.processInfo.environment))
    }

    static func isActive(_ launch: V2FixtureLaunch) -> Bool {
        if case .run = launch { return true }
        return false
    }

    static let isolationRefusal =
        "Fixture mode needs a throwaway home directory under /private/tmp "
        + "(CFFIXED_USER_HOME, see Scripts/v2-fixture.sh); refusing to start."

    /// Pure parser for the `--v2-fixture` launch argument.
    static func parseArguments(_ arguments: [String]) -> V2FixtureLaunch {
        guard let index = arguments.firstIndex(of: flag) else { return .off }
        let valueIndex = index + 1
        guard arguments.indices.contains(valueIndex) else {
            return .refuse("Missing fixture name after \(flag). Use shell or many.")
        }
        let value = arguments[valueIndex]
        guard let fixture = V2Fixture(rawValue: value) else {
            return .refuse("Unknown fixture '\(value)'. Use shell or many.")
        }
        return .run(fixture)
    }

    /// Full launch decision. A fixture request is honored only when
    /// CFFIXED_USER_HOME resolves strictly inside the system temp area, so a
    /// missing or unsafe root fails closed before AppDatabase ever opens.
    static func resolve(arguments: [String], environment: [String: String]) -> V2FixtureLaunch {
        let request = parseArguments(arguments)
        guard case .run(let fixture) = request else { return request }
        guard let rawRoot = environment["CFFIXED_USER_HOME"], isIsolatedTempRoot(rawRoot) else {
            return .refuse(isolationRefusal)
        }
        return .run(fixture)
    }

    /// True only for paths that standardize strictly below /tmp or
    /// /private/tmp. `resolvingSymlinksInPath` neither expands /tmp nor keeps
    /// a /private prefix on this OS, so both spellings are checked against
    /// their resolved form.
    static func isIsolatedTempRoot(_ rawPath: String) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let resolved = URL(fileURLWithPath: trimmed)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return isStrictlyInside(resolved, "/tmp") || isStrictlyInside(resolved, "/private/tmp")
    }

    private static func isStrictlyInside(_ path: String, _ root: String) -> Bool {
        path.hasPrefix(root + "/") && path.count > root.count + 1
    }
}
#endif
