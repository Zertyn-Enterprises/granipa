import AppKit

enum AppRelocator {
    // Pure decision so it stays testable: offer only for the launch locations
    // that actually break updates/permissions (Downloads, or the read-only
    // App Translocation mount), never for dev builds running from a checkout.
    static func shouldOffer(bundlePath: String, downloadsPath: String, declined: Bool) -> Bool {
        guard !declined, bundlePath.hasSuffix(".app") else { return false }
        if bundlePath.hasPrefix("/Applications/") { return false }
        return bundlePath.contains("/AppTranslocation/")
            || bundlePath.hasPrefix(downloadsPath + "/")
    }

    @MainActor
    static func offerMoveIfNeeded() {
        let bundleURL = Bundle.main.bundleURL
        let downloads =
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?.path ?? "/var/empty"
        guard
            shouldOffer(
                bundlePath: bundleURL.path,
                downloadsPath: downloads,
                declined: UserDefaults.standard.bool(forKey: "declinedMoveToApplications"))
        else { return }
        let translocated = bundleURL.path.contains("/AppTranslocation/")

        let alert = NSAlert()
        alert.messageText = "Move Grañipa to the Applications folder?"
        alert.informativeText =
            "Grañipa is running from \(translocated ? "a temporary location" : "your Downloads folder"). "
            + "Apps can only keep their permissions and update automatically from the Applications folder."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: "declinedMoveToApplications")
            return
        }

        do {
            let destination = URL(fileURLWithPath: "/Applications/")
                .appendingPathComponent(bundleURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destination)
            // The translocated mount hides the original path, so only clean up
            // the Downloads copy when we can actually see it.
            if !translocated {
                try? FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
            }
            relaunch(at: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Could not move Grañipa"
            failure.informativeText =
                "\(error.localizedDescription)\n\nDrag Grañipa.app to the Applications folder manually, then relaunch it."
            failure.runModal()
        }
    }

    @MainActor
    private static func relaunch(at url: URL) {
        // A detached shell outlives this process; relaunching directly would
        // race our own termination.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(url.path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
