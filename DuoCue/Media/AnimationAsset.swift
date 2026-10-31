import Foundation

enum AnimationKind: String, Codable {
    case image
    case gif
    case video

    var title: String {
        switch self {
        case .image: return "图片"
        case .gif: return "GIF"
        case .video: return "视频"
        }
    }
}

enum AnimationFit: String, Codable, CaseIterable, Identifiable {
    case fit
    case fill

    var id: String { rawValue }
    var title: String { self == .fit ? "完整显示" : "填满外屏" }
}

struct AnimationAsset: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let fileName: String
    let thumbnailFileName: String?
    let kind: AnimationKind
    let createdAt: Date
}

/// Frame deadlines let playback follow GIF timing even if a slow decode skips a frame.
struct GIFFrameTimeline {
    let deadlines: [TimeInterval]
    let duration: TimeInterval

    init(delays: [TimeInterval]) {
        var end: TimeInterval = 0
        deadlines = delays.map { delay in
            end += delay.isFinite && delay > 0 ? max(delay, 1.0 / 120.0) : 0.1
            return end
        }
        duration = end
    }

    func frame(at elapsed: TimeInterval) -> Int {
        guard !deadlines.isEmpty, duration > 0 else { return 0 }
        let time = max(0, elapsed).truncatingRemainder(dividingBy: duration)
        var lower = 0
        var upper = deadlines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if time < deadlines[middle] {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return min(lower, deadlines.count - 1)
    }
}
