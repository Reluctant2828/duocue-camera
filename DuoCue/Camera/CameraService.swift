import AVFoundation
import Combine
import Foundation
import UIKit

/// AVCaptureSession and all capture-device mutations are confined to sessionQueue.
/// Published UI properties are changed on the main queue.
final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    let captures = CaptureRepository()

    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 1
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let sessionQueue = DispatchQueue(label: "app.duocue.capture-session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var configured = false
    private var wantsRunning = false
    private var startGeneration = 0
    private var stopRequested = false
    private var movieInFlight = false
    private var recordingRequest = RecordingRequestState()
    private var recordingSetup: Bool { recordingRequest.preparationID != nil }
    private var recordingStopRequested = false
    private var recordingStopSubmitted = false
    private var photoInFlight = false
    private var rotationAngle: CGFloat = 90
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var observers: [NSObjectProtocol] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                             object: session, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                if self.movieInFlight { self.requestRecordingStop() }
                self.publish {
                    $0.isRunning = false
                    $0.statusMessage = "相机暂时被系统中断，恢复后可以继续拍摄"
                }
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                                             object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in
                guard let self, self.wantsRunning else { return }
                self.startSessionIfNeeded()
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                             object: session, queue: nil) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self?.sessionQueue.async { [weak self] in
                guard let self else { return }
                if error?.code == .mediaServicesWereReset, self.wantsRunning {
                    self.startSessionIfNeeded()
                } else {
                    self.publish { $0.errorMessage = error?.localizedDescription ?? "相机运行发生错误，请重新进入拍摄界面。" }
                }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func clearError() {
        publish { $0.errorMessage = nil }
    }

    func start() async {
        let generation: Int = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: -1); return }
                self.startGeneration += 1
                self.wantsRunning = true
                self.stopRequested = false
                continuation.resume(returning: self.startGeneration)
            }
        }
        var permission = AVCaptureDevice.authorizationStatus(for: .video)
        if permission == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted ? .authorized : .denied
        }
        guard permission == .authorized else {
            publish { $0.errorMessage = "请到“设置 → 隐私与安全性 → 相机”允许镜头小剧场使用相机。" }
            return
        }
        let appIsForeground = await MainActor.run {
            UIApplication.shared.applicationState != .background
        }
        guard appIsForeground else { stop(); return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                guard self.startGeneration == generation, self.wantsRunning else {
                    continuation.resume()
                    return
                }
                do {
                    if !self.configured { try self.configureSession() }
                    // A previous recording may still be finishing. Its delegate
                    // keeps the session alive until the output is finalized.
                    if !self.movieInFlight { self.startSessionIfNeeded() }
                } catch {
                    self.publish {
                        $0.isRunning = false
                        $0.errorMessage = error.localizedDescription
                    }
                }
                continuation.resume()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.startGeneration += 1
            self.wantsRunning = false
            self.stopRequested = true
            self.recordingRequest.cancelPreparation()
            if self.movieInFlight {
                self.beginBackgroundCompletion()
                self.requestRecordingStop()
                return
            }
            if self.photoInFlight {
                self.beginBackgroundCompletion()
                return
            }
            self.stopSessionNow()
        }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning, self.wantsRunning,
                  !self.movieInFlight, !self.recordingSetup, !self.photoInFlight else { return }
            self.photoInFlight = true
            self.publish { $0.isBusy = true }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            self.applyRotation(to: self.photoOutput.connection(with: .video))
            let delegate = PhotoCaptureDelegate { [weak self] data, error in
                guard let self else { return }
                self.sessionQueue.async {
                    self.photoDelegates.removeValue(forKey: settings.uniqueID)
                    self.photoInFlight = false
                    self.publish { $0.isBusy = false }
                    if self.stopRequested || !self.wantsRunning { self.stopSessionNow() }
                }
                if let error {
                    self.publish { $0.errorMessage = "拍照失败：\(error.localizedDescription)" }
                    self.endBackgroundCompletion()
                    return
                }
                guard let data else {
                    self.publish { $0.errorMessage = "相机没有返回照片数据，请重试。" }
                    self.endBackgroundCompletion()
                    return
                }
                Task { @MainActor in
                    defer { self.endBackgroundCompletion() }
                    do {
                        let item = try await self.captures.addPhoto(data)
                        await self.captures.saveToPhotos(item)
                    } catch {
                        self.errorMessage = "照片保留失败，请检查存储空间：\(error.localizedDescription)"
                    }
                }
            }
            self.photoDelegates[settings.uniqueID] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func toggleRecording() async {
        // Reserve the operation on the session queue before asking permission,
        // so repeated button taps cannot configure multiple audio inputs.
        let requestID: UUID? = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                if self.movieInFlight {
                    self.requestRecordingStop()
                    continuation.resume(returning: nil)
                    return
                }
                guard self.session.isRunning, self.wantsRunning,
                      !self.photoInFlight,
                      let id = self.recordingRequest.beginPreparation() else {
                    continuation.resume(returning: nil)
                    return
                }
                self.publish { $0.isBusy = true }
                continuation.resume(returning: id)
            }
        }
        guard let requestID else { return }
        var audioPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioPermission == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            audioPermission = granted ? .authorized : .denied
        }
        let canRecordAudio = audioPermission == .authorized
        let appIsForeground = await MainActor.run {
            UIApplication.shared.applicationState != .background
        }
        let wasCancelled = Task.isCancelled
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // A permission prompt may outlive stop(), then start() may run when
            // the app returns. An old grant must not start a new recording or
            // clear a newer request's pending state.
            guard self.recordingRequest.finishPreparation(requestID) else { return }
            guard self.session.isRunning, self.wantsRunning,
                  appIsForeground, !wasCancelled else {
                self.publish { $0.isBusy = false }
                return
            }
            do {
                try self.configureAudio(enabled: canRecordAudio)
                let url = self.captures.newRecordingURL()
                // Reserve room for the movie container to be finalized when
                // storage runs low, instead of recording until the volume fills.
                self.movieOutput.minFreeDiskSpaceLimit = 50 * 1024 * 1024
                self.applyRotation(to: self.movieOutput.connection(with: .video))
                self.movieInFlight = true
                self.recordingStopRequested = false
                self.recordingStopSubmitted = false
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                self.publish {
                    $0.statusMessage = canRecordAudio ? "正在录像，外屏动画保持静音" : "未授权麦克风，正在录制无声视频"
                }
            } catch {
                self.releaseAudio()
                self.publish {
                    $0.isBusy = false
                    $0.errorMessage = "无法开始录像：\(error.localizedDescription)"
                }
            }
        }
    }

    func setZoom(_ value: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let maximum = min(device.maxAvailableVideoZoomFactor, 8)
                let clamped = max(device.minAvailableVideoZoomFactor, min(value, maximum))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                self.publish { $0.zoom = clamped }
            } catch {
                self.publish { $0.errorMessage = "无法调整变焦：\(error.localizedDescription)" }
            }
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let point = CGPoint(x: min(max(devicePoint.x, 0), 1),
                                    y: min(max(devicePoint.y, 0), 1))
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
            } catch {
                self.publish { $0.errorMessage = "无法对焦：\(error.localizedDescription)" }
            }
        }
    }

    func updateOrientation(_ orientation: UIDeviceOrientation) {
        let angle: CGFloat
        switch orientation {
        case .portrait: angle = 90
        case .portraitUpsideDown: angle = 270
        case .landscapeLeft: angle = 0
        case .landscapeRight: angle = 180
        default: return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.rotationAngle = angle
            self.applyRotation(to: self.photoOutput.connection(with: .video))
            // A movie keeps the orientation that it had when recording began.
            if !self.movieInFlight {
                self.applyRotation(to: self.movieOutput.connection(with: .video))
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        else { session.sessionPreset = .high }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            throw CameraError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(photoOutput),
              session.canAddOutput(movieOutput) else { throw CameraError.configurationFailed }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.addOutput(movieOutput)
        videoInput = input
        photoOutput.maxPhotoQualityPrioritization = .quality
        try camera.lockForConfiguration()
        let supports30 = camera.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        }
        if supports30 {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        }
        camera.unlockForConfiguration()
        let maximum = min(camera.maxAvailableVideoZoomFactor, 8)
        publish {
            $0.zoom = camera.videoZoomFactor
            $0.maxZoom = maximum
        }
        applyRotation(to: photoOutput.connection(with: .video))
        applyRotation(to: movieOutput.connection(with: .video))
        configured = true
    }

    private func configureAudio(enabled: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if !enabled {
            if let audioInput { session.removeInput(audioInput); self.audioInput = nil }
            return
        }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        try audioSession.setActive(true)
        if audioInput == nil {
            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                throw CameraError.microphoneUnavailable
            }
            let input = try AVCaptureDeviceInput(device: microphone)
            guard session.canAddInput(input) else { throw CameraError.configurationFailed }
            session.addInput(input)
            audioInput = input
        }
    }

    private func releaseAudio() {
        if let audioInput {
            session.beginConfiguration()
            session.removeInput(audioInput)
            self.audioInput = nil
            session.commitConfiguration()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Called only on sessionQueue. The output may still be starting; retain
    /// stop intent until didStartRecordingTo, and never submit stop twice.
    private func requestRecordingStop() {
        guard movieInFlight, !recordingStopRequested else { return }
        recordingStopRequested = true
        publish {
            $0.isBusy = true
            $0.statusMessage = "正在完成录像，请稍候…"
        }
        stopMovieOutputIfNeeded()
    }

    private func stopMovieOutputIfNeeded() {
        guard !recordingStopSubmitted, movieOutput.isRecording else { return }
        recordingStopSubmitted = true
        movieOutput.stopRecording()
    }

    private func applyRotation(to connection: AVCaptureConnection?) {
        guard let connection,
              connection.isVideoRotationAngleSupported(rotationAngle) else { return }
        connection.videoRotationAngle = rotationAngle
    }

    private func startSessionIfNeeded() {
        guard configured, wantsRunning, !session.isInterrupted else { return }
        if !session.isRunning { session.startRunning() }
        let running = session.isRunning
        publish {
            $0.isRunning = running
            $0.statusMessage = running ? "相机已就绪" : "等待相机恢复"
        }
    }

    private func stopSessionNow() {
        if session.isRunning { session.stopRunning() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        publish { $0.isRunning = false; $0.isBusy = false }
    }

    private func publish(_ update: @escaping (CameraService) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            update(self)
        }
    }

    private func beginBackgroundCompletion() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.backgroundTask == .invalid else { return }
            self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish recording") { [weak self] in
                self?.endBackgroundCompletion()
            }
        }
    }

    private func endBackgroundCompletion() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.backgroundTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let shouldStop = self.recordingStopRequested || self.stopRequested || !self.wantsRunning
            self.publish { $0.isRecording = true; $0.isBusy = shouldStop }
            if shouldStop {
                self.recordingStopRequested = true
                self.stopMovieOutputIfNeeded()
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.movieInFlight = false
            self.recordingStopRequested = false
            self.recordingStopSubmitted = false
            self.releaseAudio()
            self.publish { $0.isRecording = false; $0.isBusy = false }
            if self.stopRequested || !self.wantsRunning { self.stopSessionNow() }
            else { self.startSessionIfNeeded() }
        }
        let cocoaError = error as NSError?
        let didFinish = cocoaError == nil
            || (cocoaError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        guard didFinish else {
            // A failed movie can still have useful bytes. Make it immediately
            // exportable instead of requiring a restart to discover the file.
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.endBackgroundCompletion() }
                do {
                    _ = try await self.captures.addVideo(at: outputFileURL)
                    self.errorMessage = "录像被中断，文件已保留在“保存记录”，可以尝试保存或导出：\(error?.localizedDescription ?? "未知错误")"
                } catch {
                    self.errorMessage = "录像未完整结束，本机文件已保留：\(error.localizedDescription)"
                }
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endBackgroundCompletion() }
            do {
                let item = try await self.captures.addVideo(at: outputFileURL)
                await self.captures.saveToPhotos(item)
            } catch {
                self.errorMessage = "录像文件仍在本机，但登记或保存失败：\(error.localizedDescription)"
            }
        }
    }
}

/// Reservation survives an asynchronous microphone permission request. A stop
/// invalidates that reservation even if the camera starts again before the
/// permission callback arrives.
struct RecordingRequestState {
    private(set) var preparationID: UUID?

    mutating func beginPreparation(id: UUID = UUID()) -> UUID? {
        guard preparationID == nil else { return nil }
        preparationID = id
        return id
    }

    mutating func finishPreparation(_ id: UUID) -> Bool {
        guard preparationID == id else { return false }
        preparationID = nil
        return true
    }

    mutating func cancelPreparation() {
        preparationID = nil
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?, Error?) -> Void
    private var data: Data?
    private var processingError: Error?

    init(completion: @escaping (Data?, Error?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        processingError = error
        if error == nil { data = photo.fileDataRepresentation() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        completion(data, error ?? processingError)
    }
}

private enum CameraError: LocalizedError {
    case cameraUnavailable
    case microphoneUnavailable
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "找不到可用的后置相机，请在 iPhone Duo 真机上运行。"
        case .microphoneUnavailable: return "找不到可用麦克风。"
        case .configurationFailed: return "无法配置拍摄设备，请关闭其他使用相机的应用后重试。"
        }
    }
}
