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
                    step("2", title: "先看外屏上的测试动画", detail: "关闭此说明后，外屏会在系统允许时开始播放。相机顶部会显示外屏状态。")
                    step("3", title: "导入你自己的 GIF 或视频", detail: "轻点“选动画”，导入后选择一段。动画静音循环，不会叠加到拍摄文件。")
                    step("4", title: "拍完在系统相册中查看", detail: "首次保存需要相册追加权限，录像时按需申请麦克风权限。保存失败的文件保留在“保存记录”中。")
                    Text("外屏由 iOS 决定何时显示。合拢手机、切到其他 App 或停止相机时，外屏动画会暂停；再次展开并返回相机后恢复。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("开始使用") { dismiss() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .tint(.yellow).foregroundStyle(.black).frame(maxWidth: .infinity)
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
