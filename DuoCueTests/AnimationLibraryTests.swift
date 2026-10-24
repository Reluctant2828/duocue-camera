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

    private var tinyGIF: Data {
        Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7") ?? Data()
    }
}
