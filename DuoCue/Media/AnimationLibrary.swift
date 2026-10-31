import AVFoundation
import Combine
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

@MainActor
final class AnimationLibrary: ObservableObject {
    @Published private(set) var assets: [AnimationAsset] = []
    @Published var selectedID: UUID? {
        didSet { if !isRestoring { persistCurrentCatalog() } }
    }
    @Published var fit: AnimationFit = .fit {
        didSet { if !isRestoring { persistCurrentCatalog() } }
    }
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    var selectedAsset: AnimationAsset? { assets.first { $0.id == selectedID } }

    private let directory: URL
    private var isRestoring = true
    private var isStorageReady = false
    private var catalogURL: URL { directory.appendingPathComponent("catalog.json") }

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? support.appendingPathComponent("DuoCue/Animations", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: catalogURL.path) {
                let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
                guard catalog.version == 1 else { throw MediaError.unsupportedCatalog }
                // Reject an unsafe catalog before touching any of its referenced files.
                guard catalog.assets.allSatisfy({ item in
                    Self.isSafeFileName(item.fileName)
                        && (item.thumbnailFileName.map(Self.isSafeFileName) ?? true)
                }) else { throw MediaError.unsafeCatalog }
                assets = catalog.assets.filter {
                    FileManager.default.fileExists(atPath: self.directory.appendingPathComponent($0.fileName).path)
                }
                selectedID = assets.contains { $0.id == catalog.selectedID } ? catalog.selectedID : nil
                fit = catalog.fit
                if assets.count != catalog.assets.count {
                    statusMessage = "部分素材文件已不在本机，可以重新导入。"
                }
            }
            isStorageReady = true
            removeAbandonedImports()
        } catch {
            errorMessage = "素材目录读取失败，原文件已保留。\(error.localizedDescription)"
        }
        isRestoring = false
    }

    func fileURL(for asset: AnimationAsset) -> URL {
        // Catalog validation prevents traversal. This fallback also makes external callers safe.
        guard Self.isSafeFileName(asset.fileName) else {
            return directory.appendingPathComponent("invalid-media-file")
        }
        return directory.appendingPathComponent(asset.fileName)
    }

    func thumbnailURL(for asset: AnimationAsset) -> URL? {
        guard let name = asset.thumbnailFileName, Self.isSafeFileName(name) else { return nil }
        return directory.appendingPathComponent(name)
    }

    func select(_ item: AnimationAsset) {
        guard assets.contains(where: { $0.id == item.id }) else { return }
        selectedID = item.id
    }

    func importFile(at sourceURL: URL, suggestedName: String? = nil) async {
        guard !isImporting else { return }
        guard isStorageReady else {
            errorMessage = "素材目录暂时无法写入，请先处理目录读取错误。"
            return
        }
        isImporting = true
        errorMessage = nil
        statusMessage = "正在检查并导入素材…"
        defer { isImporting = false }

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let targetDirectory = directory
        let task = Task.detached(priority: .userInitiated) {
            try await Self.prepareImport(from: sourceURL, directory: targetDirectory,
                                         suggestedName: suggestedName)
        }
        var prepared: AnimationAsset?
        do {
            let result = try await withTaskCancellationHandler(operation: {
                try await task.value
            }, onCancel: { task.cancel() })
            prepared = result
            try Task.checkCancellation()
            var updated = assets
            updated.insert(result, at: 0)
            // Publish only after the complete media and atomic catalog have been committed.
            try writeCatalog(assets: updated, selection: result.id, fit: fit)
            isRestoring = true
            assets = updated
            selectedID = result.id
            isRestoring = false
            prepared = nil
            statusMessage = result.kind == .image
                ? "已导入「\(result.name)」，拍摄时可在外屏显示。"
                : "已导入「\(result.name)」，拍摄时可在外屏循环播放。"
        } catch is CancellationError {
            statusMessage = "已取消导入。"
        } catch {
            errorMessage = Self.readableError(error)
            statusMessage = nil
        }
        if let uncommitted = prepared { removeFiles(for: uncommitted) }
    }

    func importData(_ data: Data, suggestedName: String) async {
        guard !isImporting else { return }
        guard isStorageReady else {
            errorMessage = "素材目录暂时无法写入，请先处理目录读取错误。"
            return
        }
        let requestedName = URL(fileURLWithPath: suggestedName).lastPathComponent
        let name = Self.isSafeFileName(requestedName) ? requestedName : "自定义素材.data"
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duocue-import-\(UUID().uuidString)", isDirectory: true)
        let temp = tempDirectory.appendingPathComponent(name)
        isImporting = true
        statusMessage = "正在读取所选素材…"
        defer {
            isImporting = false
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        do {
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                try data.write(to: temp, options: .atomic)
            }.value
            try Task.checkCancellation()
            isImporting = false
            await importFile(at: temp, suggestedName: suggestedName)
        } catch is CancellationError {
            statusMessage = "已取消导入。"
        } catch {
            errorMessage = Self.readableError(error)
        }
    }

    func delete(_ item: AnimationAsset) {
        guard !isImporting, assets.contains(where: { $0.id == item.id }) else { return }
        let updated = assets.filter { $0.id != item.id }
        let selection = selectedID == item.id ? updated.first?.id : selectedID
        do {
            try writeCatalog(assets: updated, selection: selection, fit: fit)
            isRestoring = true
            assets = updated
            selectedID = selection
            isRestoring = false
            removeFiles(for: item)
            statusMessage = "已删除「\(item.name)」。"
        } catch {
            errorMessage = Self.readableError(error)
        }
    }

    private func persistCurrentCatalog() {
        guard isStorageReady else { return }
        do { try writeCatalog(assets: assets, selection: selectedID, fit: fit) }
        catch { errorMessage = Self.readableError(error) }
    }

    private func writeCatalog(assets: [AnimationAsset], selection: UUID?, fit: AnimationFit) throws {
        guard isStorageReady else { throw MediaError.unavailableStorage }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Catalog(version: 1, assets: assets, selectedID: selection, fit: fit))
        try data.write(to: catalogURL, options: .atomic)
    }

    private func removeFiles(for item: AnimationAsset) {
        if Self.isSafeFileName(item.fileName) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        }
        if let thumbnail = item.thumbnailFileName, Self.isSafeFileName(thumbnail) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(thumbnail))
        }
    }

    private func removeAbandonedImports() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                     includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(".import-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    nonisolated static func isSafeFileName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\") && !value.contains(":")
            && !value.unicodeScalars.contains(where: { $0.value == 0 })
            && URL(fileURLWithPath: value).lastPathComponent == value
    }

    private struct Catalog: Codable {
        let version: Int
        let assets: [AnimationAsset]
        let selectedID: UUID?
        let fit: AnimationFit
    }

    nonisolated private static func prepareImport(from source: URL, directory: URL,
                                                suggestedName: String?) async throws -> AnimationAsset {
        let manager = FileManager.default
        let id = UUID()
        var staging = directory.appendingPathComponent(".import-\(id.uuidString).\(source.pathExtension)")
        var finalURL: URL?
        var thumbnailURL: URL?
        var committed = false
        defer {
            try? manager.removeItem(at: staging)
            if !committed {
                if let finalURL { try? manager.removeItem(at: finalURL) }
                if let thumbnailURL { try? manager.removeItem(at: thumbnailURL) }
            }
        }
        try Task.checkCancellation()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { throw MediaError.emptyFile }
        try manager.copyItem(at: source, to: staging)
        try Task.checkCancellation()

        let kind: AnimationKind
        let fileExtension: String
        let thumbnail: CGImage
        if let imageSource = CGImageSourceCreateWithURL(staging as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let sourceType = CGImageSourceGetType(imageSource),
           let imageType = UTType(sourceType as String), imageType.conforms(to: .image) {
            let isGIF = imageType.conforms(to: .gif)
            kind = isGIF ? .gif : .image
            fileExtension = isGIF ? "gif" : (imageType.preferredFilenameExtension ?? "image")
            let primaryIndex = isGIF ? 0 : CGImageSourceGetPrimaryImageIndex(imageSource)
            guard CGImageSourceGetCount(imageSource) > 0,
                  let image = CGImageSourceCreateThumbnailAtIndex(imageSource, primaryIndex, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw isGIF ? MediaError.corruptGIF : MediaError.corruptImage }
            // Validate each frame with a small thumbnail. The source and decoded
            // full-size frames are not cached, so long GIFs do not fill memory.
            // A still HEIF may have depth/auxiliary frames; only its primary image
            // is needed for display, whereas all animated GIF frames must decode.
            for index in (isGIF ? Array(0..<CGImageSourceGetCount(imageSource)) : [primaryIndex]) {
                try Task.checkCancellation()
                let isDecodable = autoreleasepool {
                    CGImageSourceCreateThumbnailAtIndex(imageSource, index, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 16,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary) != nil
                }
                guard isDecodable, CGImageSourceGetStatusAtIndex(imageSource, index) == .statusComplete,
                      CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) != nil else {
                    throw isGIF ? MediaError.corruptGIF : MediaError.corruptImage
                }
            }
            thumbnail = image
        } else {
            // NSItemProvider frequently hands us .data/.tmp files. Recognize the
            // container instead of rejecting those or blindly renaming MOV to MP4.
            let detectedExtension = try videoContainerExtension(at: staging,
                                                               extensionHint: source.pathExtension)
            if let detectedExtension, staging.pathExtension.lowercased() != detectedExtension {
                let renamed = staging.deletingPathExtension().appendingPathExtension(detectedExtension)
                try manager.moveItem(at: staging, to: renamed)
                staging = renamed
            }
            let asset = AVURLAsset(url: staging)
            let playable = try await asset.load(.isPlayable)
            let protected = try await asset.load(.hasProtectedContent)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard playable, !protected, !tracks.isEmpty else {
                throw MediaError.unsupportedMedia
            }
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw MediaError.unsupportedMedia }
            kind = .video
            // AVFoundation also recognizes older QuickTime files without ftyp.
            // Keeping .mov is safe for that validated QuickTime fallback.
            fileExtension = detectedExtension ?? "mov"
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            thumbnail = try await generator.image(at: .zero).image
        }

        try Task.checkCancellation()
        let mediaName = "\(id.uuidString).\(fileExtension)"
        let imageName = "\(id.uuidString)-thumbnail.jpg"
        let target = directory.appendingPathComponent(mediaName)
        let imageTarget = directory.appendingPathComponent(imageName)
        finalURL = target
        thumbnailURL = imageTarget
        guard let imageData = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82) else {
            throw MediaError.thumbnailFailed
        }
        try imageData.write(to: imageTarget, options: .atomic)
        try manager.moveItem(at: staging, to: target)
        try Task.checkCancellation()
        let nameSource = suggestedName.map { URL(fileURLWithPath: $0) } ?? source
        let rawName = nameSource.deletingPathExtension().lastPathComponent
        let displayName = rawName.hasPrefix("duocue-import-") || rawName.hasPrefix("PhotoImport-")
            || rawName.isEmpty ? "自定义素材" : rawName
        let item = AnimationAsset(id: id, name: String(displayName.prefix(100)), fileName: mediaName,
                                  thumbnailFileName: imageName, kind: kind, createdAt: Date())
        committed = true
        return item
    }

    /// ISO BMFF/QuickTime use ftyp's major brand. Read only a small header; the
    /// complete video stays on disk even when imported from iCloud or Files.
    nonisolated private static func videoContainerExtension(at url: URL, extensionHint: String) throws -> String? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 256) ?? Data()
        if prefix.count >= 12, String(data: prefix[4..<8], encoding: .ascii) == "ftyp" {
            return String(data: prefix[8..<12], encoding: .ascii) == "qt  " ? "mov" : "mp4"
        }
        switch extensionHint.lowercased() {
        case "mov": return "mov"
        case "mp4", "m4v": return "mp4"
        default: return nil
        }
    }

    nonisolated private static func readableError(_ error: Error) -> String {
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain && value.code == NSFileWriteOutOfSpaceError {
            return "手机存储空间不足。请释放空间后再试，已有素材和拍摄文件会保留。"
        }
        if let mediaError = error as? MediaError { return mediaError.localizedDescription }
        return "无法导入或保存素材：\(error.localizedDescription)"
    }

    private enum MediaError: LocalizedError {
        case emptyFile, corruptGIF, corruptImage, unsupportedMedia, thumbnailFailed
        case unsafeCatalog, unsupportedCatalog, unavailableStorage
        var errorDescription: String? {
            switch self {
            case .emptyFile: return "所选文件为空或无法读取，请重新选择。"
            case .corruptGIF: return "这段 GIF 已损坏，无法完整播放。"
            case .corruptImage: return "这张图片已损坏或无法解码，请重新选择。"
            case .unsupportedMedia: return "请选择图片、GIF、MP4 或 MOV 视频。受保护的视频暂时无法导入。"
            case .thumbnailFailed: return "无法生成素材预览，请换一段素材。"
            case .unsafeCatalog: return "素材目录包含无效路径，已停止读取以保护本机文件。"
            case .unsupportedCatalog: return "素材目录版本暂不受支持。"
            case .unavailableStorage: return "素材目录暂时无法写入。"
            }
        }
    }
}
