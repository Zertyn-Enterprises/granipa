import Foundation
import Sparkle

@MainActor
final class UpdaterManager {
    static let shared = UpdaterManager()
    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    private init() {
        // Sparkle needs a real .app bundle with a feed URL in Info.plist;
        // `swift run` and test binaries have neither.
        guard Bundle.main.bundlePath.hasSuffix(".app"),
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
