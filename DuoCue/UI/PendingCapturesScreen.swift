import SwiftUI
import UIKit

struct PendingCapturesScreen: View {
    @ObservedObject var repository: CaptureRepository
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("拍摄完成后自动保存到系统相册", systemImage: "photo.badge.checkmark")
                    Text("保存成功的文件可在“照片”中查看。下面只列出尚未保存成功的本地文件；你可以重试保存或导出。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if repository.items.isEmpty {
                    ContentUnavailableView("没有待保存文件", systemImage: "checkmark.circle",
                                           description: Text("拍摄后请到系统“照片”中查看。"))
                } else {
                    Section("待保存 · \(repository.items.count)") {
                        ForEach(repository.items) { item in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: item.kind == .photo ? "photo" : "video")
                                    Text(item.kind == .photo ? "照片" : "录像").font(.headline)
                                    Spacer()
                                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button("保存到相册") { Task { await repository.saveToPhotos(item) } }
                                        .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                                        .disabled(repository.isSaving)
                                    ShareLink(item: repository.fileURL(for: item)) {
                                        Label("导出", systemImage: "square.and.arrow.up")
                                    }.buttonStyle(.bordered)
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                }
                if let message = repository.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("保存记录")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .overlay { if repository.isSaving { ProgressView("正在保存…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .alert("保存提示", isPresented: Binding(get: { repository.errorMessage != nil },
                                                set: { if !$0 { repository.errorMessage = nil } })) {
                Button("好", role: .cancel) { repository.errorMessage = nil }
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } message: { Text(repository.errorMessage ?? "") }
        }.preferredColorScheme(.dark)
    }
}
