import Foundation

enum MeetingASRPolicy {
    static func usesMuseForSystem(
        engine: String? = UserDefaults.standard.string(forKey: "meetingSystemEngine"),
        hasMuseKey: Bool = KeychainStore.hasMuseKey()
    ) -> Bool {
        engine == "muse" && hasMuseKey
    }

    /// Live SpeechAnalyzer during Record pegs a core (~125% CPU) and freezes
    /// the UI. Default is file transcription after Stop.
    static func usesLiveASR(
        flag: Bool? = UserDefaults.standard.object(forKey: "liveMeetingASR") as? Bool
    ) -> Bool {
        flag ?? false
    }

    /// Captions overlay is empty without live ASR, and setVisible no-ops when
    /// the captions pref is off. Captions default ON; live ASR default OFF.
    static func usesLiveCaptions(
        live: Bool? = UserDefaults.standard.object(forKey: "liveMeetingASR") as? Bool,
        captions: Bool? = UserDefaults.standard.object(forKey: "meetingCaptionsEnabled") as? Bool
    ) -> Bool {
        usesLiveASR(flag: live) && (captions ?? true)
    }
}
