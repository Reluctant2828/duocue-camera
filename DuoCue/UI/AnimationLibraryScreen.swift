import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AnimationLibraryScreen: View {
    @ObservedObject var library: AnimationLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var photoSelection: PhotosPickerItem?
    @State private var showingFiles = false
    @State private var previewAsset: AnimationAsset?
    @State private var deletionCandidate: AnimationAsset?
    @State private var importTask: Task<Void, Never>?
    @State private var pickerIsLoading = false
    @State private var pickerError: String?

    private var importing: Bool { pickerIsLoading || library.isImporting }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("让镜头前，多一点惊喜。")
                        .font(.title2.weight(.bold))
                    Text("选择一段动画，在外屏静音循环。照片和视频只记录相机拍到的画面。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    importButtons
                    Picker("显示方式", selection: $library.fit) {
                        Text("完整显示").tag(AnimationFit.fit)
                        Text("填满裁切").tag(AnimationFit.fill)
                    }.pickerStyle(.segmented)
                    sampleCard
                    if !library.assets.isEmpty {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(library.assets) { asset in assetCard(asset) }
                        }
                    }
                    if let message = library.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("支持 GIF、MP4、MOV。导入后离线可用。很长的视频或复杂 GIF 可能需要更多处理时间。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(white: 0.055))
            .navigationTitle("动画库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .overlay {
                if importing {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().tint(.yellow)
                            Text("正在导入动画…").font(.subheadline)
                        }
                        .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            importTask = Task { @MainActor in
                pickerIsLoading = true
                defer { pickerIsLoading = false; photoSelection = nil }
                do {
                    guard let imported = try await item.loadTransferable(type: PickedAnimationFile.self) else {
                        throw ImportPickerError.unreadable
                    }
                    defer { try? FileManager.default.removeItem(at: imported.url) }
                    try Task.checkCancellation()
                    await library.importFile(at: imported.url)
                } catch is CancellationError { }
                catch { pickerError = "无法读取这段素材。请重新选择，或从“文件”导入。\n\(error.localizedDescription)" }
            }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.gif, .mpeg4Movie, .quickTimeMovie]) { result in
            switch result {
            case .success(let url):
                importTask = Task { await library.importFile(at: url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { pickerError = error.localizedDescription }
            }
        }
        .sheet(item: $previewAsset) { asset in
            AnimationPreviewScreen(asset: asset, library: library)
        }
        .confirmationDialog("删除这段动画？", isPresented: Binding(
            get: { deletionCandidate != nil }, set: { if !$0 { deletionCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("删除动画", role: .destructive) {
                if let asset = deletionCandidate { library.delete(asset) }
                deletionCandidate = nil
            }
        } message: { Text("仅删除 App 内的副本，相册和原始文件不受影响。") }
        .alert("导入提示", isPresented: Binding(
            get: { pickerError != nil || library.errorMessage != nil },
            set: { if !$0 { pickerError = nil; library.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { pickerError = nil; library.errorMessage = nil }
        } message: { Text(pickerError ?? library.errorMessage ?? "") }
        .interactiveDismissDisabled(importing)
        .onDisappear { importTask?.cancel() }
    }

    private var importButtons: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoSelection, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                Label("从相册导入", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
            Button { showingFiles = true } label: {
                Label("文件", systemImage: "folder").padding(.vertical, 8)
            }.buttonStyle(.bordered)
        }
        .disabled(importing)
    }

    private var sampleCard: some View {
        Button {
            library.selectedID = nil
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "eyes.inverse").font(.system(size: 34))
                    .foregroundStyle(.yellow).frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("内置测试动画").font(.headline)
                    Text("首次安装，用它检查外屏播放").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: library.selectedID == nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(library.selectedID == nil ? Color.yellow : Color.secondary)
            }
            .padding(14).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private func assetCard(_ asset: AnimationAsset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { previewAsset = asset } label: {
                ZStack(alignment: .bottomTrailing) {
                    AssetThumbnail(url: library.thumbnailURL(for: asset))
                        .frame(height: 135).frame(maxWidth: .infinity)
                        .background(.black)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                    Image(systemName: "play.circle.fill").font(.title)
                        .foregroundStyle(.white).shadow(radius: 3).padding(10)
                }
            }.buttonStyle(.plain).accessibilityLabel("预览 \(asset.name)")
            Text(asset.name).font(.subheadline.weight(.medium)).lineLimit(1)
            HStack {
                Text(asset.kind == .gif ? "GIF" : "视频").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    library.select(asset)
                } label: {
                    Image(systemName: library.selectedID == asset.id ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                }
                .accessibilityLabel("使用 \(asset.name)")
                Menu {
                    Button("预览", systemImage: "play") { previewAsset = asset }
                    Button("删除", systemImage: "trash", role: .destructive) { deletionCandidate = asset }
                } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
            }
        }
        .padding(12)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(library.selectedID == asset.id ? Color.yellow : .clear, lineWidth: 1.5) }
    }
}

private struct AssetThumbnail: View {
    let url: URL?
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
            else { Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary) }
        }
        .task(id: url) {
            guard let url else { thumbnail = nil; return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            if !Task.isCancelled, let data { thumbnail = UIImage(data: data) }
        }
    }
}

private struct AnimationPreviewScreen: View {
    let asset: AnimationAsset
    @ObservedObject var library: AnimationLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AnimationPlaybackView(asset: asset, fileURL: library.fileURL(for: asset), fit: library.fit,
                                      isPlaying: scenePhase == .active)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Picker("显示方式", selection: $library.fit) {
                    Text("完整显示").tag(AnimationFit.fit)
                    Text("填满裁切").tag(AnimationFit.fill)
                }.pickerStyle(.segmented)
                Button("使用这段动画") { library.select(asset); dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(.yellow).foregroundStyle(.black)
            }
            .padding(20).background(.black)
            .navigationTitle(asset.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

private struct PickedAnimationFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let fileExtension = received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoImport-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension.isEmpty ? "data" : fileExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

private enum ImportPickerError: LocalizedError {
    case unreadable
    var errorDescription: String? { "素材暂时无法读取。如果它在 iCloud 中，请先下载。" }
}
