import AVKit
import SwiftUI
import FreeTVCore

/// Full-screen player. AVPlayer handles HLS; anything else shows an error.
struct PlayerView: View {
    let channel: Channel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if failed {
                VStack(spacing: 16) {
                    Text("This stream needs a different player")
                        .font(.title2)
                    Text(channel.name)
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
        guard let streamURL = channel.streamURL else {
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
