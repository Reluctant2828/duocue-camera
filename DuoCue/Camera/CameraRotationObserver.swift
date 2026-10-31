import AVFoundation
import Foundation

/// Sensor orientation and the preview layer's location both matter on Duo.
/// Keep this on the main actor: RotationCoordinator delivers KVO on the main
/// queue and uses the layer's position to compute the preview angle.
@MainActor
final class CameraRotationObserver {
    private var device: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private var captureAngleChanged: ((CGFloat) -> Void)?

    func connect(device: AVCaptureDevice?, previewLayer: AVCaptureVideoPreviewLayer,
                 captureAngleChanged: @escaping (CGFloat) -> Void) {
        self.captureAngleChanged = captureAngleChanged
        let changed = self.device?.uniqueID != device?.uniqueID || self.previewLayer !== previewLayer
        self.device = device
        self.previewLayer = previewLayer
        if changed || coordinator == nil { rebuild() }
        else { applyCurrentAngles() }
    }

    func previewDidMoveToWindow() {
        // An unattached layer has no position in the view hierarchy. Recreate
        // the coordinator once it has one, including a move between displays.
        rebuild()
    }

    func applyCurrentAngles() {
        guard let coordinator else { return }
        applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
        captureAngleChanged?(coordinator.videoRotationAngleForHorizonLevelCapture)
    }

    func disconnect() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        coordinator = nil
        previewLayer = nil
        device = nil
        captureAngleChanged = nil
    }

    private func rebuild() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        coordinator = nil
        guard let device else { return }
        let source = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        coordinator = source
        // Initial values are essential: the phone may already be upside down
        // when this view is created, with no subsequent orientation event.
        applyCurrentAngles()
        observations.append(source.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] observed, change in
            guard let angle = change.newValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.coordinator === observed else { return }
                self.applyPreviewAngle(angle)
            }
        })
        observations.append(source.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] observed, change in
            guard let angle = change.newValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.coordinator === observed else { return }
                self.captureAngleChanged?(angle)
            }
        })
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        guard angle.isFinite, let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        if connection.videoRotationAngle != angle { connection.videoRotationAngle = angle }
    }
}

/// Photos follow the current sensor angle; one movie keeps its starting
/// transform. A new movie must pick up rotations that occurred during the last.
struct CaptureRotationState {
    private(set) var latestAngle: CGFloat?
    private(set) var recordingAngle: CGFloat?
    private(set) var isRecording = false
    var movieAngle: CGFloat? { isRecording ? recordingAngle : latestAngle }

    @discardableResult
    mutating func update(_ angle: CGFloat) -> Bool {
        guard angle.isFinite else { return false }
        latestAngle = angle
        return true
    }

    @discardableResult
    mutating func beginRecording() -> CGFloat? {
        guard !isRecording, let latestAngle else { return nil }
        isRecording = true
        recordingAngle = latestAngle
        return recordingAngle
    }

    mutating func finishRecording() {
        isRecording = false
        recordingAngle = nil
    }
}
