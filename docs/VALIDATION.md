# 验证记录 · 2026-10-31

## 0.2.2 当前交付 · 旋转卡住修复

- 用户确认0.2.1旋转时整个 App 不响应。审查修正横竖屏拆接预览、布局和方向回调内同步写相机连接的风险路径，未取得真机 hang 堆栈，不将静态审查当作死锁点已复现。
- 源码 `ef835d049ae3d5d26d7a1122b88c53d386e5b0a7`，[云端构建 #7](https://github.com/Reluctant2828/duocue-camera/actions/runs/41196266524) 编译与 arm64 archive 成功。
- 38项 XCTest 通过，0 failures；新增的生产布局测试连续16次切换横竖尺寸，原生预览只创建1次，切换期间拆除0次。另4项验证延迟应用、角度合并、旧任务取消和不嵌套重入。
- `dist/ios/DuoCue-0.2.2.ipa` 已核对版本0.2.2/build4、arm64、原 Bundle ID；SHA-256 `d4afc11980dfe2ef3829a5e0966f8c372f2bc44f11ec95e25eb6ddcbf8cc05df`，与云端一致。
- 自动化测试验证视图生命周期与调度；真实 Duo 摄像头/双屏在旋转时是否仍会冻结，必须覆盖安装后确认。

## 0.2.1 历史交付 · 相机方向修复

- 用户报告0.2.0预览存在上下颠倒/横转；此前自动化测试没有覆盖真实相机传感器和跨屏角度。
- 已采用苹果 `AVCaptureDevice.RotationCoordinator`，由实际镜头与预览层提供初始及实时方向。预览/捕获分别使用对应角度，删除手写方向表。
- 源码 `3ef0a265e2509373a37b50d6afa94d88cab65b0b`，[云端构建 #6](https://github.com/Reluctant2828/duocue-camera/actions/runs/41194170358) 编译和 archive 成功，33项 XCTest 全部通过，0 failures。
- 新增4项方向状态测试；系统协调器在真实 Duo 上的输出及最终画面朝向仍须真机验收，不能由模拟器测试替代。
- `dist/ios/DuoCue-0.2.1.ipa` 已核对版本0.2.1/build3、arm64、原Bundle ID及系统方向协调器链接，SHA-256：`4d951f933ac9f29c326454e7a4431ba9e50df98604783cfb305eea72966a5087`。

## 0.2.0 历史交付

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
