import SwiftUI
import FreeTVCore

/// One search across live channels, TMDB titles, and Plex items.
struct SearchView: View {
    @EnvironmentObject private var store: CatalogStore
    @EnvironmentObject private var tmdb: TMDBStore
    @EnvironmentObject private var plex: PlexStore
    @State private var query = ""
    @State private var scope: SearchScope = .all
    @State private var tmdbTitles: [TMDBTitle] = []
    @State private var plexHits: [PlexItem] = []
    @State private var focusTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    private var scoped: UnifiedResults {
        let channels = search(channels: store.channels, query: query)
        var results = applyScope(scope, channels: channels,
                                 titles: tmdbTitles)
        if scope == .all {
            results = UnifiedResults(channels: results.channels,
                                     titles: results.titles,
                                     plexItems: plexHits)
        }
        return results
    }

    private var resultCount: Int {
        scoped.channels.count + scoped.titles.count + scoped.plexItems.count
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Movies, shows, channels", text: $query)
                .focused($fieldFocused)
                .frame(maxWidth: 900)
                .padding(.top, 32)
                .onChange(of: query) { _, new in runSearch(query: new) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SearchScope.allCases, id: \.self) { item in
                        Button(item.rawValue) { scope = item }
                            .buttonStyle(.card)
                            .opacity(scope == item ? 1.0 : 0.6)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 16)
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("\(resultCount) results for “\(query)”")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        if !scoped.channels.isEmpty {
                            resultShelf(title: "Live channels") {
                                ForEach(scoped.channels) { channel in
                                    NavigationLink(value: channel) {
                                        ChannelCard(channel: channel)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                        }
                        if !scoped.titles.isEmpty {
                            resultShelf(title: "Movies & shows") {
                                ForEach(scoped.titles, id: \.id) { title in
                                    NavigationLink(value: title) {
                                        TitleCardSmall(title: title)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                        }
                        if !scoped.plexItems.isEmpty {
                            resultShelf(title: "On your Plex") {
                                ForEach(scoped.plexItems, id: \.title) { item in
                                    NavigationLink(value: item) {
                                        PlexCardSmall(item: item)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Type to search \(store.channels.count) channels" +
                    (tmdb.hasKey ? ", movies and shows" : ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }

        .onAppear {
            focusTask?.cancel()
            focusTask = Task {
                for _ in 0 ..< 4 {
                    if Task.isCancelled { return }
                    fieldFocused = false
                    try? await Task.sleep(for: .seconds(0.3))
                    if Task.isCancelled { return }
                    fieldFocused = true
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        .onDisappear { focusTask?.cancel() }
    }

    private func runSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            tmdbTitles = []
            plexHits = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            async let titles = fetchTitles(trimmed)
            async let plexHits = fetchPlex(trimmed)
            tmdbTitles = await titles
            self.plexHits = await plexHits
        }
    }

    private func fetchTitles(_ query: String) async -> [TMDBTitle] {
        guard tmdb.hasKey, let client = tmdb.client else { return [] }
        return (try? await client.search(query: query,
                                          region: tmdb.region)) ?? []
    }

    private func fetchPlex(_ query: String) async -> [PlexItem] {
        guard plex.isSignedIn, let server = plex.serverURL,
              let token = plex.serverToken else { return [] }
        return (try? await plex.client.searchTitles(
            server: server, query: query, token: token)) ?? []
    }

    private func resultShelf<Content: View>(title: String,
                                           @ViewBuilder rows: () -> Content)
        -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    rows()
                }
            }
        }
    }
}

/// Compact title tile for search rows.
struct TitleCardSmall: View {
    let title: TMDBTitle

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                if let poster = title.posterURL {
                    AsyncImage(url: poster) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        }
                    }
                }
            }
            .frame(width: 160, height: 240)
            Text(title.name).font(.caption).lineLimit(1).frame(width: 160)
        }
    }
}

struct PlexCardSmall: View {
    let item: PlexItem

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                if let thumb = item.thumbURL {
                    AsyncImage(url: thumb) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit().padding(8)
                        }
                    }
                }
            }
            .frame(width: 220, height: 124)
            Text(item.title).font(.caption).lineLimit(1).frame(width: 220)
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var store: CatalogStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        ChannelGrid(
            channels: store.channels.filter { favorites.isFavorite($0) },
            emptyText: "No favorites yet — open a channel and ♡ it"
        )

    }
}
