import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let onCaptureRotation: (CGFloat) -> Void
    let onFocus: (CGPoint) -> Void
    let onZoom: (CGFloat) -> Void
    let currentZoom: CGFloat

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocus = onFocus
        view.onZoom = onZoom
        view.currentZoom = currentZoom
        view.connectRotation(device: device, onCaptureRotation: onCaptureRotation)
        return view
    }

    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.onFocus = onFocus
        view.onZoom = onZoom
        view.currentZoom = currentZoom
        view.connectRotation(device: device, onCaptureRotation: onCaptureRotation)
    }

    static func dismantleUIView(_ view: PreviewSurface, coordinator: ()) {
        view.disconnect()
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var currentZoom: CGFloat = 1
    private var initialZoom: CGFloat = 1
    private let focusIndicator = UIView()
    private let rotationObserver = CameraRotationObserver()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus(_:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))))
        focusIndicator.layer.borderColor = UIColor.systemYellow.cgColor
        focusIndicator.layer.borderWidth = 1.5
        focusIndicator.layer.cornerRadius = 12
        focusIndicator.alpha = 0
        focusIndicator.isUserInteractionEnabled = false
        addSubview(focusIndicator)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        rotationObserver.applyCurrentAngles()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { rotationObserver.previewDidMoveToWindow() }
    }

    func connectRotation(device: AVCaptureDevice?, onCaptureRotation: @escaping (CGFloat) -> Void) {
        rotationObserver.connect(device: device, previewLayer: previewLayer, captureAngleChanged: onCaptureRotation)
    }

    func disconnect() {
        rotationObserver.disconnect()
        previewLayer.session = nil
    }

    @objc private func focus(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        focusIndicator.layer.removeAllAnimations()
        focusIndicator.frame = CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60)
        focusIndicator.alpha = 1
        UIView.animate(withDuration: 0.8, delay: 0.35, options: [.beginFromCurrentState]) {
            self.focusIndicator.alpha = 0
        }
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { initialZoom = currentZoom }
        onZoom?(initialZoom * gesture.scale)
    }
}
