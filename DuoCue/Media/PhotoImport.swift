import Combine
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Requests the original Photos representation instead of asking Photos to
/// manufacture a generic `.data` file (which can flatten animated images).
struct PhotoImportRepresentation: Equatable {
    enum Kind: Equatable { case image, movie }
    let typeIdentifier: String
    let kind: Kind

    static func preferred(in identifiers: [String]) -> Self? {
        if identifiers.contains(UTType.gif.identifier) {
            return Self(typeIdentifier: UTType.gif.identifier, kind: .image)
        }
        if let movie = identifiers.first(where: { UTType($0)?.conforms(to: .movie) == true }) {
            return Self(typeIdentifier: movie, kind: .movie)
        }
        if let image = identifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            return Self(typeIdentifier: image, kind: .image)
        }
        return nil
    }
}

struct ImportedPhotoFile {
    let url: URL
    let directory: URL

    func cleanup() {
        // This directory is created exclusively for this request. Never remove
        // Photos' provider URL, or any file the user originally selected.
        try? FileManager.default.removeItem(at: directory)
    }
}

enum PhotoImportLoader {
    static func load(provider: NSItemProvider,
                     onProgress: @escaping (Progress) -> Void = { _ in }) async throws -> ImportedPhotoFile {
        guard let representation = PhotoImportRepresentation.preferred(in: provider.registeredTypeIdentifiers) else {
            throw PhotoImportError.unsupported
        }
        let result: ImportedPhotoFile
        switch representation.kind {
        case .movie:
            result = try await loadFile(provider: provider, representation: representation, onProgress: onProgress)
        case .image:
            do {
                result = try await loadData(provider: provider, representation: representation, onProgress: onProgress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // Some cloud providers only vend an image as a file. Preserve
                // the same exact type, especially GIF, for this fallback.
                result = try await loadFile(provider: provider, representation: representation, onProgress: onProgress)
            }
        }
        do { try Task.checkCancellation(); return result }
        catch { result.cleanup(); throw error }
    }

    private static func loadData(provider: NSItemProvider, representation: PhotoImportRepresentation,
                                 onProgress: @escaping (Progress) -> Void) async throws -> ImportedPhotoFile {
        let request = ProviderRequest<ImportedPhotoFile>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                request.install(continuation)
                guard !request.isCancelled else { return }
                let progress = provider.loadDataRepresentation(forTypeIdentifier: representation.typeIdentifier) { data, error in
                    do {
                        if let error { throw error }
                        guard let data, !data.isEmpty else { throw PhotoImportError.unreadable }
                        let file = try makeTemporaryFile(name: provider.suggestedName,
                                                         typeIdentifier: representation.typeIdentifier)
                        do {
                            try data.write(to: file.url, options: .atomic)
                            if !request.finish(.success(file)) { file.cleanup() }
                        } catch { file.cleanup(); throw error }
                    } catch { request.finish(.failure(error)) }
                }
                request.setProgress(progress)
                onProgress(progress)
            }
        }, onCancel: { request.cancel() })
    }

    private static func loadFile(provider: NSItemProvider, representation: PhotoImportRepresentation,
                                 onProgress: @escaping (Progress) -> Void) async throws -> ImportedPhotoFile {
        let request = ProviderRequest<ImportedPhotoFile>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                request.install(continuation)
                guard !request.isCancelled else { return }
                let progress = provider.loadFileRepresentation(forTypeIdentifier: representation.typeIdentifier) { url, error in
                    do {
                        if let error { throw error }
                        guard let url else { throw PhotoImportError.unreadable }
                        let file = try makeTemporaryFile(name: provider.suggestedName ?? url.lastPathComponent,
                                                         typeIdentifier: representation.typeIdentifier)
                        do {
                            // Provider files are valid only until this callback
                            // returns. Copy here, not after resuming an await.
                            try FileManager.default.copyItem(at: url, to: file.url)
                            if !request.finish(.success(file)) { file.cleanup() }
                        } catch { file.cleanup(); throw error }
                    } catch { request.finish(.failure(error)) }
                }
                request.setProgress(progress)
                onProgress(progress)
            }
        }, onCancel: { request.cancel() })
    }

    private static func makeTemporaryFile(name: String?, typeIdentifier: String) throws -> ImportedPhotoFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoCue-PhotoImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suggested = name.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        let basename = (suggested?.isEmpty == false ? suggested : nil) ?? "相册素材"
        let candidate = String(basename.prefix(80)).replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-").replacingOccurrences(of: "/", with: "-")
        let safeName = candidate == "." || candidate == ".." || candidate.isEmpty ? "相册素材" : candidate
        let suffix = UTType(typeIdentifier)?.preferredFilenameExtension ?? "data"
        let url = directory.appendingPathComponent(safeName).appendingPathExtension(suffix)
        return ImportedPhotoFile(url: url, directory: directory)
    }
}

/// NSItemProvider may finish after cancellation, or may never invoke its
/// completion when cancelled. Resume exactly once and clean late results.
private final class ProviderRequest<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var progress: Progress?
    private var cancelled = false

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        let result = result
        if result == nil { self.continuation = continuation }
        lock.unlock()
        if let result { continuation.resume(with: result) }
    }

    func setProgress(_ progress: Progress) {
        lock.lock()
        self.progress = progress
        let cancelled = cancelled
        lock.unlock()
        if cancelled { progress.cancel() }
    }

    @discardableResult
    func finish(_ value: Result<Value, Error>) -> Bool {
        lock.lock()
        guard result == nil else { lock.unlock(); return false }
        result = value
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: value)
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let progress = progress
        lock.unlock()
        finish(.failure(CancellationError()))
        progress?.cancel()
    }
}

enum PhotoImportError: LocalizedError {
    case unsupported, unreadable
    var errorDescription: String? {
        switch self {
        case .unsupported: return "请选择图片、GIF 或视频。"
        case .unreadable: return "相册暂时无法提供原始文件。请检查网络后重试，或从“文件”导入。"
        }
    }
}

@MainActor
final class PhotoImportController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var fractionCompleted: Double?
    @Published private(set) var phase = "正在从相册读取…"
    @Published var errorMessage: String?
    private var task: Task<Void, Never>?
    private var progress: Progress?
    private var observation: NSKeyValueObservation?
    private var generation = UUID()
    private var isReadingProvider = false

    func importSelection(_ provider: NSItemProvider, into library: AnimationLibrary) {
        guard !isLoading else { return }
        let token = UUID()
        generation = token
        isLoading = true
        isReadingProvider = true
        fractionCompleted = nil
        phase = "正在从相册读取…"
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.observation = nil
                self.progress = nil
                self.fractionCompleted = nil
                self.isLoading = false
                self.isReadingProvider = false
                self.task = nil
            }
            do {
                let file = try await PhotoImportLoader.load(provider: provider) { [weak self] progress in
                    Task { @MainActor in self?.observe(progress, token: token) }
                }
                defer { file.cleanup() }
                try Task.checkCancellation()
                self.isReadingProvider = false
                self.observation = nil
                self.progress = nil
                self.fractionCompleted = nil
                self.phase = "正在检查并保存素材…"
                await library.importFile(at: file.url)
            } catch is CancellationError { }
            catch {
                self.errorMessage = "导入未完成：\(error.localizedDescription)"
            }
        }
    }

    private func observe(_ progress: Progress, token: UUID) {
        guard generation == token, isLoading, isReadingProvider else { return }
        self.progress = progress
        observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor in
                guard let self, self.generation == token, self.isLoading, self.isReadingProvider else { return }
                self.fractionCompleted = progress.totalUnitCount > 0 ? min(1, max(0, progress.fractionCompleted)) : nil
            }
        }
    }

    func cancel() {
        phase = "正在取消…"
        task?.cancel()
        progress?.cancel()
    }
}

struct PhotoImportPicker: UIViewControllerRepresentable {
    let onSelection: (NSItemProvider?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelection: (NSItemProvider?) -> Void
        init(onSelection: @escaping (NSItemProvider?) -> Void) { self.onSelection = onSelection }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onSelection(results.first?.itemProvider)
        }
    }
}
