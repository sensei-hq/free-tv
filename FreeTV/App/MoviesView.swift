import SwiftUI
import FreeTVCore

/// Unified movies/shows: TMDB search, year/genre browse, trending,
/// where-to-watch providers, and Plex ownership matching.
struct MoviesView: View {
    @EnvironmentObject private var tmdb: TMDBStore
    @State private var query = ""
    @State private var year = ""
    @State private var genreID: Int?
    @State private var focusTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if !tmdb.hasKey {
            VStack(spacing: 16) {
                Text("TMDB key needed")
                    .font(.title2)
                Text("Add your free TMDB API key in Settings")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    filtersRow
                    genreRow
                    TextField("Search titles", text: $query)
                        .focused($fieldFocused)
                        .accessibilityIdentifier("TitleSearchField")
                        .frame(maxWidth: 600)
                        .padding(.horizontal, 60)
                        .onSubmit { Task { await tmdb.search(query: query) } }
                        .onChange(of: query) { _, new in
                            searchTask?.cancel()
                            let trimmed = new.trimmingCharacters(
                                in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            searchTask = Task {
                                try? await Task.sleep(for: .seconds(0.6))
                                guard !Task.isCancelled else { return }
                                await tmdb.search(query: trimmed)
                            }
                        }
                    if tmdb.isLoading {
                        ProgressView().padding(.horizontal, 60)
                    } else if !tmdb.results.isEmpty {
                        titleGrid(tmdb.results)
                    } else {
                        if !tmdb.trendingMovies.isEmpty {
                            titleShelf(title: "Trending movies",
                                       titles: tmdb.trendingMovies)
                        }
                        if !tmdb.trendingShows.isEmpty {
                            titleShelf(title: "Trending shows",
                                       titles: tmdb.trendingShows)
                        }
                    }
                    if let message = tmdb.errorMessage {
                        Text(message).foregroundStyle(.red)
                            .padding(.horizontal, 60)
                    }
                }
                .padding(.vertical, 32)
            }
            .navigationDestination(for: TMDBTitle.self) { title in
                TitleDetailView(title: title)
            }
            .task { await tmdb.loadTrending() }
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
    }

    private var filtersRow: some View {
        HStack(spacing: 16) {
            TextField("Year", text: $year)
                .frame(maxWidth: 140)
            Button("Browse") {
                Task { await tmdb.browse(year: year, genreID: genreID) }
            }
            if genreID != nil || !year.isEmpty {
                Button("Clear") {
                    genreID = nil
                    year = ""
                    Task { await tmdb.loadTrending() }
                }
            }
        }
        .padding(.horizontal, 60)
    }

    private var genreRow: some View {
        Group {
            if !tmdb.movieGenres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        genreChip(id: nil, name: "All")
                        ForEach(tmdb.movieGenres.sorted(by: {
                            $0.value < $1.value
                        }), id: \.key) { id, name in
                            genreChip(id: id, name: name)
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
        }
    }

    private func genreChip(id: Int?, name: String) -> some View {
        Button(name) { genreID = id }
            .buttonStyle(.card)
            .opacity(genreID == id ? 1.0 : 0.6)
    }

    private func titleShelf(title: String, titles: [TMDBTitle]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold().padding(.horizontal, 60)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(titles, id: \.id) { title in
                        NavigationLink(value: title) {
                            TitleCard(title: title)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60)
            }
        }
    }

    private func titleGrid(_ titles: [TMDBTitle]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(300),
                                                     spacing: 32),
                                 count: 4),
                  spacing: 40) {
            ForEach(titles, id: \.id) { title in
                NavigationLink(value: title) {
                    TitleCard(title: title)
                }
                .buttonStyle(.card)
            }
        }
        .padding(.horizontal, 60)
    }
}

struct TitleCard: View {
    let title: TMDBTitle

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                if let poster = title.posterURL {
                    AsyncImage(url: poster) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        } else {
                            Text(title.name.prefix(1))
                                .font(.system(size: 72, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 300, height: 450)
            Text(title.name).font(.headline).lineLimit(1).frame(width: 300)
            Text(yearLine).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var yearLine: String {
        var parts = [title.mediaType == .movie ? "Movie" : "TV"]
        if !title.year.isEmpty { parts.append(title.year) }
        if title.rating > 0 {
            parts.append(String(format: "★ %.1f", title.rating))
        }
        return parts.joined(separator: " • ")
    }
}

struct TitleDetailView: View {
    let title: TMDBTitle
    @EnvironmentObject private var tmdb: TMDBStore
    @EnvironmentObject private var plex: PlexStore
    @State private var providers: TMDBProviderGroups?
    @State private var plexMatch: PlexItem?
    @State private var plexLocal = true
    @State private var playing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backdrop
                VStack(alignment: .leading, spacing: 20) {
                    Text(title.name).font(.largeTitle).bold()
                    Text(title.overview).font(.body)
                        .foregroundStyle(.secondary)
                    if let match = plexMatch, match.playURL != nil {
                        Button("Play on your Plex" +
                            (plexLocal ? " (local)" : " (remote)")) {
                            playing = true
                        }
                    }
                    providerSection(cost: .free,
                                    providers: (providers?.free ?? [])
                                        + (providers?.ads ?? []))
                    providerSection(cost: .subscription,
                                    providers: providers?.flatrate ?? [])
                    providerSection(cost: .rent,
                                    providers: providers?.rent ?? [])
                    providerSection(cost: .buy,
                                    providers: providers?.buy ?? [])
                }
                .padding(60)
            }
        }

        .task {
            providers = await tmdb.providers(for: title)
            await matchPlex()
        }
        .fullScreenCover(isPresented: $playing) {
            PlayerView(title: title.name, url: plexMatch?.playURL)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = title.backdropURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                        .frame(height: 420)
                        .clipped()
                        .overlay(LinearGradient(
                            colors: [.clear, .black.opacity(0.85)],
                            startPoint: .center, endPoint: .bottom))
                }
            }
            .frame(height: 420)
        }
    }

    private func providerSection(cost: WatchCost,
                                 providers: [TMDBProvider]) -> some View {
        Group {
            if !providers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(sectionName(cost)).font(.title3).bold()
                    providerRows(cost: cost, providers: providers)
                }
            }
        }
    }

    /// Eager rows (not LazyVGrid): every card exists for focus,
    /// so remote navigation and scrolling always work.
    private func providerRows(cost: WatchCost,
                              providers: [TMDBProvider]) -> some View {
        let rows = stride(from: 0, to: providers.count, by: 4).map {
            Array(providers[$0 ..< min($0 + 4, providers.count)])
        }
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 20) {
                    ForEach(rows[index], id: \.id) { provider in
                        ProviderCard(provider: provider, cost: cost)
                    }
                }
            }
        }
    }

    private func sectionName(_ cost: WatchCost) -> String {
        switch cost {
        case .owned: return "Owned"
        case .free: return "Stream free"
        case .subscription: return "Subscription"
        case .rent: return "Rent"
        case .buy: return "Buy"
        }
    }

    private func matchPlex() async {
        guard plex.isSignedIn,
              let server = plex.serverURL,
              let token = plex.serverToken else { return }
        let items = (try? await plex.client.searchTitles(
            server: server, query: title.name, token: token)) ?? []
        plexMatch = items.first {
            $0.title.localizedCaseInsensitiveContains(title.name)
                || title.name.localizedCaseInsensitiveContains($0.title)
        } ?? items.first
        plexLocal = !(server.absoluteString.contains("plex.direct")
            || server.absoluteString.hasPrefix("https"))
    }
}

/// One provider: logo card with cost badge. Launches the provider app
/// when installed, otherwise renders disabled.
struct ProviderCard: View {
    let provider: TMDBProvider
    let cost: WatchCost
    @State private var available: Bool?

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                    if let logo = provider.logoURL {
                        AsyncImage(url: logo) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit().padding(20)
                            }
                        }
                    }
                }
                .frame(width: 200, height: 120)
                Text(cost.badge)
                    .font(.caption2).bold()
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(badgeColor)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .buttonStyle(.card)
        .disabled(available == false)
        .opacity(available == false ? 0.45 : 1.0)
        .accessibilityLabel("\(provider.name), \(cost.badge.lowercased())")
        .task { await checkAvailability() }
    }

    private var badgeColor: Color {
        switch cost {
        case .owned, .free: return .green
        case .subscription: return .blue
        case .rent: return .orange
        case .buy: return .gray
        }
    }

    private func open() {
        guard let links = ProviderLink.links(for: provider.id) else { return }
        AppLauncher.openFirst(links.candidates)
    }

    private func checkAvailability() async {
        guard let links = ProviderLink.links(for: provider.id) else {
            available = false
            return
        }
        available = links.candidates.contains {
            AppLauncher.canOpen($0)
        }
    }
}
