import SwiftUI
import FreeTVCore

/// Personal Plex libraries, browsed inside the app.
struct PlexView: View {
    @EnvironmentObject private var plex: PlexStore

    var body: some View {
        List(plex.sections, id: \.key) { section in
            NavigationLink(value: section) {
                HStack {
                    Text(section.title).font(.headline)
                    Spacer()
                    Text(section.type).font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        .navigationDestination(for: LibrarySection.self) { section in
            PlexSectionView(section: section)
        }
        .onAppear { plex.refreshSections() }
    }
}

struct PlexSectionView: View {
    let section: LibrarySection
    @EnvironmentObject private var plex: PlexStore
    @State private var items: [PlexItem] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220),
                                        spacing: 24)],
                      spacing: 32) {
                ForEach(items, id: \.title) { item in
                    NavigationLink(value: item) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                                if let thumb = item.thumbURL {
                                    AsyncImage(url: thumb) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFit()
                                                .padding(8)
                                        }
                                    }
                                }
                            }
                            .frame(width: 220, height: 124)
                            Text(item.title).font(.caption).lineLimit(1)
                                .frame(width: 220)
                        }
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }

        .navigationDestination(for: PlexItem.self) { item in
            PlexDetailView(item: item)
        }
        .task { await load() }
    }

    private func load() async {
        guard let server = plex.serverURL,
              let token = plex.serverToken else { return }
        items = (try? await plex.client.items(
            server: server, sectionKey: section.key, token: token)) ?? []
    }
}

struct PlexDetailView: View {
    let item: PlexItem
    @EnvironmentObject private var playback: PlaybackStore
    @State private var playing = false

    private var progressID: String {
        item.key ?? item.title
    }

    var body: some View {
        HStack(spacing: 60) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                if let thumb = item.thumbURL {
                    AsyncImage(url: thumb) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit().padding(32)
                        }
                    }
                }
            }
            .frame(width: 420, height: 236)
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title).font(.largeTitle).bold()
                if item.playURL != nil {
                    Button(playbackButtonLabel) { playing = true }
                } else {
                    Text("No direct-play file for this item")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(60)
        .fullScreenCover(isPresented: $playing) {
            PlayerView(title: item.title, url: item.playURL,
                       resumeFrom: playback.progress(id: progressID)?
                           .resumeFrom,
                       onProgress: { position, duration in
                           playback.record(WatchProgress(
                               id: progressID, title: item.title, kind: .vod,
                               url: item.playURL, tmdbID: nil,
                               artwork: item.thumbURL, position: position,
                               duration: duration, updatedAt: Date()))
                       },
                       onFinished: { playback.clear(id: progressID) })
        }
    }

    private var playbackButtonLabel: String {
        playback.progress(id: progressID)?.resumeFrom != nil
            ? "Resume" : "Play"
    }
}
