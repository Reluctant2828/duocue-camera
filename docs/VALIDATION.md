# 验证记录 · 2026-10-31

## 0.2.0 当前交付

- 构建源码：`4da37520d22bc750375a2e837ba39382a82d0740`。
- [云端构建 #5](https://github.com/Reluctant2828/duocue-camera/actions/runs/41192688054)：Xcode 27.1 / iOS 27.1 SDK，模拟器测试和 arm64 archive 全部通过。
- 原生 XCTest：29 项通过，0 failures。包括5项 NSItemProvider 格式、临时文件和取消测试，10项素材库/图片/GIF/真实 MP4/MOV/旧目录测试，7项可靠保存测试，3项录制授权请求测试，2项静图解码测试及2项横竖屏渲染检查。
- Python：6项云端通过（含 macOS 符号链接打包测试）；本机 Windows 为5项通过、1项平台跳过。
- 已检查两张素材库内容布局截图；精简首屏说明，把已选素材提前。截图是带合成素材的布局夹具，不是手机相册或 Duo 外屏的实拍。
- IPA：`dist/ios/DuoCue-0.2.0.ipa`，1,542,513字节；SHA-256 为 `0ac9c914ba04394720141af41b87cfbb2da8ee7accb88248537fbd27abce96ba`，与云端 checksum 一致。
- 已确认 IPA 版本为0.2.0（build 2）、名称DuoCue、Bundle ID `com.reluctant2828.duocue`、最低 iOS27.1、arm64。猫猫图标源文件保持原样。

### 验证边界

用户已确认0.1.0经 SideStore 安装后可使用。0.2.0 的 Photos 原始 GIF、PNG/JPEG、视频文件、取消和持久化链路已用系统提供者 API 与真实生成的媒体文件验证；真实个人相册/iCloud下载、相机收音以及 Duo 外屏仍需覆盖安装后验证。

旧版 Swift5 并发与若干 API 弃用警告仍存在；构建无错误。本次没有将源码检查或模拟器结果标记为 Duo 真机验证通过。

## 0.1.0 历史验证

Windows 与 GitHub Actions 检查通过；这不是 iPhone Duo 真机通过证明。

| 检查 | 结果 |
| --- | --- |
| Xcode 工程生成及源文件引用、共享 scheme | 通过 |
| Info.plist、隐私声明、图标和权限文案 | 通过 |
| 14 个 Swift 文件的 Tree-sitter 语法解析 | 通过；不包含 Apple SDK 类型检查 |
| GitHub Actions YAML 和 Windows PowerShell 脚本语法 | 通过 |
| Python 打包及模拟器选择测试 | 5 项通过，1 项符号链接测试等待 macOS 执行 |
| 原生 XCTest | 10 项通过，0 failures |
| Xcode 编译 / IPA | Xcode 27.1 / iOS 27.1 SDK 编译与 arm64 archive 通过；SideStore 兼容 IPA 已生成 |
| SideStore `appIdName` 兼容 | `CFBundleDisplayName` 为 ASCII `DuoCue`；应用内仍显示中文；IPA 元数据已检查 |
| Windows 侧载、Duo 外屏、实际拍照录像 | 尚未验证 |

云端构建 #2：commit `4b95d09`，[Actions run](https://github.com/Reluctant2828/duocue-camera/actions/runs/40080060345)，2 分 11 秒完成。

原生测试包括损坏素材导入、选择和适配方式持久化、删除选择、GIF 帧时序，以及相册拒绝/失败保留原文件、重启恢复、索引失败和路径校验。

手工审查已修正：横屏预览与输出方向映射、相机授权返回后的后台启动竞态、相册保存失败的主界面提示、录像中断文件立即进入恢复列表。SideStore 兼容修复将 iOS 桌面名称设为 ASCII `DuoCue`，拍摄 UI 仍是中文。

GitHub 只读检查确认当前账号为 `Reluctant2828`。首个云端构建前已确认免费 Actions 配额与 $0 预算阻断。
