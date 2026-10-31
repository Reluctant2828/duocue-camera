import SwiftUI

struct FirstRunGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "sparkles.tv").font(.system(size: 52)).foregroundStyle(.yellow)
                    Text("你取景，\n外屏演一出小剧场。")
                        .font(.largeTitle.weight(.bold))
                    step("1", title: "展开 Duo，保持相机全屏", detail: "内屏朝向你，后置镜头和外屏朝向拍摄对象。首次运行允许相机权限。")
                    step("2", title: "先看外屏上的笑脸", detail: "关闭此说明后，外屏会在系统允许时开始播放。相机顶部可随时开关外屏显示。")
                    step("3", title: "直接使用图片、GIF 或视频", detail: "轻点“选素材”，从相册或文件导入。图片保持显示，GIF 和视频静音循环。预览满意后轻点“使用并返回相机”。")
                    step("4", title: "拍完在系统相册中查看", detail: "首次保存需要相册追加权限，录像时按需申请麦克风权限。保存失败的文件保留在“保存记录”中。")
                    Text("外屏由 iOS 决定何时显示。合拢手机、切到其他 App 或停止相机时，外屏动画会暂停；再次展开并返回相机后恢复。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("开始使用") { dismiss() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .tint(.yellow).foregroundStyle(.black).frame(maxWidth: .infinity)
                    Text("DuoCue \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 所有素材和拍摄文件保存在本机")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(26)
            }.background(Color(white: 0.055))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }

    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.subheadline.bold()).foregroundStyle(.black)
                .frame(width: 28, height: 28).background(.yellow, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
