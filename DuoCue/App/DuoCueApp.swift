import SwiftUI

@main
struct DuoCueApp: App {
    @StateObject private var library = AnimationLibrary()
    @StateObject private var camera = CameraService()
    @StateObject private var display = OuterDisplayState()

    var body: some Scene {
        WindowGroup {
            CameraScreen(camera: camera, library: library, display: display)
                .preferredColorScheme(.dark)
                .tint(.yellow)
        }
    }
}
