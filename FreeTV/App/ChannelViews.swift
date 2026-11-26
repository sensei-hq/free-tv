import SwiftUI
import FreeTVCore

/// Small card used in shelves and grids.
struct ChannelCard: View {
    let channel: Channel

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                if let logoURL = channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().padding(16)
                        default:
                            ChannelMonogram(name: channel.name)
                        }
                    }
                } else {
                    ChannelMonogram(name: channel.name)
                }
            }
            .frame(width: 220, height: 124)
            Text(channel.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 220)
        }
    }
}

struct ChannelMonogram: View {
    let name: String

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: 48, weight: .bold))
            .foregroundStyle(.secondary)
    }
}

/// Full detail screen with Play and Favorite actions.
struct ChannelDetailView: View {
    let channel: Channel
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var playing = false

    var body: some View {
        HStack(spacing: 60) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                if let logoURL = channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit().padding(32)
                        } else {
                            ChannelMonogram(name: channel.name)
                        }
                    }
                } else {
                    ChannelMonogram(name: channel.name)
                }
            }
            .frame(width: 420, height: 236)

            VStack(alignment: .leading, spacing: 16) {
                Text(channel.name)
                    .font(.largeTitle)
                    .bold()
                Text(detailLine)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    Button("Play") { playing = true }
                    Button(favorites.isFavorite(channel)
                        ? "★ Favorited" : "♡ Favorite") {
                        favorites.toggle(channel)
                    }
                }
                .padding(.top, 12)
            }
            Spacer()
        }
        .padding(60)
        .fullScreenCover(isPresented: $playing) {
            PlayerView(channel: channel)
        }
    }

    private var detailLine: String {
        var parts = [channel.category]
        if let country = channel.country, !country.isEmpty {
            parts.append(country)
        }
        parts.append("\(channel.sources.count) source"
            + (channel.sources.count == 1 ? "" : "s"))
        return parts.joined(separator: " • ")
    }
}

/// Adaptive grid shared by search results and favorites.
struct ChannelGrid: View {
    let channels: [Channel]
    let emptyText: String

    var body: some View {
        if channels.isEmpty {
            Text(emptyText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220),
                                      spacing: 24)],
                    spacing: 32
                ) {
                    ForEach(channels) { channel in
                        NavigationLink(value: channel) {
                            ChannelCard(channel: channel)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
        }
    }
}
