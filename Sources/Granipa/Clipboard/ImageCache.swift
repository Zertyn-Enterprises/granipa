import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ImageCache {
    private struct DownsampledImage {
        let image: NSImage
        let byteCost: Int
    }

    static let shared = ImageCache()
    private static let thumbnailCountLimit = 64
    private static let thumbnailCostLimit = 1 * 1024 * 1024
    private static let previewCountLimit = 3
    private static let previewCostLimit = 12 * 1024 * 1024

    private let thumbnails = NSCache<NSString, NSImage>()
    private let previews = NSCache<NSString, NSImage>()

    private init() {
        thumbnails.countLimit = Self.thumbnailCountLimit
        thumbnails.totalCostLimit = Self.thumbnailCostLimit
        previews.countLimit = Self.previewCountLimit
        previews.totalCostLimit = Self.previewCostLimit
    }

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let path = item.imagePath else { return nil }
        let key = path as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let thumbPath = Self.thumbnailPath(for: path)
        let sourcePath = FileManager.default.fileExists(atPath: thumbPath) ? thumbPath : path
        guard
            let loaded = Self.loadDownsampled(path: sourcePath, maxPixel: 44)
                ?? (sourcePath == path ? nil : Self.loadDownsampled(path: path, maxPixel: 44))
        else { return nil }
        thumbnails.setObject(loaded.image, forKey: key, cost: loaded.byteCost)
        return loaded.image
    }

    func preview(for item: ClipboardItem) -> NSImage? {
        guard let path = item.imagePath else { return nil }
        let key = path as NSString
        if let cached = previews.object(forKey: key) { return cached }
        guard let loaded = Self.loadDownsampled(path: path, maxPixel: 1000) else { return nil }
        previews.setObject(loaded.image, forKey: key, cost: loaded.byteCost)
        return loaded.image
    }

    nonisolated static func thumbnailPath(for imagePath: String) -> String {
        let url = URL(fileURLWithPath: imagePath)
        return url.deletingLastPathComponent()
            .appendingPathComponent("thumb_" + url.lastPathComponent)
            .path
    }

    nonisolated static func writeThumbnail(forImageAt path: String) {
        guard
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 88,
                ] as CFDictionary),
            let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: thumbnailPath(for: path)) as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            try? FileManager.default.removeItem(atPath: thumbnailPath(for: path))
        }
    }

    static func downsampled(path: String, maxPixel: CGFloat) -> NSImage? {
        loadDownsampled(path: path, maxPixel: maxPixel)?.image
    }

    private static func loadDownsampled(path: String, maxPixel: CGFloat) -> DownsampledImage? {
        guard
            let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return DownsampledImage(
            image: NSImage(
                cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            byteCost: cgImage.bytesPerRow * cgImage.height)
    }
}
