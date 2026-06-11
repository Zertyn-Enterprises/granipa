import Foundation
import Sparkle

@MainActor
final class UpdaterManager {
    static let shared = UpdaterManager()
    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    private init() {
        // Sparkle needs a real .app bundle with a feed URL AND a decodable
        // EdDSA public key; with the placeholder still in Info.plist the
        // updater fails to start and alerts at launch on every build.
        guard Bundle.main.bundlePath.hasSuffix(".app"),
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !publicKey.isEmpty,
            publicKey != "SPARKLE_ED_PUBLIC_KEY_PLACEHOLDER"
        else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
