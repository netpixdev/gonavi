import CoreImage
import Foundation
import GonaviCore
import ImageIO
import UniformTypeIdentifiers

/// ImageIO performs format detection and EXIF orientation. Keep photo decoding
/// separate from AVAsset inspection, which treats stills as zero-duration media.
enum PhotoSource {
    private static let maximumPixels = 100_000_000.0

    static func isImageURL(_ url: URL) -> Bool {
        let resourceType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return (resourceType ?? UTType(filenameExtension: url.pathExtension))?.conforms(to: .image) == true
    }

    private static func open(_ url: URL) throws -> (source: CGImageSource, index: Int, orientation: Int32) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String),
              [UTType.jpeg, .png, .heic, .tiff].contains(where: { type.conforms(to: $0) }) else {
            throw ProjectError.invalid("Fotoğraf okunamadı: \(url.lastPathComponent). JPEG, PNG, HEIC veya TIFF kullanın.")
        }
        // A HEIC container can contain auxiliary images before its main image.
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard index < CGImageSourceGetCount(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ProjectError.invalid("Fotoğraf okunamadı: \(url.lastPathComponent). JPEG, PNG, HEIC veya TIFF kullanın.")
        }
        let w = width.doubleValue, h = height.doubleValue
        guard w.isFinite, h.isFinite, w > 0, h > 0, w * h <= maximumPixels else {
            throw ProjectError.invalid("Fotoğraf en fazla 100 megapiksel olabilir: \(url.lastPathComponent)")
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        return (source, index, (1...8).contains(orientation) ? orientation : 1)
    }

    static func validate(_ url: URL) throws {
        let opened = try open(url)
        // Verify actual decoding as well as metadata before adding a source.
        guard CGImageSourceCreateThumbnailAtIndex(opened.source, opened.index, thumbnailOptions(maximum: 64)) != nil else {
            throw ProjectError.invalid("Fotoğrafın piksel verisi okunamadı: \(url.lastPathComponent)")
        }
    }

    static func image(_ url: URL) throws -> CIImage {
        let opened = try open(url)
        guard let decoded = CGImageSourceCreateImageAtIndex(opened.source, opened.index,
            [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ProjectError.invalid("Fotoğraf oluşturulamadı: \(url.lastPathComponent)")
        }
        let image = CIImage(cgImage: decoded).oriented(forExifOrientation: opened.orientation)
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    static func thumbnail(_ url: URL, maximum: Int = 1920) throws -> CGImage {
        let opened = try open(url)
        guard let image = CGImageSourceCreateThumbnailAtIndex(opened.source, opened.index,
            thumbnailOptions(maximum: max(1, maximum))) else {
            throw ProjectError.invalid("Fotoğraf önizlemesi oluşturulamadı: \(url.lastPathComponent)")
        }
        return image
    }

    private static func thumbnailOptions(maximum: Int) -> CFDictionary {
        [kCGImageSourceCreateThumbnailFromImageAlways: true,
         kCGImageSourceCreateThumbnailWithTransform: true,
         kCGImageSourceThumbnailMaxPixelSize: maximum,
         kCGImageSourceShouldCacheImmediately: true] as CFDictionary
    }
}
