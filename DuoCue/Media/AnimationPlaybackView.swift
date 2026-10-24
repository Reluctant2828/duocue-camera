import AVFoundation
import ImageIO
import SwiftUI
import UIKit

/// Shares the selected file with the camera accessory without adding it to captured media.
struct AnimationPlaybackView: View {
    let asset: AnimationAsset?
    let fileURL: URL?
    let fit: AnimationFit
    let isPlaying: Bool

    var body: some View {
        ZStack {
            Color.black
            if let asset, let fileURL {
                switch asset.kind {
                case .video:
                    LoopingVideoView(url: fileURL, fit: fit, isPlaying: isPlaying)
                case .gif:
                    GIFPlaybackView(url: fileURL, fit: fit, isPlaying: isPlaying)
                }
            } else {
                LensAttentionAnimation(isPlaying: isPlaying)
            }
        }
        .clipped()
        .accessibilityLabel(asset.map { "外屏动画：\($0.name)" } ?? "外屏验证动画")
    }
}

private struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    let fit: AnimationFit
    let isPlaying: Bool

    func makeUIView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.setSource(url)
        return view
    }

    func updateUIView(_ view: PlayerSurface, context: Context) {
        view.setSource(url)
        view.playerLayer.videoGravity = fit == .fit ? .resizeAspect : .resizeAspectFill
        if isPlaying { view.player?.play() } else { view.player?.pause() }
    }

    static func dismantleUIView(_ view: PlayerSurface, coordinator: ()) {
        view.releasePlayer()
    }

    final class PlayerSurface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private(set) var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?
        private var currentItemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private var failureObserver: NSObjectProtocol?
        private let statusLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            prepareStatusLabel()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            prepareStatusLabel()
        }

        private func prepareStatusLabel() {
            statusLabel.numberOfLines = 0
            statusLabel.textAlignment = .center
            statusLabel.font = .preferredFont(forTextStyle: .callout)
            statusLabel.textColor = UIColor.white.withAlphaComponent(0.75)
            addSubview(statusLabel)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            statusLabel.frame = bounds.insetBy(dx: 18, dy: 18)
        }

        func setSource(_ url: URL) {
            guard currentURL != url else { return }
            releasePlayer()
            currentURL = url
            let player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player
            statusLabel.text = "正在加载动画…"
            currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] queue, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.player === queue else { return }
                    self.observeStatus(of: queue.currentItem)
                }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self, let item = notification.object as? AVPlayerItem,
                          self.player?.currentItem === item else { return }
                    self.statusLabel.text = "动画无法播放，请重新导入这段素材。"
                }
            }
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            backgroundColor = .black
        }

        private func observeStatus(of item: AVPlayerItem?) {
            statusObservation = nil
            guard let item else { return }
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.player?.currentItem === item else { return }
                    switch item.status {
                    case .readyToPlay: self.statusLabel.text = nil
                    case .failed: self.statusLabel.text = "动画无法播放，请重新导入这段素材。"
                    default: self.statusLabel.text = "正在加载动画…"
                    }
                }
            }
        }

        func releasePlayer() {
            currentItemObservation = nil
            statusObservation = nil
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
            failureObserver = nil
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player?.removeAllItems()
            playerLayer.player = nil
            player = nil
            currentURL = nil
        }

        deinit {
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        }
    }
}

private struct GIFPlaybackView: View {
    let url: URL
    let fit: AnimationFit
    let isPlaying: Bool
    @StateObject private var playback = GIFPlaybackController()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let frame = playback.image {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: fit == .fit ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if playback.error == nil {
                    ProgressView().tint(.white)
                }
                if let error = playback.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding()
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: url) { await playback.load(url: url, playing: isPlaying) }
        .onChange(of: isPlaying) { _, playing in playback.setPlaying(playing) }
        .onDisappear { playback.setPlaying(false) }
    }
}

@MainActor
private final class GIFPlaybackController: ObservableObject {
    @Published var image: CGImage?
    @Published var error: String?
    private var decoder: GIFFrameDecoder?
    private var timeline: GIFFrameTimeline?
    private var loopTask: Task<Void, Never>?
    private var currentURL: URL?
    private var elapsed: TimeInterval = 0
    private var lastFrame = -1
    private var generation = UUID()
    private var wantsPlayback = false

    func load(url: URL, playing: Bool) async {
        wantsPlayback = playing
        if currentURL == url, decoder != nil {
            setPlaying(playing)
            return
        }
        loopTask?.cancel()
        loopTask = nil
        let token = UUID()
        generation = token
        currentURL = url
        image = nil
        error = nil
        elapsed = 0
        lastFrame = -1
        decoder = nil
        timeline = nil
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try GIFFrameDecoder(url: url)
            }.value
            try Task.checkCancellation()
            guard token == generation else { return }
            let frames = await prepared.timeline
            let first = try await prepared.frame(at: 0)
            try Task.checkCancellation()
            guard token == generation else { return }
            decoder = prepared
            timeline = frames
            image = first
            lastFrame = 0
            setPlaying(wantsPlayback)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            self.error = "动画读取失败，请重新导入。"
        }
    }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        loopTask?.cancel()
        loopTask = nil
        guard playing, let decoder, let timeline, timeline.deadlines.count > 1 else { return }
        let token = generation
        loopTask = Task { [weak self] in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.elapsed += max(0, now - previous)
                previous = now
                let index = timeline.frame(at: self.elapsed)
                if index != self.lastFrame {
                    do {
                        let frame = try await decoder.frame(at: index)
                        guard !Task.isCancelled, self.generation == token else { return }
                        self.image = frame
                        self.lastFrame = index
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.error = "这段动画包含损坏帧，请重新导入。"
                        return
                    }
                }
                do { try await Task.sleep(nanoseconds: 8_333_333) }
                catch { return }
            }
        }
    }

    deinit { loopTask?.cancel() }
}

private actor GIFFrameDecoder {
    let timeline: GIFFrameTimeline
    private let source: CGImageSource
    private var cache: [Int: CGImage] = [:]
    private var recent: [Int] = []

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                   [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw GIFError.unreadable }
        self.source = source
        let count = CGImageSourceGetCount(source)
        var delays: [TimeInterval] = []
        delays.reserveCapacity(count)
        for index in 0..<count {
            try Task.checkCancellation()
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            let clamped = (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            delays.append(unclamped ?? clamped ?? 0.1)
        }
        timeline = GIFFrameTimeline(delays: delays)
    }

    func frame(at index: Int) throws -> CGImage {
        if let cached = cache[index] {
            recent.removeAll { $0 == index }
            recent.append(index)
            return cached
        }
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw GIFError.unreadable }
        cache[index] = frame
        recent.append(index)
        // At most three downsampled frames, rather than a full decoded GIF in memory.
        while recent.count > 3 {
            let oldest = recent.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return frame
    }

    private enum GIFError: Error { case unreadable }
}

/// A file-free animated subject for the first real-device accessory verification.
private struct LensAttentionAnimation: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let bounce = isPlaying ? sin(time * 2.5) : 0
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                VStack(spacing: size * 0.06) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.97, green: 0.78, blue: 0.27))
                        HStack(spacing: size * 0.08) {
                            Circle().fill(.black).frame(width: size * 0.055)
                            Circle().fill(.black).frame(width: size * 0.055)
                        }
                        .offset(y: -size * 0.025)
                        Capsule()
                            .fill(.black)
                            .frame(width: size * 0.09, height: size * 0.025)
                            .offset(y: size * 0.055)
                    }
                    .frame(width: size * 0.46, height: size * 0.46)
                    .offset(y: bounce * size * 0.025)
                    Text("看看镜头")
                        .font(.system(size: max(15, size * 0.055), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
