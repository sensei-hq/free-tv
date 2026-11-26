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
            .navigationTitle("Movies")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Search titles", text: $query)
                        .focused($fieldFocused)
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
                    HStack(spacing: 16) {
                        TextField("Year", text: $year)
                            .frame(maxWidth: 140)
                        Button("Search") {
                            Task { await tmdb.search(query: query) }
                        }
                        Button("Browse") {
                            Task { await tmdb.browse(year: year,
                                                     genreID: genreID) }
                        }
                    }
                    .padding(.horizontal, 60)
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
            .navigationTitle("Movies")
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

    private func genreChip(id: Int?, name: String) -> some View {
        Button(name) { genreID = id }
            .buttonStyle(.card)
            .opacity(genreID == id ? 1.0 : 0.6)
    }

    private func titleShelf(title: String, titles: [TMDBTitle]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold().padding(.horizontal, 60)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)],
                  spacing: 32) {
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
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                if let poster = title.posterURL {
                    AsyncImage(url: poster) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        } else {
                            Text(title.name.prefix(1))
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 160, height: 240)
            Text(title.name).font(.caption).lineLimit(1).frame(width: 160)
            Text(yearLine).font(.caption2).foregroundStyle(.secondary)
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
    @State private var playing = false

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 60) {
                AsyncImage(url: title.posterURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    }
                }
                .frame(width: 300, height: 450)
                VStack(alignment: .leading, spacing: 16) {
                    Text(title.name).font(.largeTitle).bold()
                    Text(title.overview).font(.body)
                        .foregroundStyle(.secondary)
                    if let match = plexMatch, match.playURL != nil {
                        Button("Play on your Plex") { playing = true }
                    }
                    providerSection(name: "Stream free",
                                    providers: providers?.free ?? [])
                    providerSection(name: "Stream",
                                    providers: providers?.flatrate ?? [])
                    providerSection(name: "Rent or buy",
                                    providers: (providers?.rent ?? [])
                                        + (providers?.buy ?? []))
                }
                Spacer()
            }
            .padding(60)
        }
        .navigationTitle(title.name)
        .task {
            providers = await tmdb.providers(for: title)
            await matchPlex()
        }
        .fullScreenCover(isPresented: $playing) {
            PlayerView(title: title.name, url: plexMatch?.playURL)
        }
    }

    private func providerSection(name: String,
                                 providers: [TMDBProvider]) -> some View {
        Group {
            if !providers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.headline)
                    ForEach(providers, id: \.id) { provider in
                        HStack(spacing: 12) {
                            AsyncImage(url: provider.logoURL) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFit()
                                }
                            }
                            .frame(width: 48, height: 48)
                            Text(provider.name)
                        }
                    }
                }
            }
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
    }
}
