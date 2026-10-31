import SwiftUI
import UIKit
import XCTest
@testable import DuoCue

@MainActor
final class AdaptiveCameraLayoutTests: XCTestCase {
    func testRepeatedPortraitLandscapeChangesKeepTheSameNativePreview() async throws {
        let portrait = CGSize(width: 430, height: 900)
        let landscape = CGSize(width: 852, height: 393)
        let model = LayoutSizeModel(size: portrait)
        let counts = PreviewLifecycleCounts()
        let host = UIHostingController(rootView: LayoutLifecycleHarness(model: model, counts: counts))
        let container = UIViewController()
        container.addChild(host)
        host.safeAreaRegions = []
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = []
        container.view.addSubview(host.view)
        host.didMove(toParent: container)

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: portrait))
        }
        window.rootViewController = container
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            window.rootViewController = nil
        }

        host.view.frame = CGRect(origin: .zero, size: portrait)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(counts.created, 1)
        let initialView = try XCTUnwrap(counts.firstViewIdentity)

        for index in 0..<16 {
            let size = index.isMultiple(of: 2) ? landscape : portrait
            model.size = size
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(counts.created, 1, "Rotation \(index) must not recreate the AVCapture preview")
            XCTAssertEqual(counts.dismantled, 0, "Rotation \(index) must not disconnect the session")
            XCTAssertEqual(counts.lastViewIdentity, initialView)
        }
    }
}

@MainActor
private final class LayoutSizeModel: ObservableObject {
    @Published var size: CGSize
    init(size: CGSize) { self.size = size }
}

@MainActor
private final class PreviewLifecycleCounts {
    var created = 0
    var dismantled = 0
    var firstViewIdentity: ObjectIdentifier?
    var lastViewIdentity: ObjectIdentifier?
}

private struct LayoutLifecycleHarness: View {
    @ObservedObject var model: LayoutSizeModel
    let counts: PreviewLifecycleCounts

    var body: some View {
        AdaptiveCameraLayout(size: model.size) {
            NativePreviewLifecycleProbe(counts: counts)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } controls: {
            Text("Synthetic camera controls").frame(height: 100)
        }
        .frame(width: model.size.width, height: model.size.height)
    }
}

private struct NativePreviewLifecycleProbe: UIViewRepresentable {
    let counts: PreviewLifecycleCounts

    func makeCoordinator() -> PreviewLifecycleCounts { counts }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .blue
        counts.created += 1
        let identity = ObjectIdentifier(view)
        if counts.firstViewIdentity == nil { counts.firstViewIdentity = identity }
        counts.lastViewIdentity = identity
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        counts.lastViewIdentity = ObjectIdentifier(view)
    }

    static func dismantleUIView(_ view: UIView, coordinator: PreviewLifecycleCounts) {
        coordinator.dismantled += 1
    }
}
