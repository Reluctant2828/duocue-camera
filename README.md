# 镜头小剧场 · DuoCue

给 iPhone Duo 的自用相机：在内屏取景和拍摄，在外屏循环播放你导入的 GIF 或视频。使用原生 SwiftUI、AVFoundation 和 iOS 27.1 的 `CameraCaptureAccessory`，没有第三方运行时依赖。

## 当前交付状态

源码、Xcode 工程、Windows 检查工具和手动云端构建配置保存在这里。**在 Windows 上通过项目检查，不代表已经编译 iOS App。IPA 只有云端构建成功后才会产生；安装、相机和 Duo 外屏效果必须在真机验收。**

设备要求：iPhone Duo，iOS 27.1 或更高版本。外屏内容只能在本 App 的拍摄界面、活动相机采集期间由系统显示；系统会在退后台、合拢或其他不满足条件时收回内容。它不会替换苹果“相机”里固定的“看看镜头”素材。

## Windows 本地检查

```powershell
cd 'D:\苹果相机'
python scripts/generate_project.py
python scripts/check_project.py
python -m unittest discover -s scripts/tests -v
```

工程生成器只依赖 Python 标准库，按实际 Swift 文件生成完整可打开的 `DuoCue.xcodeproj`；新增 Swift 源码后重新运行。`--check` 是不写文件的检查模式。

## 云端编译：不需要购买 Mac

本地开发与编译分离：Windows 修改源码，GitHub Actions 的 Mac 用 Xcode 27.1 编译 arm64 iPhone App，然后回到 Windows 安装。云端只需要源码，不需要你的动画、照片、Apple 密码或签名证书。

用户已确认 GitHub 账号 `Reluctant2828`、私有仓库 `duocue-camera` 和本工程源码上传范围。工程不会自动上传或自动启动云端任务；每次构建仍受免费额度和零付费预算约束。

确认后采用以下流程：

1. 在 GitHub 的 Billing 中确认有可用 Actions 免费额度，检查 Mac runner 的额度倍率，并将付费超额预算/支出限制设为 0。额度不够就停止；不用默认开启付费继续运行。
2. 将审核过的工程上传到确认的私有仓库。忽略构建产物、动画、拍摄文件、证书和本机配置。
3. 到仓库 Actions → **Build iOS IPA** → **Run workflow**，仅在免费额度足够时勾选确认项。
4. 工作流选择 `xcode-27` runner，固定 `/Applications/Xcode_27.1.app`，验证 iOS 27.1 SDK 后进行检查、存在 XCTest 时运行测试，再编译真机包。最长运行 20 分钟，不会因 push 或定时任务自动触发。
5. 成功后下载 `DuoCue-unsigned-运行编号` artifact，解压得到 `DuoCue-unsigned.ipa` 和 SHA-256 校验文件。未签名 IPA 需要在下一步由侧载工具签名，不能直接点开安装。

也可用只读状态脚本（仓库名称换成已确认名称）：

```powershell
.\scripts\Build-Status.ps1 -Repository 'Reluctant2828/已确认的仓库名'
```

显式启动一次构建才使用 `-Dispatch -ConfirmFreeQuota`。脚本会检查账号和私有仓库，默认不会改变远程状态。它无法替你实时保证账单额度，请在启动前检查 GitHub Billing。

## 在 Windows 安装到 Duo

1. 从 [Sideloadly 官方网站](https://sideloadly.io/) 获取 Windows 版本；按其官方安装要求准备 Apple Mobile Device 驱动（iTunes/iCloud 组件）。
2. USB 连接 Duo，解锁手机并点“信任这台电脑”。
3. 在 Sideloadly 中选中 Duo，将 `DuoCue-unsigned.ipa` 拖进去，使用你自己的 Apple 账号在工具内完成登录和签名。无需把密码发给任何人，也不把它写入本项目或云端。
4. 如系统要求，打开“设置 → 隐私与安全性 → 开发者模式”，按提示重启并确认；在“通用 → VPN 与设备管理”信任你自己的开发者身份。
5. 启动“镜头小剧场”，展开 Duo，允许相机，在外屏验证模式中观察动画；随后按 [真机验收表](docs/DEVICE_TESTS.md) 测试。

免费 Apple 账号的侧载 App 通常 7 天需要续签，并受同时安装数量限制。可按 [Sideloadly FAQ](https://sideloadly.io/faq.html) 配置自动刷新；电脑需能通过 USB 或已配对 Wi-Fi 识别设备。更新时沿用同一账号和 Bundle ID，以覆盖安装并保留本地素材；不要先卸载 App。

## 数据与恢复

- 动画及选择保存在 App 私有目录，导入使用系统选择器，不扫描整个相册。
- 动画默认静音；录像声音来自麦克风，动画不写进拍摄文件。
- 拍摄先写入本机待保存队列，再尝试写入系统相册。相册权限被拒绝或保存失败时，保留原文件并允许重试。
- 删除或卸载 App 会清除其私有目录。重要拍摄请确认已保存到系统相册。

## 验证边界

Windows 只能检查工程引用、XML/JSON、权限声明和打包工具。Swift 编译由 Xcode 完成，免费签名能否安装、外屏是否出现、相机方向/收音和中断恢复由真机确认。具体测试步骤见 [DEVICE_TESTS.md](docs/DEVICE_TESTS.md)。

苹果接口参考：[CameraCaptureAccessory](https://developer.apple.com/documentation/swiftui/cameracaptureaccessory) · [相机外屏配件](https://developer.apple.com/documentation/avfoundation/registering-a-camera-capture-accessory-on-iphone-duo)。
