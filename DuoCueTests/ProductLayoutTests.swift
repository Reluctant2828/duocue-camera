import SwiftUI
import UIKit
import XCTest
@testable import DuoCue

/// Renders synthetic local content only. These attachments let reviewers inspect
/// layout on CI without requesting Photos access or using personal media.
@MainActor
final class ProductLayoutTests: XCTestCase {
    func testMaterialLibraryOnPortraitPhone() async throws {
        try await renderLibrary(size: CGSize(width: 430, height: 900), name: "material-library-phone-portrait")
    }

    func testMaterialLibraryOnLandscapeDuo() async throws {
        try await renderLibrary(size: CGSize(width: 852, height: 393), name: "material-library-duo-landscape")
    }

    private func renderLibrary(size: CGSize, name: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoCue-LayoutTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = AnimationLibrary(directory: directory)
        let fixture = makeFixture()
        let bytes = try XCTUnwrap(fixture.pngData())
        await library.importData(bytes, suggestedName: "布局测试图片.png")
        XCTAssertNil(library.errorMessage)
        XCTAssertEqual(library.assets.count, 1)
        XCTAssertEqual(library.selectedAsset?.kind, .image)

        let host = UIHostingController(rootView:
            AnimationLibraryScreen(library: library).preferredColorScheme(.dark))
        // These are content-size fixtures, not the simulator's physical screen.
        // A hosting controller used directly as the window root is resized by
        // UIWindowScene, which can silently invalidate the requested canvas.
        let container = UIViewController()
        container.view.backgroundColor = .black
        container.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = []
        // Prevent the physical simulator scene's off-canvas safe area from
        // shrinking a child whose synthetic width is larger than that scene.
        host.safeAreaRegions = []
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = .alert + 1
        window.rootViewController = container
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            window.rootViewController = nil
        }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 400_000_000)
        // Apply once more after UIWindowScene has finished sizing the parent.
        // Snapshot only the explicit child content bounds, never the window.
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        XCTAssertEqual(host.view.bounds.size, size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size, size)
        // A blank renderer surface compresses to a tiny PNG. A real material
        // library includes text, navigation and the generated local thumbnail.
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 8_000)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeFixture() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 720, height: 480)).image { context in
            let canvas = CGRect(x: 0, y: 0, width: 720, height: 480)
            UIColor(red: 0.12, green: 0.24, blue: 0.42, alpha: 1).setFill()
            context.fill(canvas)
            UIColor.systemYellow.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 250, y: 110, width: 220, height: 220))
            UIColor.black.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 305, y: 175, width: 24, height: 24))
            context.cgContext.fillEllipse(in: CGRect(x: 391, y: 175, width: 24, height: 24))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            ("DuoCue Preview" as NSString).draw(at: CGPoint(x: 218, y: 365), withAttributes: attributes)
        }
    }
}
