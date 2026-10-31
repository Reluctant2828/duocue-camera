import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import DuoCue

final class StillImageDecoderTests: XCTestCase {
    func testLargePortraitPhotoIsDownsampledAndEXIFRotationApplied() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orientation-\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 40), format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }())
        let image = renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 40)) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let decoded = try StillImageDecoder.decode(url: url, maxPixelSize: 60)
        XCTAssertEqual(decoded.width, 20)
        XCTAssertEqual(decoded.height, 60)
    }

    func testUnreadableImageThrowsInsteadOfDisplayingStaleFrame() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).png")
        XCTAssertThrowsError(try StillImageDecoder.decode(url: missing))
    }
}
