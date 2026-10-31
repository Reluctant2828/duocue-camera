import AVFoundation
import Foundation
import QuartzCore

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
    private var previewAngle: CGFloat?
    private var lastCaptureAngle: CGFloat?
    private let deferredUpdates = DeferredRotationUpdates()

    func connect(device: AVCaptureDevice?, previewLayer: AVCaptureVideoPreviewLayer,
                 captureAngleChanged: @escaping (CGFloat) -> Void) {
        self.captureAngleChanged = captureAngleChanged
        let changed = self.device?.uniqueID != device?.uniqueID || self.previewLayer !== previewLayer
        self.device = device
        self.previewLayer = previewLayer
        if changed || coordinator == nil { rebuild() }
        else { refreshPreview() }
    }

    func previewDidMoveToWindow() {
        // An unattached layer has no position in the view hierarchy. Recreate
        // the coordinator once it has one, including a move between displays.
        rebuild()
    }

    func refreshPreview() {
        // layoutSubviews must never synchronously mutate an AVCaptureConnection.
        // Only replay the cached preview value after layout has returned.
        guard let coordinator, let previewAngle else { return }
        deferredUpdates.enqueue(previewAngle) { [weak self, weak coordinator] angle in
            guard let self, let coordinator, self.coordinator === coordinator else { return }
            self.applyPreviewAngle(angle)
        }
    }

    func disconnect() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        deferredUpdates.invalidate()
        coordinator = nil
        previewAngle = nil
        lastCaptureAngle = nil
        previewLayer = nil
        device = nil
        captureAngleChanged = nil
    }

    private func rebuild() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        deferredUpdates.invalidate()
        coordinator = nil
        previewAngle = nil
        lastCaptureAngle = nil
        guard let device else { return }
        let source = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        coordinator = source
        // Initial values are essential: the phone may already be upside down
        // when this view is created, with no subsequent orientation event.
        previewAngle = source.videoRotationAngleForHorizonLevelPreview
        refreshPreview()
        publishCaptureAngle(source.videoRotationAngleForHorizonLevelCapture)
        observations.append(source.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] observed, change in
            guard let angle = change.newValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.coordinator === observed else { return }
                self.previewAngle = angle
                self.refreshPreview()
            }
        })
        observations.append(source.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] observed, change in
            guard let angle = change.newValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.coordinator === observed else { return }
                self.publishCaptureAngle(angle)
            }
        })
    }

    private func publishCaptureAngle(_ angle: CGFloat) {
        guard angle.isFinite, lastCaptureAngle != angle else { return }
        lastCaptureAngle = angle
        captureAngleChanged?(angle)
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        guard angle.isFinite, let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        if connection.videoRotationAngle != angle {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            connection.videoRotationAngle = angle
            CATransaction.commit()
        }
    }
}

/// One deferred update per main-actor turn. Rotating a layer can itself produce
/// layout/KVO notifications; callbacks must not re-enter capture mutation while
/// those notifications hold framework locks. Invalidation also drops old work
/// when a preview really disconnects or moves to a different display.
@MainActor
final class DeferredRotationUpdates {
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var pending: (angle: CGFloat, apply: (CGFloat) -> Void)?

    func enqueue(_ angle: CGFloat, apply: @escaping (CGFloat) -> Void) {
        guard angle.isFinite else { return }
        pending = (angle, apply)
        guard task == nil else { return }
        let token = generation
        task = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.generation == token else { return }
            let update = self.pending
            self.pending = nil
            self.task = nil
            if let update { update.apply(update.angle) }
        }
    }

    func invalidate() {
        generation = UUID()
        task?.cancel()
        task = nil
        pending = nil
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
