import AppKit
import Foundation
import Vision

enum OCRService {
    static func captureAndCopy() async {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }

        await runScreencapture(to: path)
        guard FileManager.default.fileExists(atPath: path.path) else { return }

        let text = await recognizeText(in: path)
        await MainActor.run {
            guard let text, !text.isEmpty else {
                ToastController.shared.show("No text found")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            ToastController.shared.show("Copied text to clipboard")
        }
    }

    private static func runScreencapture(to path: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", path.path]
                try? process.run()
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private static func recognizeText(in url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                var preferred = LanguageDetection.parseProbeLocales(
                    UserDefaults.standard.string(forKey: "probeLocales"))
                if !preferred.contains(where: { $0.hasPrefix("en") }) {
                    preferred.append("en-US")
                }
                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                let chosen = preferred.filter { id in
                    supported.contains { $0.prefix(2) == id.prefix(2) }
                }
                request.recognitionLanguages = chosen.isEmpty ? ["en-US"] : chosen

                let handler = VNImageRequestHandler(url: url)
                guard (try? handler.perform([request])) != nil,
                    let observations = request.results
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
        }
    }
}
