# 验证记录 · 2026-10-24

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
