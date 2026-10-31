import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import DuoCue

@MainActor
final class AnimationLibraryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoCue-MediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    func testCorruptImportLeavesCatalogAndExistingFilesUnchanged() async throws {
        let library = AnimationLibrary(directory: temporaryDirectory)
        await library.importData(tinyGIF, suggestedName: "第一段.gif")
        XCTAssertEqual(library.assets.count, 1)
        let before = try Data(contentsOf: temporaryDirectory.appendingPathComponent("catalog.json"))
        let previous = library.selectedID

        await library.importData(Data("not an animation".utf8), suggestedName: "损坏.gif")

        XCTAssertNotNil(library.errorMessage)
        XCTAssertEqual(library.selectedID, previous)
        XCTAssertEqual(library.assets.count, 1)
        XCTAssertEqual(try Data(contentsOf: temporaryDirectory.appendingPathComponent("catalog.json")), before)
        let names = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".import-") })
    }

    func testSelectionAndFitSurviveRestartAndDeletingSelectionChoosesRemainingAsset() async throws {
        let library = AnimationLibrary(directory: temporaryDirectory)
        await library.importData(tinyGIF, suggestedName: "first.gif")
        await library.importData(tinyGIF, suggestedName: "second.gif")
        XCTAssertEqual(library.assets.count, 2)
        let first = try XCTUnwrap(library.assets.first(where: { $0.name == "first" }))
        library.select(first)
        library.fit = .fill

        let restarted = AnimationLibrary(directory: temporaryDirectory)
        XCTAssertNil(restarted.errorMessage)
        XCTAssertEqual(restarted.selectedID, first.id)
        XCTAssertEqual(restarted.fit, .fill)
        restarted.delete(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.fileURL(for: first).path))
        XCTAssertEqual(restarted.selectedID, restarted.assets.first?.id)

        let final = AnimationLibrary(directory: temporaryDirectory)
        XCTAssertEqual(final.assets.count, 1)
        XCTAssertEqual(final.selectedID, final.assets.first?.id)
    }

    func testUnsafeCatalogIsRejectedWithoutReadingOrDeletingOutsideFile() throws {
        let outside = temporaryDirectory.appendingPathComponent("victim.gif")
        try tinyGIF.write(to: outside)
        let libraryDirectory = temporaryDirectory.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let payload: [String: Any] = [
            "version": 1,
            "assets": [["id": id, "name": "unsafe", "fileName": "../victim.gif",
                        "kind": "gif", "createdAt": 0]],
            "selectedID": id,
            "fit": "fit"
        ]
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: libraryDirectory.appendingPathComponent("catalog.json"))

        let library = AnimationLibrary(directory: libraryDirectory)
        XCTAssertTrue(library.assets.isEmpty)
        XCTAssertNotNil(library.errorMessage)
        XCTAssertEqual(try Data(contentsOf: outside), tinyGIF)
    }

    func testGIFTimelineHonorsFrameDurationsAndWraps() {
        let timeline = GIFFrameTimeline(delays: [0.05, 0.2, 0.1])
        XCTAssertEqual(timeline.frame(at: 0.049), 0)
        XCTAssertEqual(timeline.frame(at: 0.05), 1)
        XCTAssertEqual(timeline.frame(at: 0.249), 1)
        XCTAssertEqual(timeline.frame(at: 0.251), 2)
        XCTAssertEqual(timeline.frame(at: 0.351), 0)
        XCTAssertEqual(timeline.frame(at: -1), 0)
    }

    func testPNGImportDetectsContentWithoutExtensionAndPersistsImageSelection() async throws {
        let library = AnimationLibrary(directory: temporaryDirectory)
        let png = try imageData(type: .png)
        await library.importData(png, suggestedName: "相册图片.data")

        XCTAssertNil(library.errorMessage)
        let asset = try XCTUnwrap(library.selectedAsset)
        XCTAssertEqual(asset.kind, .image)
        XCTAssertEqual(asset.name, "相册图片")
        XCTAssertEqual(library.fileURL(for: asset).pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: library.fileURL(for: asset)), png)
        let restarted = AnimationLibrary(directory: temporaryDirectory)
        XCTAssertEqual(restarted.selectedID, asset.id)
        XCTAssertEqual(restarted.selectedAsset?.kind, .image)
    }

    func testJPEGThumbnailAppliesOriginalOrientation() async throws {
        let library = AnimationLibrary(directory: temporaryDirectory)
        let jpeg = try imageData(type: .jpeg, orientation: 6)
        await library.importData(jpeg, suggestedName: "portrait.jpg")

        XCTAssertNil(library.errorMessage)
        let asset = try XCTUnwrap(library.selectedAsset)
        XCTAssertEqual(asset.kind, .image)
        XCTAssertEqual(try Data(contentsOf: library.fileURL(for: asset)), jpeg)
        let thumbnailURL = try XCTUnwrap(library.thumbnailURL(for: asset))
        let thumbnail = try XCTUnwrap(CGImageSourceCreateWithURL(thumbnailURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(thumbnail, 0, nil))
        XCTAssertLessThan(image.width, image.height, "EXIF orientation 6 must rotate the landscape source")
    }

    func testAnimatedGIFBytesAndAllFramesArePreserved() async throws {
        let bytes = try twoFrameGIF()
        let library = AnimationLibrary(directory: temporaryDirectory)
        await library.importData(bytes, suggestedName: "相册动图.data")

        XCTAssertNil(library.errorMessage)
        let asset = try XCTUnwrap(library.selectedAsset)
        XCTAssertEqual(asset.kind, .gif)
        let file = library.fileURL(for: asset)
        XCTAssertEqual(file.pathExtension, "gif")
        XCTAssertEqual(try Data(contentsOf: file), bytes, "The animation must not be flattened to a still image")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        let gif = (CGImageSourceCopyPropertiesAtIndex(source, 1, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual((gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0, 0.2, accuracy: 0.02)
    }

    func testMP4AndOpaqueQuickTimeMovieImportUseTheirRealContainers() async throws {
        let library = AnimationLibrary(directory: temporaryDirectory.appendingPathComponent("library"))
        for (type, suffix) in [(AVFileType.mp4, "mp4"), (.mov, "mov")] {
            let source = temporaryDirectory.appendingPathComponent("source.\(suffix)")
            try await writeVideo(to: source, fileType: type)
            let original = try Data(contentsOf: source)
            let opaqueURL = temporaryDirectory.appendingPathComponent("provider-\(UUID().uuidString).data")
            try FileManager.default.copyItem(at: source, to: opaqueURL)
            await library.importFile(at: opaqueURL, suggestedName: "来自相册.\(suffix)")

            XCTAssertNil(library.errorMessage)
            let asset = try XCTUnwrap(library.selectedAsset)
            XCTAssertEqual(asset.kind, .video)
            let storedURL = library.fileURL(for: asset)
            XCTAssertEqual(storedURL.pathExtension, suffix)
            XCTAssertEqual(try Data(contentsOf: storedURL), original)
            let tracks = try await AVURLAsset(url: storedURL).loadTracks(withMediaType: .video)
            XCTAssertEqual(tracks.count, 1)
        }
        XCTAssertEqual(library.assets.count, 2)
    }

    func testLegacyVersionOneGIFAndVideoCatalogRemainReadable() throws {
        let gifID = UUID()
        let videoID = UUID()
        try tinyGIF.write(to: temporaryDirectory.appendingPathComponent("legacy.gif"))
        try Data([0]).write(to: temporaryDirectory.appendingPathComponent("legacy.mov"))
        let records = [
            AnimationAsset(id: gifID, name: "旧动图", fileName: "legacy.gif", thumbnailFileName: nil,
                           kind: .gif, createdAt: Date(timeIntervalSince1970: 0)),
            AnimationAsset(id: videoID, name: "旧视频", fileName: "legacy.mov", thumbnailFileName: nil,
                           kind: .video, createdAt: Date(timeIntervalSince1970: 1))
        ]
        struct LegacyCatalog: Encodable {
            let version = 1
            let assets: [AnimationAsset]
            let selectedID: UUID
            let fit: AnimationFit
        }
        try JSONEncoder().encode(LegacyCatalog(assets: records, selectedID: gifID, fit: .fill))
            .write(to: temporaryDirectory.appendingPathComponent("catalog.json"))

        let library = AnimationLibrary(directory: temporaryDirectory)
        XCTAssertNil(library.errorMessage)
        XCTAssertEqual(library.assets, records)
        XCTAssertEqual(library.selectedID, gifID)
        XCTAssertEqual(library.fit, .fill)
    }

    func testCancelledImportLeavesNoPartialFilesOrCatalogEntries() async throws {
        let library = AnimationLibrary(directory: temporaryDirectory)
        let source = temporaryDirectory.appendingPathComponent("cancelled.gif")
        try twoFrameGIF().write(to: source)
        let task = Task { @MainActor in await library.importFile(at: source) }
        task.cancel()
        await task.value

        XCTAssertTrue(library.assets.isEmpty)
        XCTAssertFalse(library.isImporting)
        XCTAssertNil(library.errorMessage)
        let names = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertEqual(names, ["cancelled.gif"])
    }

    private func sourceImage(color: UIColor = .red) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 8), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
        }
        return try XCTUnwrap(image.cgImage)
    }

    private func imageData(type: UTType, orientation: Int = 1) throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try sourceImage(), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func twoFrameGIF() throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output as CFMutableData, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (color, delay) in [(UIColor.red, 0.1), (.blue, 0.2)] {
            CGImageDestinationAddImage(destination, try sourceImage(color: color),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func writeVideo(to url: URL, fileType: AVFileType) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 32,
            AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 32,
            kCVPixelBufferHeightKey as String: 32
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoFixtureError.cannotWrite }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<3 {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, attempts < 200 else {
                    throw writer.error ?? VideoFixtureError.cannotWrite
                }
                attempts += 1
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard status == kCVReturnSuccess, let buffer else { throw VideoFixtureError.cannotWrite }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, frame == 0 ? 0 : 127, CVPixelBufferGetBytesPerRow(buffer) * 32)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 3)) else {
                throw writer.error ?? VideoFixtureError.cannotWrite
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoFixtureError.cannotWrite }
    }

    private enum VideoFixtureError: Error { case cannotWrite }

    private var tinyGIF: Data {
        Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7") ?? Data()
    }
}
