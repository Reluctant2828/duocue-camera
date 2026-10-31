import Foundation
import ImageIO

/// Decode only the pixels the display can use; apply EXIF orientation for
/// camera photos without allocating the entire original (often 48 megapixels).
enum StillImageDecoder {
    static func decode(url: URL, maxPixelSize: Int = 2048) throws -> CGImage {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary) else { throw DecodeError.unreadable }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
                    kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw DecodeError.unreadable }
        try Task.checkCancellation()
        return image
    }

    private enum DecodeError: LocalizedError {
        case unreadable
        var errorDescription: String? { "图片无法读取，请重新导入。" }
    }
}
