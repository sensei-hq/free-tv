import SwiftUI
import FreeTVCore

/// Test hooks: `-tab <name>` starts on a tab, `-resetData` wipes
/// saved sources, favorites, and Plex state (keychain included).
enum LaunchTestHooks {
    static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-tab"),
              args.indices.contains(flag + 1) else { return 0 }
        return ["home", "movies", "shows", "channels", "search",
                "settings"]
            .firstIndex(of: args[flag + 1]) ?? 0
    }

    static var resetData: Bool {
        ProcessInfo.processInfo.arguments.contains("-resetData")
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: CatalogStore
    @State private var tab = LaunchTestHooks.initialTab
    @State private var visited: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            PillBar(selection: $tab)
            ZStack {
                if visited.contains(0) { tabPage(0) { HomeContentView() } }
                if visited.contains(1) {
                    tabPage(1) { MoviesView(media: .movie) }
                }
                if visited.contains(2) {
                    tabPage(2) { MoviesView(media: .show) }
                }
                if visited.contains(3) { tabPage(3) { EPGGridView() } }
                if visited.contains(4) {
                    SearchView()
                        .navigationDestination(for: Channel.self) { channel in
                            ChannelDetailView(channel: channel)
                        }
                        .navigationDestination(for: TMDBTitle.self) { title in
                            TitleDetailView(title: title)
                        }
                        .navigationDestination(for: PlexItem.self) { item in
                            PlexDetailView(item: item)
                        }
                }
                if visited.contains(5) { tabPage(5) { SettingsView() } }
            }
            .onAppear { visited.insert(tab) }
            .onChange(of: tab) { _, next in visited.insert(next) }
        }
    }

    /// All tabs stay mounted (state preserved); only the selected one
    /// is visible and focusable.
    private func tabPage<Content: View>(_ tag: Int,
                                       @ViewBuilder content: () -> Content)
        -> some View {
        NavigationStack {
            content()
        }
        .opacity(tab == tag ? 1 : 0)
        .disabled(tab != tag)
        .accessibilityHidden(tab != tag)
    }
}

/// Mock-matching pill bar: four tabs plus search and settings icons.
struct PillBar: View {
    @Binding var selection: Int

    private let tabs = [(0, "Home"), (1, "Movies"), (2, "Shows"),
                        (3, "Channels")]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(tabs, id: \.0) { tag, label in
                Button(label) { selection = tag }
                    .font(.system(size: 26, weight: .medium))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(selection == tag
                        ? Color.white.opacity(0.18) : Color.clear)
                    .foregroundStyle(selection == tag ? .white : .gray)
                    .clipShape(Capsule())
            }
            Button {
                selection = 4
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26))
                    .frame(width: 60, height: 60)
                    .background(selection == 4
                        ? Color.white.opacity(0.18) : Color.clear)
                    .foregroundStyle(selection == 4 ? .white : .gray)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Search")
            Button {
                selection = 5
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 26))
                    .frame(width: 60, height: 60)
                    .background(selection == 5
                        ? Color.white.opacity(0.18) : Color.clear)
                    .foregroundStyle(selection == 5 ? .white : .gray)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 40)
    }
}

/// Home tab: hero, continue watching, then category shelves.
struct HomeContentView: View {
    @EnvironmentObject private var store: CatalogStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var tmdb: TMDBStore
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var playing: WatchProgress?

    private var favoriteChannels: [Channel] {
        store.channels.filter { favorites.isFavorite($0) }
    }

    var body: some View {
        ScrollView {
            if store.shelves.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading channels…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVStack(alignment: .leading, spacing: 40) {
                    if hero != nil || !playback.items.isEmpty {
                        HeroView(hero: hero, onPlay: play)
                    }
                    if !playback.items.isEmpty {
                        ContinueRow(items: playback.items, onPlay: play)
                    }
                    if !favoriteChannels.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Favorites")
                                .font(.title2)
                                .bold()
                                .padding(.horizontal, 60)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 24) {
                                    ForEach(favoriteChannels) { channel in
                                        NavigationLink(value: channel) {
                                            ChannelCard(channel: channel)
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.horizontal, 60)
                            }
                        }
                    }
                    ForEach(store.shelves, id: \.title) { shelf in
                        ShelfRow(shelf: shelf)
                    }
                }
                .padding(.vertical, 40)
            }
        }
        .navigationDestination(for: Channel.self) { channel in
            ChannelDetailView(channel: channel)
        }
        .navigationDestination(for: TMDBTitle.self) { title in
            TitleDetailView(title: title)
        }
        .navigationDestination(for: PlexItem.self) { item in
            PlexDetailView(item: item)
        }

        .fullScreenCover(item: $playing) { item in
            PlayerView(title: item.title, url: item.url,
                       resumeFrom: item.resumeFrom,
                       onProgress: { position, duration in
                           playback.record(WatchProgress(
                               id: item.id, title: item.title, kind: item.kind,
                               url: item.url, tmdbID: item.tmdbID,
                               artwork: item.artwork, position: position,
                               duration: duration, updatedAt: Date()))
                       },
                       onFinished: { playback.clear(id: item.id) })
        }
    }

    private var hero: HeroModel? {
        if let top = playback.items.first {
            return HeroModel(progress: top)
        }
        if let trending = tmdb.trendingMovies.first {
            return HeroModel(trending: trending)
        }
        return nil
    }

    private func play(_ progress: WatchProgress) {
        playback.record(WatchProgress(
            id: progress.id, title: progress.title, kind: progress.kind,
            url: progress.url, tmdbID: progress.tmdbID,
            artwork: progress.artwork, position: progress.position,
            duration: progress.duration, updatedAt: Date()))
        playing = progress
    }
}

struct HeroModel {
    let badge: String
    let title: String
    let meta: String
    let artURL: URL?
    let playLabel: String?
    let progress: WatchProgress?
    let trending: TMDBTitle?
    let channel: Channel?

    init(progress: WatchProgress) {
        badge = progress.kind == .live ? "Live TV" : "On your Plex"
        title = progress.title
        meta = progress.remainingText
        artURL = progress.artwork
        playLabel = progress.kind == .live ? "Watch" : "Resume"
        self.progress = progress
        trending = nil
        channel = nil
    }

    init(trending: TMDBTitle) {
        badge = "Trending"
        title = trending.name
        var parts = [trending.mediaType == .movie ? "Movie" : "TV"]
        if !trending.year.isEmpty { parts.append(trending.year) }
        meta = parts.joined(separator: " • ")
        artURL = trending.backdropURL ?? trending.posterURL
        playLabel = nil
        progress = nil
        self.trending = trending
        channel = nil
    }
}

struct HeroView: View {
    let hero: HeroModel?
    var onPlay: (WatchProgress) -> Void
    @EnvironmentObject private var store: CatalogStore

    var body: some View {
        if let hero {
            HStack(spacing: 60) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(hero.badge)
                        .font(.caption).bold()
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(hero.title).font(.system(size: 64)).bold()
                        .lineLimit(2)
                    Text(hero.meta).font(.title3)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        if let progress = hero.progress,
                           progress.url != nil {
                            Button(hero.playLabel ?? "Play") {
                                onPlay(progress)
                            }
                        }
                        if let progress = hero.progress,
                           let channel = store.channels.first(where: {
                               $0.url == progress.id
                           }) {
                            NavigationLink("Details", value: channel)
                        } else if let trending = hero.trending {
                            NavigationLink("Details", value: trending)
                        } else if let progress = hero.progress,
                                  progress.kind == .vod,
                                  let url = progress.url {
                            NavigationLink("Details", value: PlexItem(
                                key: progress.id, title: progress.title,
                                thumbURL: progress.artwork, durationMS: nil,
                                playURL: url))
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 820)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.08))
                    if let art = hero.artURL {
                        AsyncImage(url: art) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            }
                        }
                    }
                }
                .frame(width: 640, height: 360)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .padding(.horizontal, 60)
        }
    }
}

struct ContinueRow: View {
    let items: [WatchProgress]
    var onPlay: (WatchProgress) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue watching")
                .font(.title2)
                .bold()
                .padding(.horizontal, 60)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(items) { item in
                        Button {
                            onPlay(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomLeading) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.08))
                                        if let art = item.artwork {
                                            AsyncImage(url: art) { phase in
                                                if case .success(let image) =
                                                    phase {
                                                    image.resizable()
                                                        .scaledToFit()
                                                        .padding(16)
                                                }
                                            }
                                        }
                                    }
                                    .frame(width: 320, height: 180)
                                    if item.kind == .vod {
                                        ProgressView(
                                            value: item.fraction)
                                            .progressViewStyle(
                                                LinearProgressViewStyle())
                                            .padding(.horizontal, 16)
                                            .padding(.bottom, 12)
                                    }
                                }
                                .frame(width: 320, height: 180)
                                Text(item.title).font(.headline).lineLimit(1)
                                    .frame(width: 320, alignment: .leading)
                                Text(item.remainingText).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60)
            }
        }
    }
}

struct ShelfRow: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2)
                .bold()
                .padding(.horizontal, 60)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(shelf.channels) { channel in
                        NavigationLink(value: channel) {
                            ChannelCard(channel: channel)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60)
            }
        }
    }
}
