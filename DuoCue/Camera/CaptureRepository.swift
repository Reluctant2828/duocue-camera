import Combine
import Foundation
import Photos

enum CaptureKind: String, Codable {
    case photo
    case video
}

struct PendingCapture: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let kind: CaptureKind
    let createdAt: Date
}

/// Kept injectable so recovery and save failures can be verified without
/// requesting real photo-library access from the test process.
struct PhotoLibraryClient {
    var authorizationStatus: () -> PHAuthorizationStatus
    var requestAuthorization: () async -> PHAuthorizationStatus
    var save: (PendingCapture, URL) async throws -> Void

    static let system = PhotoLibraryClient(
        authorizationStatus: { PHPhotoLibrary.authorizationStatus(for: .addOnly) },
        requestAuthorization: { await PHPhotoLibrary.requestAuthorization(for: .addOnly) },
        save: { item, url in
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = item.createdAt
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: item.kind == .photo ? .photo : .video,
                                    fileURL: url, options: options)
            }
        })
}

/// Owns durable copies until PhotoKit confirms that the original has been saved.
/// No photograph or movie is removed merely because permission or a save failed.
final class CaptureRepository: ObservableObject {
    @Published private(set) var items: [PendingCapture]
    @Published private(set) var isSaving = false
    @Published var message: String?
    @Published var errorMessage: String?

    private let disk: CaptureDiskStore
    private let photoLibrary: PhotoLibraryClient
    private var savingIDs: Set<UUID> = []

    init(storageDirectory: URL? = nil, photoLibrary: PhotoLibraryClient = .system) {
        let disk = CaptureDiskStore(directory: storageDirectory)
        self.disk = disk
        self.photoLibrary = photoLibrary
        self.items = disk.initialItems
        if let failure = disk.initialError {
            self.errorMessage = "无法读取待保存文件：\(failure)"
        }
    }

    func fileURL(for item: PendingCapture) -> URL {
        // Unknown or malformed metadata must never produce an arbitrary path.
        disk.safeURL(for: item)
            ?? disk.directory.appendingPathComponent("unavailable-\(item.id.uuidString)")
    }

    /// Recording directly to the durable directory also preserves files if the
    /// app is interrupted before the movie delegate can update the index.
    func newRecordingURL() -> URL {
        disk.directory.appendingPathComponent("video_\(UUID().uuidString).mov")
    }

    @MainActor
    func addPhoto(_ data: Data) async throws -> PendingCapture {
        let result = try await disk.addPhoto(data)
        insert(result.item)
        if let warning = result.warning { errorMessage = warning }
        return result.item
    }

    @MainActor
    func addVideo(at url: URL) async throws -> PendingCapture {
        let result = try await disk.addVideo(at: url)
        insert(result.item)
        if let warning = result.warning { errorMessage = warning }
        return result.item
    }

    @MainActor
    private func insert(_ item: PendingCapture) {
        if !items.contains(where: { $0.id == item.id }) {
            items.insert(item, at: 0)
        }
        message = "已保留在本机，正在保存到相册…"
    }

    @MainActor
    func saveToPhotos(_ item: PendingCapture) async {
        guard !savingIDs.contains(item.id) else { return }
        guard items.contains(item), disk.safeURL(for: item) != nil else {
            errorMessage = "无法保存不属于待保存列表的文件。"
            return
        }
        errorMessage = nil
        savingIDs.insert(item.id)
        isSaving = true
        defer {
            savingIDs.remove(item.id)
            isSaving = !savingIDs.isEmpty
        }

        var authorization = photoLibrary.authorizationStatus()
        if authorization == .notDetermined {
            authorization = await photoLibrary.requestAuthorization()
        }
        guard authorization == .authorized || authorization == .limited else {
            errorMessage = "尚未获得相册保存权限。文件已保留在本机，可到设置中允许添加照片后重试，或分享导出。"
            return
        }

        let url = fileURL(for: item)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "找不到这段拍摄文件，请检查本机存储。"
            return
        }

        do {
            try await photoLibrary.save(item, url)
            do {
                try await disk.remove(item)
                items.removeAll { $0.id == item.id }
                message = "已保存到系统相册"
            } catch {
                // A completed PhotoKit save is authoritative. If the file was
                // already removed before an index write failed, don't offer a
                // dead retry/export row (or save the same photograph twice).
                if !FileManager.default.fileExists(atPath: url.path) {
                    items.removeAll { $0.id == item.id }
                    message = "已保存到系统相册"
                } else {
                    message = "已保存到相册，本机副本暂未清理"
                    errorMessage = "相册已保存成功，本机副本清理失败：\(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "保存到相册失败，原文件仍保留在本机：\(error.localizedDescription)"
        }
    }

    @MainActor
    func retryAll() async {
        errorMessage = nil
        for item in items {
            await saveToPhotos(item)
        }
    }
}

private final class CaptureDiskStore: @unchecked Sendable {
    let directory: URL
    let initialItems: [PendingCapture]
    let initialError: String?

    private let queue = DispatchQueue(label: "app.duocue.capture-files", qos: .utility)
    private var records: [PendingCapture]

    init(directory customDirectory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storageDirectory = customDirectory
            ?? support.appendingPathComponent("DuoCue/Captures", isDirectory: true)
        directory = storageDirectory
        var recovered: [PendingCapture] = []
        var failure: String?
        do {
            try FileManager.default.createDirectory(at: storageDirectory,
                                                    withIntermediateDirectories: true)
            let index = storageDirectory.appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: index.path) {
                do {
                    let decoded = try JSONDecoder().decode([PendingCapture].self,
                                                           from: Data(contentsOf: index))
                    // Only accept an indexed basename; imported metadata can
                    // never point outside the recovery directory.
                    recovered = decoded.filter {
                        guard let url = Self.validatedURL(for: $0, in: storageDirectory) else { return false }
                        return FileManager.default.fileExists(atPath: url.path)
                    }
                } catch {
                    failure = error.localizedDescription
                }
            }

            // Recover files written just before a crash or an interrupted index
            // write, without requiring an intact index.json.
            let files = try FileManager.default.contentsOfDirectory(
                at: storageDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
            for file in files where !recovered.contains(where: { $0.fileName == file.lastPathComponent }) {
                let stem = file.deletingPathExtension().lastPathComponent
                let pieces = stem.split(separator: "_", maxSplits: 1)
                guard pieces.count == 2,
                      let kind = CaptureKind(rawValue: String(pieces[0])),
                      let id = UUID(uuidString: String(pieces[1])),
                      ["jpg", "jpeg", "heic", "mov"].contains(file.pathExtension.lowercased()) else {
                    continue
                }
                let values = try file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                guard (values.fileSize ?? 0) > 0 else { continue }
                let item = PendingCapture(id: id, fileName: file.lastPathComponent,
                                          kind: kind, createdAt: values.creationDate ?? Date())
                guard Self.validatedURL(for: item, in: storageDirectory) != nil else { continue }
                recovered.append(item)
            }
            recovered.sort { $0.createdAt > $1.createdAt }
        } catch {
            failure = error.localizedDescription
        }
        initialItems = recovered
        records = recovered
        initialError = failure
    }

    func safeURL(for item: PendingCapture) -> URL? {
        Self.validatedURL(for: item, in: directory)
    }

    private static func validatedURL(for item: PendingCapture, in directory: URL) -> URL? {
        let name = item.fileName
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"),
              name != ".", name != "..",
              name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        let fileExtension = URL(fileURLWithPath: name).pathExtension.lowercased()
        let extensions = item.kind == .photo ? ["jpg", "jpeg", "heic"] : ["mov"]
        guard extensions.contains(fileExtension),
              name.lowercased() == "\(item.kind.rawValue)_\(item.id.uuidString).\(fileExtension)".lowercased() else {
            return nil
        }
        let url = directory.appendingPathComponent(name).standardizedFileURL
        guard url.deletingLastPathComponent().path == directory.standardizedFileURL.path,
              url.resolvingSymlinksInPath().deletingLastPathComponent().path
                == directory.resolvingSymlinksInPath().standardizedFileURL.path else { return nil }
        return url
    }

    func addPhoto(_ data: Data) async throws -> StoredCapture {
        try await perform {
            let id = UUID()
            let item = PendingCapture(id: id, fileName: "photo_\(id.uuidString).jpg",
                                      kind: .photo, createdAt: Date())
            try data.write(to: self.directory.appendingPathComponent(item.fileName), options: .atomic)
            self.records.insert(item, at: 0)
            return self.resultAfterIndexing(item)
        }
    }

    func addVideo(at url: URL) async throws -> StoredCapture {
        try await perform {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.int64Value ?? 0) > 0 else {
                throw CaptureStorageError.emptyRecording
            }
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "video_", with: "")) ?? UUID()
            let item = PendingCapture(id: id, fileName: "video_\(id.uuidString).mov",
                                      kind: .video, createdAt: Date())
            let destination = self.directory.appendingPathComponent(item.fileName)
            if destination.standardizedFileURL != url.standardizedFileURL {
                try FileManager.default.copyItem(at: url, to: destination)
                // Only remove the source once its durable copy is confirmed.
                try? FileManager.default.removeItem(at: url)
            }
            if !self.records.contains(where: { $0.id == item.id }) {
                self.records.insert(item, at: 0)
            }
            return self.resultAfterIndexing(item)
        }
    }

    func remove(_ item: PendingCapture) async throws {
        try await perform {
            guard self.records.contains(item), let path = self.safeURL(for: item) else {
                throw CaptureStorageError.invalidCapture
            }
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            self.records.removeAll { $0.id == item.id }
            try self.persist()
        }
    }

    private func persist() throws {
        try JSONEncoder().encode(records).write(
            to: directory.appendingPathComponent("index.json"), options: .atomic)
    }

    private func resultAfterIndexing(_ item: PendingCapture) -> StoredCapture {
        do {
            try persist()
            return StoredCapture(item: item, warning: nil)
        } catch {
            // The original is already durable and discoverable by filename.
            // Publish it now even when writing the auxiliary index failed.
            return StoredCapture(item: item,
                                 warning: "原文件已保留，但索引写入失败；仍可保存或导出：\(error.localizedDescription)")
        }
    }

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private struct StoredCapture {
    let item: PendingCapture
    let warning: String?
}

private enum CaptureStorageError: LocalizedError {
    case emptyRecording
    case invalidCapture
    var errorDescription: String? {
        switch self {
        case .emptyRecording: return "录像文件为空，未删除原文件。"
        case .invalidCapture: return "文件不属于待保存目录，已停止操作。"
        }
    }
}
