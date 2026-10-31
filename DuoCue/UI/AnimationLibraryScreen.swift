import SwiftUI
import UniformTypeIdentifiers

struct AnimationLibraryScreen: View {
    @ObservedObject var library: AnimationLibrary
    @Environment(\.dismiss) private var dismiss
    @StateObject private var photoImport = PhotoImportController()
    @State private var showingPhotos = false
    @State private var selectedPhotoProvider: NSItemProvider?
    @State private var showingFiles = false
    @State private var previewAsset: AnimationAsset?
    @State private var deletionCandidate: AnimationAsset?
    @State private var importTask: Task<Void, Never>?
    @State private var pickerError: String?
    @State private var returnToCameraAfterPreview = false

    private var importing: Bool { photoImport.isLoading || library.isImporting || importTask != nil }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if library.assets.isEmpty {
                        Text("选一份素材，放到外屏。")
                            .font(.title2.weight(.bold))
                    }
                    Text("图片保持显示 · GIF 和视频静音循环")
                        .font(.caption).foregroundStyle(.secondary)
                    importButtons
                    Picker("显示方式", selection: $library.fit) {
                        Text("完整显示").tag(AnimationFit.fit)
                        Text("填满裁切").tag(AnimationFit.fill)
                    }.pickerStyle(.segmented)
                    if let selected = library.selectedAsset {
                        Label("当前使用：\(selected.name)", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(.yellow).lineLimit(2)
                    }
                    if !library.assets.isEmpty {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(library.assets) { asset in assetCard(asset) }
                        }
                    }
                    if let message = library.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    if library.assets.isEmpty {
                        ContentUnavailableView("导入第一份素材", systemImage: "photo.badge.plus",
                            description: Text("从相册选择图片、GIF 或视频，也可以从“文件”中导入。"))
                    }
                    sampleCard
                    Text("支持常见图片、GIF、MP4 和 MOV。iCloud 素材会先下载原文件；导入后离线可用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(white: 0.055))
            .navigationTitle("素材库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("返回相机") { dismiss() }.disabled(importing)
            } }
            .overlay {
                if importing {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        VStack(spacing: 12) {
                            if let fraction = photoImport.fractionCompleted {
                                ProgressView(value: fraction).tint(.yellow).frame(width: 190)
                            } else { ProgressView().tint(.yellow) }
                            Text(photoImport.isLoading ? photoImport.phase : "正在检查并保存素材…").font(.subheadline)
                            Button("取消导入") {
                                photoImport.cancel()
                                importTask?.cancel()
                            }.buttonStyle(.bordered)
                        }
                        .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingPhotos, onDismiss: {
            if let provider = selectedPhotoProvider {
                selectedPhotoProvider = nil
                photoImport.importSelection(provider, into: library)
            }
        }) {
            PhotoImportPicker { provider in
                selectedPhotoProvider = provider
                showingPhotos = false
            }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .movie]) { result in
            switch result {
            case .success(let url):
                importTask = Task { @MainActor in
                    defer { importTask = nil }
                    await library.importFile(at: url)
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { pickerError = error.localizedDescription }
            }
        }
        .sheet(item: $previewAsset, onDismiss: {
            if returnToCameraAfterPreview { returnToCameraAfterPreview = false; dismiss() }
        }) { asset in
            AnimationPreviewScreen(asset: asset, library: library) { returnToCameraAfterPreview = true }
        }
        .confirmationDialog("删除这份素材？", isPresented: Binding(
            get: { deletionCandidate != nil }, set: { if !$0 { deletionCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("删除素材", role: .destructive) {
                if let asset = deletionCandidate { library.delete(asset) }
                deletionCandidate = nil
            }
        } message: { Text("仅删除 App 内的副本，相册和原始文件不受影响。") }
        .alert("导入提示", isPresented: Binding(
            get: { pickerError != nil || photoImport.errorMessage != nil || library.errorMessage != nil },
            set: { if !$0 { pickerError = nil; photoImport.errorMessage = nil; library.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { pickerError = nil; photoImport.errorMessage = nil; library.errorMessage = nil }
        } message: { Text(pickerError ?? photoImport.errorMessage ?? library.errorMessage ?? "") }
        .interactiveDismissDisabled(importing)
    }

    private var importButtons: some View {
        HStack(spacing: 12) {
            Button { showingPhotos = true } label: {
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
                    Text("内置笑脸").font(.headline)
                    Text("不导入素材，也可以直接使用").font(.caption).foregroundStyle(.secondary)
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
                    Image(systemName: asset.kind == .image ? "arrow.up.left.and.arrow.down.right.circle.fill" : "play.circle.fill").font(.title)
                        .foregroundStyle(.white).shadow(radius: 3).padding(10)
                }
            }.buttonStyle(.plain).accessibilityLabel("预览 \(asset.name)")
            Text(asset.name).font(.subheadline.weight(.medium)).lineLimit(1)
            HStack {
                Text(asset.kind.title).font(.caption).foregroundStyle(.secondary)
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
    let onUse: () -> Void
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
                Button("使用并返回相机") { library.select(asset); onUse(); dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(.yellow).foregroundStyle(.black)
            }
            .padding(20).background(.black)
            .navigationTitle(asset.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
