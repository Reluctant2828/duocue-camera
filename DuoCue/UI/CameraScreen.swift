import AVFoundation
import SwiftUI
import UIKit

struct CameraScreen: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var library: AnimationLibrary
    @ObservedObject var display: OuterDisplayState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didReadFirstRunGuide") private var didReadGuide = false
    @State private var showingLibrary = false
    @State private var showingCaptures = false
    @State private var showingGuide = false
    @State private var mode: CaptureMode = .photo
    @State private var recordingStartedAt: Date?
    @State private var accessoryEnabled = false

    private var showsSheet: Bool { showingLibrary || showingCaptures || showingGuide }
    private var shouldEnableAccessory: Bool {
        display.isEnabled && !showsSheet && scenePhase == .active && camera.isRunning
    }

    private enum CaptureMode: String, CaseIterable { case photo = "照片", video = "视频" }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if geometry.size.width > geometry.size.height * 1.25 {
                    HStack(spacing: 0) {
                        viewfinder
                        controls.frame(width: min(300, geometry.size.width * 0.34))
                    }
                } else {
                    viewfinder
                    controls
                }
            }
        }
        .background(Color.black)
        .sceneAccessory {
            CameraCaptureAccessory(isEnabled: $accessoryEnabled) {
                OuterAnimationScreen(library: library, display: display)
            }
            .onAvailabilityChange { available in
                Task { @MainActor in
                    display.isAvailable = available
                }
            }
        }
        .onChange(of: shouldEnableAccessory, initial: true) { _, enabled in
            // A modal or system state can suspend presentation without changing
            // the user's persisted switch. Restore it when capture returns.
            accessoryEnabled = enabled
        }
        .task {
            await camera.start()
            if !didReadGuide { showingGuide = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.start() }
            } else if phase == .background {
                camera.stop()
            }
            UIApplication.shared.isIdleTimerDisabled = phase == .active && camera.isRunning && !showsSheet
        }
        .onChange(of: camera.isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running && scenePhase == .active && !showsSheet
        }
        .onChange(of: showsSheet) { _, showing in
            UIApplication.shared.isIdleTimerDisabled = !showing && camera.isRunning && scenePhase == .active
        }
        .onChange(of: camera.isRecording) { _, recording in
            recordingStartedAt = recording ? Date() : nil
        }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showingLibrary) { AnimationLibraryScreen(library: library) }
        .sheet(isPresented: $showingCaptures) { PendingCapturesScreen(repository: camera.captures) }
        .sheet(isPresented: $showingGuide, onDismiss: { didReadGuide = true }) { FirstRunGuide() }
        .alert("相机提示", isPresented: Binding(
            get: { camera.errorMessage != nil },
            set: { if !$0 { camera.clearError() } }
        )) {
            Button("好", role: .cancel) { camera.clearError() }
            Button("打开设置") { openSettings() }
        } message: { Text(camera.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("镜头小剧场").font(.headline)
                Label(display.status, systemImage: display.isPresented ? "rectangle.inset.filled" : "rectangle.portrait.on.rectangle.portrait")
                    .font(.caption2)
                    .foregroundStyle(display.isPresented ? Color.yellow : Color.secondary)
                    .accessibilityIdentifier("outerDisplayStatus")
            }
            Spacer(minLength: 4)
            Group {
                Button {
                    display.isEnabled.toggle()
                } label: {
                    Image(systemName: display.isEnabled ? "play.rectangle.fill" : "pause.rectangle")
                        .font(.title3)
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel(display.isEnabled ? "关闭外屏素材" : "打开外屏素材")
            }
            Button { showingGuide = true } label: {
                Image(systemName: "questionmark.circle").font(.title3).frame(width: 40, height: 44)
            }
            .accessibilityLabel("使用帮助")
            .disabled(camera.isRecording || camera.isBusy)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var viewfinder: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreview(session: camera.session, device: camera.captureDevice,
                              onCaptureRotation: camera.updateCaptureRotation,
                              onFocus: camera.focus, onZoom: camera.setZoom, currentZoom: camera.zoom)
                if !camera.isRunning {
                    VStack(spacing: 14) {
                        Image(systemName: "camera.aperture").font(.system(size: 40)).foregroundStyle(.yellow)
                        Text(camera.errorMessage == nil ? "相机尚未就绪" : "相机暂不可用").font(.headline)
                        Button("重新启动") { Task { await camera.start() } }
                            .buttonStyle(.bordered)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                }
                if let startedAt = recordingStartedAt {
                    VStack {
                        HStack(spacing: 7) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text(startedAt, style: .timer).monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.top, 14)
                        Spacer()
                    }
                }
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Text(String(format: "%.1f×", Double(camera.zoom)))
                            .font(.caption.monospacedDigit().weight(.medium))
                        Slider(value: Binding(get: { Double(camera.zoom) }, set: { camera.setZoom(CGFloat($0)) }),
                               in: 1...Double(max(1.01, min(camera.maxZoom, 10))))
                            .accessibilityLabel("缩放")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .frame(maxWidth: min(geometry.size.width - 32, 360))
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(.horizontal, 10)
        .accessibilityIdentifier("cameraViewfinder")
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 32) {
                ForEach(CaptureMode.allCases, id: \.self) { item in
                    Button(item.rawValue) { mode = item }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == item ? Color.yellow : .secondary)
                        .disabled(camera.isRecording || camera.isBusy)
                }
            }
            HStack(alignment: .center) {
                Button { showingLibrary = true } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "sparkles.tv").font(.title2)
                        Text("选素材").font(.caption)
                    }.frame(width: 70, height: 70)
                }
                .disabled(camera.isRecording || camera.isBusy)
                .accessibilityIdentifier("openAnimationLibrary")
                Spacer()
                Button { shutter() } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 3).frame(width: 78, height: 78)
                        if camera.isRecording {
                            RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                        } else {
                            Circle().fill(mode == .video ? .red : .white).frame(width: 66, height: 66)
                        }
                    }
                }
                .disabled(!camera.isRunning || !camera.isOrientationReady || (camera.isBusy && !camera.isRecording))
                .opacity(camera.isRunning ? 1 : 0.5)
                .accessibilityLabel(camera.isRecording ? "停止录像" : (mode == .video ? "开始录像" : "拍照"))
                .accessibilityIdentifier("shutterButton")
                Spacer()
                Button { showingCaptures = true } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.stack").font(.title2)
                        Text("保存记录").font(.caption)
                    }.frame(width: 70, height: 70)
                }.disabled(camera.isRecording || camera.isBusy)
            }
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle")
                Text(library.selectedAsset?.name ?? "内置笑脸")
                    .lineLimit(1)
            }
            .font(.caption).foregroundStyle(.secondary)
            if let message = camera.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            CaptureSaveStatus(repository: camera.captures) { showingCaptures = true }
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func shutter() {
        if mode == .photo { camera.capturePhoto() }
        else { Task { await camera.toggleRecording() } }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct CaptureSaveStatus: View {
    @ObservedObject var repository: CaptureRepository
    let openRecovery: () -> Void

    var body: some View {
        if repository.isSaving {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("正在保存到相册…").font(.caption)
            }.foregroundStyle(.secondary)
        } else if !repository.items.isEmpty {
            Button(action: openRecovery) {
                Label("\(repository.items.count) 个文件待保存 · 轻点重试或导出", systemImage: "tray.and.arrow.down")
                    .font(.caption).foregroundStyle(.yellow)
            }
        } else if let message = repository.message {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct OuterAnimationScreen: View {
    @ObservedObject var library: AnimationLibrary
    @ObservedObject var display: OuterDisplayState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AnimationPlaybackView(
            asset: library.selectedAsset,
            fileURL: library.selectedAsset.map { library.fileURL(for: $0) },
            fit: library.fit,
            isPlaying: display.isEnabled && scenePhase == .active
        )
        .background(.black)
        .ignoresSafeArea()
        .onAppear { display.isPresented = true }
        .onDisappear { display.isPresented = false }
    }
}
