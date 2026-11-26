import AVKit
import SwiftUI
import FreeTVCore

/// Full-screen player. AVPlayer handles HLS; anything else shows an error.
struct PlayerView: View {
    let title: String
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    init(channel: Channel) {
        title = channel.name
        url = channel.streamURL
    }

    init(title: String, url: URL?) {
        self.title = title
        self.url = url
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
        newPlayer.play()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            if newPlayer.status == .failed
                || newPlayer.currentItem?.status == .failed {
                failed = true
            }
        }
    }

    private func stop() {
        player?.pause()
        player = nil
    }
}
