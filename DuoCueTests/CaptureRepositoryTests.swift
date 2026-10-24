import Photos
import XCTest
@testable import DuoCue

final class CaptureRepositoryTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoCue-CaptureTests-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func testOriginalExistsBeforeSaveAndSurvivesSaveFailureAndRelaunch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data([0xFF, 0xD8, 0xFF, 0xD9])
        var saverSawOriginal = false
        let client = PhotoLibraryClient(
            authorizationStatus: { .authorized },
            requestAuthorization: { .authorized },
            save: { _, url in
                saverSawOriginal = try Data(contentsOf: url) == original
                throw TestError.saveFailed
            })
        let repository = CaptureRepository(storageDirectory: directory, photoLibrary: client)
        let item = try await repository.addPhoto(original)

        XCTAssertEqual(try Data(contentsOf: repository.fileURL(for: item)), original)
        await repository.saveToPhotos(item)
        XCTAssertTrue(saverSawOriginal)
        XCTAssertEqual(repository.items, [item])
        XCTAssertNotNil(repository.errorMessage)
        XCTAssertFalse(repository.isSaving)

        let relaunched = CaptureRepository(storageDirectory: directory, photoLibrary: client)
        XCTAssertEqual(relaunched.items, [item])
        XCTAssertEqual(try Data(contentsOf: relaunched.fileURL(for: item)), original)
    }

    @MainActor
    func testDeniedPermissionNeverCallsSaverOrRemovesOriginal() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls = 0
        let client = PhotoLibraryClient(
            authorizationStatus: { .denied }, requestAuthorization: { .denied },
            save: { _, _ in calls += 1 })
        let repository = CaptureRepository(storageDirectory: directory, photoLibrary: client)
        let item = try await repository.addPhoto(Data([1, 2, 3]))

        await repository.saveToPhotos(item)

        XCTAssertEqual(calls, 0)
        XCTAssertEqual(repository.items, [item])
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.fileURL(for: item).path))
    }

    @MainActor
    func testSuccessfulSaveRemovesRecoveryCopyAndIndexEntry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PhotoLibraryClient(
            authorizationStatus: { .authorized }, requestAuthorization: { .authorized },
            save: { _, url in XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) })
        let repository = CaptureRepository(storageDirectory: directory, photoLibrary: client)
        let item = try await repository.addPhoto(Data([1, 2, 3]))

        await repository.saveToPhotos(item)

        XCTAssertTrue(repository.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL(for: item).path))
        let relaunched = CaptureRepository(storageDirectory: directory, photoLibrary: client)
        XCTAssertTrue(relaunched.items.isEmpty)
    }

    func testRecoveryFindsMovieWithoutIndexAfterAbruptExit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let fileName = "video_\(id.uuidString).mov"
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent(fileName))
        // Also verify a broken index cannot hide a completed original.
        try Data("broken index".utf8).write(to: directory.appendingPathComponent("index.json"))

        let repository = CaptureRepository(storageDirectory: directory)

        XCTAssertEqual(repository.items.count, 1)
        XCTAssertEqual(repository.items.first?.id, id)
        XCTAssertEqual(repository.items.first?.kind, .video)
        XCTAssertEqual(repository.items.first?.fileName, fileName)
    }

    @MainActor
    func testIndexFailureStillPublishesDurableOriginal() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CaptureRepository(storageDirectory: directory)
        // A directory at the index path forces atomic index writes to fail,
        // while the original media file can still be written normally.
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("index.json"), withIntermediateDirectories: false)

        let bytes = Data([1, 2, 3, 4])
        let item = try await repository.addPhoto(bytes)

        XCTAssertEqual(repository.items, [item])
        XCTAssertEqual(try Data(contentsOf: repository.fileURL(for: item)), bytes)
        XCTAssertNotNil(repository.errorMessage)
        let relaunched = CaptureRepository(storageDirectory: directory)
        XCTAssertEqual(relaunched.items.map(\.id), [item.id])
    }

    @MainActor
    func testForgedCaptureCannotReadOutsideDirectoryOrReachPhotoSaver() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls = 0
        let client = PhotoLibraryClient(
            authorizationStatus: { .authorized }, requestAuthorization: { .authorized },
            save: { _, _ in calls += 1 })
        let repository = CaptureRepository(storageDirectory: directory, photoLibrary: client)
        let original = try await repository.addPhoto(Data([1, 2, 3]))
        let forged = PendingCapture(id: original.id, fileName: "../../outside.jpg",
                                    kind: .photo, createdAt: original.createdAt)

        let protectedURL = repository.fileURL(for: forged)
        await repository.saveToPhotos(forged)

        XCTAssertEqual(protectedURL.deletingLastPathComponent().standardizedFileURL,
                       directory.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: protectedURL.path))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(repository.items, [original])
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.fileURL(for: original).path))
    }

    private enum TestError: Error { case saveFailed }
}
