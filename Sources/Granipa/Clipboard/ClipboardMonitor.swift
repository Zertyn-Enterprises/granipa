import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let database: AppDatabase
    private var task: Task<Void, Never>?
    private var lastChangeCount = NSPasteboard.general.changeCount

    init(database: AppDatabase) {
        self.database = database
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                poll()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "clipboardHistoryEnabled") as? Bool ?? true
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard isEnabled else { return }

        let typeIDs = (pasteboard.types ?? []).map(\.rawValue)
        // Standard markers used by password managers and ephemeral copiers.
        guard !typeIDs.contains("org.nspasteboard.ConcealedType"),
            !typeIDs.contains("org.nspasteboard.TransientType")
        else { return }

        let source = NSWorkspace.shared.frontmostApplication?.localizedName

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        {
            saveText(urls.map(\.path).joined(separator: "\n"), type: .file, source: source)
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            saveImage(data, source: source)
        } else if let string = pasteboard.string(forType: .string),
            !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            saveText(string, type: ClipboardClassifier.classify(string), source: source)
        } else {
            return
        }

        if let orphanedImages = try? database.pruneClipboardItems() {
            removeFiles(orphanedImages)
        }
    }

    private func saveText(_ text: String, type: ClipboardItemType, source: String?) {
        if let latest = try? database.latestClipboardItem(),
            latest.textContent == text
        {
            return
        }
        let item = ClipboardItem(
            id: UUID().uuidString,
            type: type,
            textContent: text,
            imagePath: nil,
            sourceApp: source,
            createdAt: .now,
            sizeBytes: text.utf8.count,
            width: nil,
            height: nil)
        try? database.insertClipboardItem(item)
    }

    private func saveImage(_ data: Data, source: String?) {
        guard let rep = NSBitmapImageRep(data: data),
            let png = rep.representation(using: .png, properties: [:]),
            let dir = try? AppPaths.clipboardDirectory()
        else { return }

        if let latest = try? database.latestClipboardItem(),
            latest.type == .image,
            latest.sizeBytes == png.count,
            latest.width == rep.pixelsWide,
            latest.height == rep.pixelsHigh
        {
            return
        }

        let id = UUID().uuidString
        let url = dir.appendingPathComponent("\(id).png")
        guard (try? png.write(to: url)) != nil else { return }
        let item = ClipboardItem(
            id: id,
            type: .image,
            textContent: nil,
            imagePath: url.path,
            sourceApp: source,
            createdAt: .now,
            sizeBytes: png.count,
            width: rep.pixelsWide,
            height: rep.pixelsHigh)
        try? database.insertClipboardItem(item)
    }

    private func removeFiles(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
