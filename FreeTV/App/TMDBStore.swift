import Foundation
import FreeTVCore

/// TMDB state: API key in keychain, region in prefs, search/browse.
@MainActor
final class TMDBStore: ObservableObject {
    @Published private(set) var hasKey = false
    @Published var region = "US"
    @Published private(set) var results: [TMDBMedia: [TMDBTitle]] = [:]
    @Published private(set) var trendingMovies: [TMDBTitle] = []
    @Published private(set) var trendingShows: [TMDBTitle] = []
    @Published private(set) var movieGenres: [Int: String] = [:]
    @Published private(set) var tvGenres: [Int: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private var overrideKey: String?

    var client: TMDBClient? {
        if let overrideKey {
            return TMDBClient(apiKey: overrideKey)
        }
        return keychain.load(account: "tmdb-api-key")
            .map { TMDBClient(apiKey: $0) }
    }

    init() {
        if LaunchTestHooks.resetData {
            try? keychain.delete(account: "tmdb-api-key")
            defaults.removeObject(forKey: "free-tv-region")
        }
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-tmdbKey"),
           args.indices.contains(flag + 1) {
            overrideKey = args[flag + 1]
        }
        hasKey = overrideKey != nil
            || keychain.load(account: "tmdb-api-key") != nil
        region = defaults.string(forKey: "free-tv-region") ?? "US"
    }

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? keychain.save(trimmed, account: "tmdb-api-key")
        hasKey = true
    }

    func clearKey() {
        try? keychain.delete(account: "tmdb-api-key")
        hasKey = false
        results = [:]
        trendingMovies = []
        trendingShows = []
    }

    func saveRegion(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard trimmed.count == 2 else { return }
        region = trimmed
        defaults.set(trimmed, forKey: "free-tv-region")
    }

    func search(media: TMDBMedia, query: String) async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let found = try await client.search(query: query, region: region)
            results[media] = found.filter { $0.mediaType == media }
        } catch TMDBError.invalidKey {
            errorMessage = "TMDB key rejected — check Settings"
            results[media] = []
        } catch {
            errorMessage = error.localizedDescription
            results[media] = []
        }
    }

    func browse(media: TMDBMedia, year: String, genreID: Int?) async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results[media] = try await client.discover(
                media: media, year: year.isEmpty ? nil : year,
                genreID: genreID, region: region)
        } catch {
            errorMessage = error.localizedDescription
            results[media] = []
        }
    }

    func loadTrending() async {
        guard let client, trendingMovies.isEmpty else { return }
        do {
            async let movies = client.trending(media: .movie)
            async let shows = client.trending(media: .show)
            async let movieGenreList = client.genres(media: .movie)
            async let tvGenreList = client.genres(media: .show)
            trendingMovies = try await movies
            trendingShows = try await shows
            movieGenres = try await movieGenreList
            tvGenres = try await tvGenreList
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func genres(for media: TMDBMedia) -> [Int: String] {
        media == .movie ? movieGenres : tvGenres
    }

    func providers(for title: TMDBTitle) async -> TMDBProviderGroups? {
        guard let client else { return nil }
        return try? await client.providers(
            media: title.mediaType, id: title.id, region: region)
    }
}
