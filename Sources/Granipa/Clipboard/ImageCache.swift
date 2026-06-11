import AppKit
import Foundation
import ImageIO

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let thumbnails = NSCache<NSString, NSImage>()
    private let previews = NSCache<NSString, NSImage>()

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let path = item.imagePath else { return nil }
        let key = path as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let thumbPath = Self.thumbnailPath(for: path)
        let sourcePath = FileManager.default.fileExists(atPath: thumbPath) ? thumbPath : path
        guard let image = Self.downsampled(path: sourcePath, maxPixel: 44) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    func preview(for item: ClipboardItem) -> NSImage? {
        guard let path = item.imagePath else { return nil }
        let key = path as NSString
        if let cached = previews.object(forKey: key) { return cached }
        guard let image = Self.downsampled(path: path, maxPixel: 1000) else { return nil }
        previews.setObject(image, forKey: key)
        return image
    }

    static func thumbnailPath(for imagePath: String) -> String {
        let url = URL(fileURLWithPath: imagePath)
        return url.deletingLastPathComponent()
            .appendingPathComponent("thumb_" + url.lastPathComponent)
            .path
    }

    static func writeThumbnail(forImageAt path: String) {
        guard let image = downsampled(path: path, maxPixel: 88),
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: thumbnailPath(for: path)))
    }

    static func downsampled(path: String, maxPixel: CGFloat) -> NSImage? {
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
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
