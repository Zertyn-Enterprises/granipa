#if DEBUG
import Foundation
import Testing

@testable import Granipa

@Suite struct V2FixtureIsolationTests {
    @Test func launchSignalIsActiveOnlyForHonoredFixtureRuns() {
        #expect(!V2FixtureRuntime.isActive(.off))
        #expect(!V2FixtureRuntime.isActive(.refuse("no")))
        #expect(V2FixtureRuntime.isActive(.run(.shell)))
        #expect(V2FixtureRuntime.isActive(.run(.many)))
        #expect(!V2FixtureRuntime.isActive)
    }

    @Test func debugExtraHidesWithIsInsertedAndSkipsMenuConstruction() throws {
        let source = try granipaSource("Sources/Granipa/GranipaApp.swift")
        #expect(source.contains("isInserted: .constant(!V2FixtureRuntime.isActive)"))
        #expect(source.contains("if V2FixtureRuntime.isActive"))
        #expect(source.contains("EmptyView()"))
        #expect(source.contains("MenuBarView()"))
        #expect(source.contains("MenuBarLabel(app: appState)"))
        #expect(!source.contains("if !V2FixtureRuntime.isActive {\n            MenuBarExtra"))
        #expect(!source.contains("if !V2FixtureRuntime.isActive {\n        MenuBarExtra"))
    }

    @Test func releaseExtraKeepsTheProductionInitializer() throws {
        let source = try granipaSource("Sources/Granipa/GranipaApp.swift")
        let releaseExtra = try #require(elseArm(in: source, after: "isInserted:"))
        #expect(releaseExtra.contains("MenuBarView()"))
        #expect(releaseExtra.contains("MenuBarLabel(app: appState)"))
        #expect(!releaseExtra.contains("V2FixtureRuntime"))
        #expect(!releaseExtra.contains("isInserted"))
        #expect(!releaseExtra.contains("EmptyView()"))
    }

    @Test func fixtureAppDelegateSkipsRelocatorAndBatterySingletons() throws {
        let source = try granipaSource("Sources/Granipa/GranipaApp.swift")
        let launching = try #require(methodBody(source, named: "applicationDidFinishLaunching"))
        let terminating = try #require(methodBody(source, named: "applicationWillTerminate"))
        let becomingActive = try #require(methodBody(source, named: "applicationDidBecomeActive"))

        #expect(launching.contains("V2FixtureRuntime.isActive"))
        #expect(terminating.contains("V2FixtureRuntime.isActive"))
        #expect(becomingActive.contains("V2FixtureRuntime.isActive"))

        let relocator = try #require(launching.range(of: "AppRelocator.offerMoveIfNeeded()"))
        let stop = try #require(terminating.range(of: "BatteryService.shared.stop()"))
        let invalidate = try #require(
            becomingActive.range(of: "BatteryHelperClient.shared.invalidateStatusCache()"))
        let skipLaunch = try #require(launching.range(of: "V2FixtureRuntime.isActive"))
        let skipTerminate = try #require(terminating.range(of: "V2FixtureRuntime.isActive"))
        let skipActive = try #require(becomingActive.range(of: "V2FixtureRuntime.isActive"))
        #expect(skipLaunch.lowerBound < relocator.lowerBound)
        #expect(skipTerminate.lowerBound < stop.lowerBound)
        #expect(skipActive.lowerBound < invalidate.lowerBound)
    }

    @Test func fixtureCaptureStartsFailBeforeHardware() throws {
        let appState = try granipaSource("Sources/Granipa/AppState.swift")
        let dictation = try granipaSource("Sources/Granipa/Dictation/DictationController.swift")

        let startRecording = try #require(methodBody(appState, named: "startRecording", signatureContains: "meetingID"))
        #expect(startRecording.contains("V2FixtureRuntime.isActive"))
        if let guardRange = startRecording.range(of: "V2FixtureRuntime.isActive"),
            let create = startRecording.range(of: "createMeeting")
        {
            #expect(guardRange.lowerBound < create.lowerBound)
        }

        let start = try #require(methodBody(dictation, named: "start"))
        #expect(start.contains("V2FixtureRuntime.isActive"))
        if let guardRange = start.range(of: "V2FixtureRuntime.isActive"),
            let preparing = start.range(of: "phase = .preparing")
        {
            #expect(guardRange.lowerBound < preparing.lowerBound)
        }
        if let guardRange = start.range(of: "V2FixtureRuntime.isActive"),
            let overlay = start.range(of: "DictationOverlayController.shared.setVisible(true)")
        {
            #expect(guardRange.lowerBound < overlay.lowerBound)
        }
    }

    @Test func runnerRefusesBinariesWithoutTheDebugSeamBeforeMktemp() throws {
        let script = try granipaSource("Scripts/v2-fixture.sh")
        let executable = try #require(script.range(of: #"[ ! -x "$BIN" ]"#))
        let strings = try #require(script.range(of: #"strings "$BIN""#))
        let grep = try #require(script.range(of: #"grep -F -- '--v2-fixture' >/dev/null"#))
        let mktemp = try #require(script.range(of: #"mktemp -d /private/tmp/granipa-v2-fixture"#))
        #expect(executable.lowerBound < strings.lowerBound)
        #expect(strings.lowerBound < grep.lowerBound)
        #expect(grep.lowerBound < mktemp.lowerBound)
        #expect(!script.contains("grep -q"))
    }
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}

private func elseArm(in source: String, after needle: String) -> String? {
    guard let needleRange = source.range(of: needle) else { return nil }
    let tail = source[needleRange.upperBound...]
    guard let elseRange = tail.range(of: "#else") else { return nil }
    let afterElse = tail[elseRange.upperBound...]
    guard let endif = afterElse.range(of: "#endif") else { return nil }
    return String(afterElse[..<endif.lowerBound])
}

private func methodBody(
    _ source: String, named name: String, signatureContains: String? = nil
) -> String? {
    var searchFrom = source.startIndex
    while let header = source.range(of: "func \(name)", range: searchFrom..<source.endIndex) {
        let afterName = source[header.upperBound...]
        if let extra = signatureContains, !afterName.prefix(120).contains(extra) {
            searchFrom = header.upperBound
            continue
        }
        guard let open = afterName.firstIndex(of: "{") else { return nil }
        return bracedBody(in: source, opening: open)
    }
    return nil
}

private func bracedBody(in source: String, opening: String.Index) -> String? {
    var depth = 0
    var index = opening
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 {
                return String(source[source.index(after: opening)..<index])
            }
        }
        index = source.index(after: index)
    }
    return nil
}
#endif
