import SwiftUI

/// Change only the layout algorithm when the device rotates. Keeping the same
/// child positions preserves the UIView/AVCaptureVideoPreviewLayer identities;
/// an if/else with separate stacks would disconnect and recreate the preview.
struct AdaptiveCameraLayout<Preview: View, Controls: View>: View {
    let size: CGSize
    private let preview: Preview
    private let controls: Controls

    init(size: CGSize, @ViewBuilder preview: () -> Preview, @ViewBuilder controls: () -> Controls) {
        self.size = size
        self.preview = preview()
        self.controls = controls()
    }

    var body: some View {
        let landscape = size.width > size.height * 1.25
        let layout = landscape
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        layout {
            preview
            // This modifier remains in both layouts, even when width is nil.
            controls.frame(width: landscape ? min(300, size.width * 0.34) : nil)
        }
    }
}
