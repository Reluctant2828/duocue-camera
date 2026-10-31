import Combine
import Foundation

/// User preference and system capability are deliberately separate. A withdrawn
/// accessory must never erase the selected animation or the user's preference.
@MainActor
final class OuterDisplayState: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "outerAnimationEnabled") }
    }
    @Published var isAvailable = false
    @Published var isPresented = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: "outerAnimationEnabled") as? Bool ?? true
    }

    var status: String {
        if !isEnabled { return "外屏素材已关闭" }
        if isPresented && isAvailable { return "外屏正在显示" }
        if isAvailable { return "外屏已就绪" }
        return "展开手机，保持相机全屏"
    }
}
