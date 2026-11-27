import AVKit
import SwiftUI
import FreeTVCore

/// Full-screen player. Reports progress for continue-watching,
/// seeks to saved positions, and signals natural finishes.
struct PlayerView: View {
    typealias ProgressHandler = (Double, Double) -> Void

    let title: String
    let url: URL?
    let resumeFrom: Double?
    let onProgress: ProgressHandler?
    let onFinished: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    init(channel: Channel, resumeFrom: Double? = nil,
         onProgress: ProgressHandler? = nil, onFinished: (() -> Void)? = nil) {
        title = channel.name
        url = channel.streamURL
        self.resumeFrom = resumeFrom
        self.onProgress = onProgress
        self.onFinished = onFinished
    }

    init(title: String, url: URL?, resumeFrom: Double? = nil,
         onProgress: ProgressHandler? = nil, onFinished: (() -> Void)? = nil) {
        self.title = title
        self.url = url
        self.resumeFrom = resumeFrom
        self.onProgress = onProgress
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if failed {
                VStack(spacing: 16) {
                    Text("This stream needs a different player")
                        .font(.title2)
                    Text(title)
                        .foregroundStyle(.secondary)
                    Button("Back") { dismiss() }
                }
            } else {
                ProgressView()
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        guard let streamURL = url else {
            failed = true
            return
        }
        let item = AVPlayerItem(url: streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        if let resumeFrom, resumeFrom > 0 {
            newPlayer.seek(to: CMTime(seconds: resumeFrom,
                                      preferredTimescale: 1))
        }
        newPlayer.play()
        let report = onProgress
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
            queue: .main) { time in
                let position = time.seconds
                let duration = newPlayer.currentItem?.duration.seconds ?? 0
                guard position.isFinite, duration.isFinite else { return }
                report?(position, duration)
            }
        let finished = onFinished
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item,
            queue: .main) { _ in finished?() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            if newPlayer.status == .failed
                || newPlayer.currentItem?.status == .failed {
                failed = true
            }
        }
    }

    private func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }
}
