import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import DuoCue

final class PhotoImportTests: XCTestCase {
    func testPrefersOriginalGIFOverStaticImageRepresentation() {
        let result = PhotoImportRepresentation.preferred(in: [UTType.png.identifier, UTType.gif.identifier])
        XCTAssertEqual(result?.typeIdentifier, UTType.gif.identifier)
        XCTAssertEqual(result?.kind, .image)
        XCTAssertNil(PhotoImportRepresentation.preferred(in: [UTType.plainText.identifier]))
    }

    func testImportsGIFBytesWithoutFlatteningAnimation() async throws {
        let bytes = try animatedGIF()
        let provider = NSItemProvider()
        provider.suggestedName = "原始动图.gif"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.gif.identifier, visibility: .all) { completion in
            completion(bytes, nil)
            return nil
        }

        let result = try await PhotoImportLoader.load(provider: provider)
        defer { result.cleanup() }
        let imported = try Data(contentsOf: result.url)
        XCTAssertEqual(imported, bytes)
        XCTAssertEqual(result.url.pathExtension, "gif")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(imported as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
    }

    func testImportsStaticImageFromSpecificProviderType() async throws {
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8)).pngData { context in
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let provider = NSItemProvider()
        provider.suggestedName = "照片.png"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(bytes, nil)
            return nil
        }
        let result = try await PhotoImportLoader.load(provider: provider)
        defer { result.cleanup() }
        XCTAssertEqual(try Data(contentsOf: result.url), bytes)
        XCTAssertEqual(result.url.pathExtension, "png")
    }

    func testMovieIsCopiedFromProviderFileBeforeItExpires() async throws {
        let original = FileManager.default.temporaryDirectory.appendingPathComponent("provider-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: original) }
        let bytes = Data("provider movie file bytes".utf8)
        try bytes.write(to: original)
        let provider = NSItemProvider()
        provider.suggestedName = "视频"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.quickTimeMovie.identifier,
                                            fileOptions: [], visibility: .all) { completion in
            completion(original, false, nil)
            return nil
        }
        let result = try await PhotoImportLoader.load(provider: provider)
        defer { result.cleanup() }
        XCTAssertNotEqual(result.url, original)
        XCTAssertEqual(try Data(contentsOf: result.url), bytes)
        XCTAssertEqual(result.url.pathExtension, "mov")
        try FileManager.default.removeItem(at: original)
        XCTAssertEqual(try Data(contentsOf: result.url), bytes)
    }

    func testCancelledProviderRequestReturnsWithoutWaitingForCallback() async throws {
        let provider = NSItemProvider()
        let started = expectation(description: "provider request started")
        provider.registerDataRepresentation(forTypeIdentifier: UTType.gif.identifier, visibility: .all) { _ in
            started.fulfill()
            return Progress(totalUnitCount: 100)
        }
        let task = Task { try await PhotoImportLoader.load(provider: provider) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do {
            let file = try await task.value
            file.cleanup()
            XCTFail("Cancelled provider should throw")
        } catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
    }

    private func animatedGIF() throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        for color in [UIColor.red, .blue] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            let cgImage = try XCTUnwrap(image.cgImage)
            CGImageDestinationAddImage(destination, cgImage,
                                      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
