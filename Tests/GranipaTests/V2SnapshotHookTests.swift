#if DEBUG
import Testing

@testable import Granipa

@Suite struct V2SnapshotHookTests {
    private static let base = ["Granipa", "--v2-fixture", "shell"]

    @Test func resolveStaysOffWithoutTheSnapshotFlag() {
        #expect(V2SnapshotHook.resolve(arguments: []) == .off)
        #expect(V2SnapshotHook.resolve(arguments: Self.base) == .off)
    }

    @Test func resolveRefusesSubFlagsWithoutTheSnapshotFlag() {
        for arguments in [
            Self.base + ["--v2-destination", "notes"],
            Self.base + ["--v2-width", "1440"],
        ] {
            guard case .refuse = V2SnapshotHook.resolve(arguments: arguments) else {
                Issue.record("must be refused: \(arguments)")
                return
            }
        }
    }

    @Test func resolveDefaultsToHomeAtDefaultWidth() {
        #expect(
            V2SnapshotHook.resolve(arguments: Self.base + ["--v2-snapshot"])
                == .run(V2SnapshotHook.Request(
                    width: V2SnapshotHook.defaultWidth, destination: .home)))
    }

    @Test func resolveAcceptsEveryDestination() {
        for destination in SidebarDestination.allCases {
            #expect(
                V2SnapshotHook.resolve(
                    arguments: Self.base
                        + ["--v2-snapshot", "--v2-destination", destination.rawValue])
                    == .run(V2SnapshotHook.Request(
                        width: V2SnapshotHook.defaultWidth, destination: destination)))
        }
    }

    @Test func resolveRefusesUnknownOrMissingDestination() {
        for arguments in [
            Self.base + ["--v2-snapshot", "--v2-destination", "settings"],
            Self.base + ["--v2-snapshot", "--v2-destination"],
        ] {
            guard case .refuse = V2SnapshotHook.resolve(arguments: arguments) else {
                Issue.record("must be refused: \(arguments)")
                return
            }
        }
    }

    @Test func resolveAcceptsBoundedFiniteWidths() {
        let lower = "\(Int(ShellLayout.minWidth))"
        let upper = "\(Int(V2SnapshotHook.maxWidth))"
        for raw in [lower, upper, "1440"] {
            #expect(
                V2SnapshotHook.resolve(
                    arguments: Self.base + ["--v2-snapshot", "--v2-width", raw])
                    == .run(V2SnapshotHook.Request(
                        width: Double(raw) ?? 0, destination: .home)))
        }
    }

    @Test func resolveRefusesUnboundedOrNonNumericWidths() {
        let below = "\(Int(ShellLayout.minWidth) - 1)"
        let above = "\(Int(V2SnapshotHook.maxWidth) + 1)"
        for raw in [below, above, "0", "-1440", "inf", "nan", "wide", ""] {
            guard case .refuse = V2SnapshotHook.resolve(
                arguments: Self.base + ["--v2-snapshot", "--v2-width", raw])
            else {
                Issue.record("width must be refused: \(raw)")
                return
            }
        }
        guard case .refuse = V2SnapshotHook.resolve(
            arguments: Self.base + ["--v2-snapshot", "--v2-width"])
        else {
            Issue.record("missing width value must be refused")
            return
        }
    }
}
#endif
