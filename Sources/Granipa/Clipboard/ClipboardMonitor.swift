import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let database: AppDatabase
    private let processingQueue = DispatchQueue(
        label: "com.zertyn.granipa.clipboard-processing", qos: .utility)
    private var task: Task<Void, Never>?
    private var lastChangeCount = NSPasteboard.general.changeCount

    init(database: AppDatabase) {
        self.database = database
    }

    func start() {
        guard isEnabled else { return }
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                if isEnabled { poll() }
                // NSPasteboard exposes no change notification; 1 s is the
                // fastest poll that still feels instant on paste.
                try? await Task.sleep(for: .milliseconds(isEnabled ? 1_000 : 2_000))
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
            let text = urls.map(\.path).joined(separator: "\n")
            processingQueue.async { [database] in
                Self.saveText(text, type: .file, source: source, database: database)
                Self.prune(database: database)
            }
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            processingQueue.async { [database] in
                Self.saveImage(data, source: source, database: database)
                Self.prune(database: database)
            }
        } else if let string = pasteboard.string(forType: .string),
            !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            processingQueue.async { [database] in
                Self.saveText(
                    string,
                    type: ClipboardClassifier.classify(string),
                    source: source,
                    database: database)
                Self.prune(database: database)
            }
        } else {
            return
        }
    }

    nonisolated private static func saveText(
        _ text: String,
        type: ClipboardItemType,
        source: String?,
        database: AppDatabase
    ) {
        if let latest = try? database.latestClipboardItem(),
            latest.type == type,
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

    nonisolated private static func saveImage(
        _ data: Data,
        source: String?,
        database: AppDatabase
    ) {
        guard let rep = NSBitmapImageRep(data: data),
            let png = rep.representation(using: .png, properties: [:]),
            let dir = try? AppPaths.clipboardDirectory()
        else { return }

        if let latest = try? database.latestClipboardItem(),
            latest.type == .image,
            latest.sizeBytes == png.count,
            latest.width == rep.pixelsWide,
            latest.height == rep.pixelsHigh,
            let latestPath = latest.imagePath,
            (try? Data(contentsOf: URL(fileURLWithPath: latestPath))) == png
        {
            return
        }

        let id = UUID().uuidString
        let url = dir.appendingPathComponent("\(id).png")
        guard (try? png.write(to: url)) != nil else { return }
        ImageCache.writeThumbnail(forImageAt: url.path)
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
        do {
            try database.insertClipboardItem(item)
        } catch {
            removeFiles([url.path])
        }
    }

    nonisolated private static func prune(database: AppDatabase) {
        guard let orphanedImages = try? database.pruneClipboardItems() else { return }
        removeFiles(orphanedImages)
    }

    nonisolated private static func removeFiles(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: ImageCache.thumbnailPath(for: path))
        }
    }
}
