# DuoCue 0.2.1 · 修复相机画面旋转

用户在0.2.0真机运行中报告相机画面上下颠倒或横转。此前预览和输出分别根据界面/设备方向手动套用固定角度，这没有考虑 Duo 的传感器安装方向及预览层所处显示屏。

## 方向处理

- 使用实际后置镜头和预览层创建 `AVCaptureDevice.RotationCoordinator`，分别读取预览角度和拍摄角度。
- 立即应用初始角度，并持续监听系统变化；预览层加入窗口或跨屏后重建协调器。
- 连接尚未建立时保留角度，连接就绪后重放；首次方向准备完成之前禁止快门。
- 删除所有90/270/0/180固定映射及 `UIDevice.orientation` 方向推断。
- 照片采用当前拍摄角度；每段录像固定开始时的方向，录像中转动得到的新方向用于下一段录像。

苹果参考：[相机旋转处理](https://developer.apple.com/documentation/avfoundation/supporting-device-rotation-in-your-camera-app) · [Duo 相机开发说明](https://developer.apple.com/videos/play/tech-talks/111465/)。

## 更新与验收

沿用现有 Bundle ID、猫猫图标和素材目录，在 SideStore 用相同账号覆盖安装。相册导入改进继续保留。

新增4项方向状态回归，覆盖初始角度等待、传感器角度原值传递、录像期间锁定及下一段恢复、无效值拒绝。模拟器无法证明实际镜头画面上下方向；覆盖更新后需在 Duo 竖握、横握、合拢后重新展开，以及录像前后转动时确认预览和拍摄文件方向。
