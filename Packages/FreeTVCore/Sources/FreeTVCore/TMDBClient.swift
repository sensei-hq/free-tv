import Foundation

/// TMDB metadata plus JustWatch-powered where-to-watch data.
/// The API key is injected by the caller (Settings → keychain);
/// nothing is bundled or hardcoded.
public enum TMDBMedia: String, Sendable {
    case movie
    case show = "tv"
}

public struct TMDBTitle: Hashable, Sendable {
    public let id: Int
    public let mediaType: TMDBMedia
    public let name: String
    public let year: String
    public let posterPath: String?
    public let overview: String
    public let genreIDs: [Int]
    public let rating: Double

    public var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
}

public struct TMDBProvider: Hashable, Sendable {
    public let id: Int
    public let name: String
    public let logoPath: String?
    public let priority: Int

    public var logoURL: URL? {
        guard let logoPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(logoPath)")
    }
}

public struct TMDBProviderGroups: Sendable {
    public let free: [TMDBProvider]
    public let ads: [TMDBProvider]
    public let flatrate: [TMDBProvider]
    public let rent: [TMDBProvider]
    public let buy: [TMDBProvider]
    public let link: String?

    public func flat() -> [TMDBProvider] {
        (free + ads + flatrate).sorted { $0.priority < $1.priority }
    }
}

public enum TMDBError: Error {
    case badResponse
    case invalidKey
}

public final class TMDBClient: Sendable {
    public static let defaultRegion = "US"

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private func url(_ path: String,
                     query: [String: String] = [:]) -> URL? {
        var components = URLComponents(
            string: "https://api.themoviedb.org/3\(path)")
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        components?.queryItems = items
        return components?.url
    }

    private func get<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw TMDBError.badResponse
        }
        if http.statusCode == 401 { throw TMDBError.invalidKey }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw TMDBError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Titles

    private struct TitleResult: Decodable {
        let id: Int
        let media_type: String?
        let title: String?
        let name: String?
        let release_date: String?
        let first_air_date: String?
        let poster_path: String?
        let overview: String?
        let genre_ids: [Int]?
        let vote_average: Double?
    }

    private struct TitleList: Decodable {
        let results: [TitleResult]
    }

    private func titles(from list: TitleList,
                        defaultMedia: TMDBMedia? = nil) -> [TMDBTitle] {
        list.results.compactMap { item in
            let media: TMDBMedia
            if let raw = item.media_type, let parsed = TMDBMedia(rawValue: raw) {
                media = parsed
            } else if let fallback = defaultMedia {
                media = fallback
            } else {
                return nil
            }
            let name = media == .movie ? item.title : item.name
            let date = media == .movie ? item.release_date : item.first_air_date
            return TMDBTitle(
                id: item.id, mediaType: media,
                name: name ?? "Unknown",
                year: String((date ?? "").prefix(4)),
                posterPath: item.poster_path,
                overview: item.overview ?? "",
                genreIDs: item.genre_ids ?? [],
                rating: item.vote_average ?? 0)
        }
    }

    /// Name search across movies and TV.
    public func search(query: String, region: String = defaultRegion)
        async throws -> [TMDBTitle] {
        guard let url = url("/search/multi",
                            query: ["query": query,
                                    "include_adult": "false",
                                    "watch_region": region]) else {
            throw TMDBError.badResponse
        }
        return titles(from: try await get(TitleList.self, url: url))
    }

    /// Browse by year and/or genre (either may be nil).
    public func discover(media: TMDBMedia, year: String? = nil,
                         genreID: Int? = nil,
                         region: String = defaultRegion) async throws
        -> [TMDBTitle] {
        var query = ["include_adult": "false", "watch_region": region,
                     "sort_by": "popularity.desc"]
        if let year, !year.isEmpty {
            query[media == .movie ? "primary_release_year" : "first_air_date_year"]
                = year
        }
        if let genreID {
            query["with_genres"] = String(genreID)
        }
        guard let url = url("/discover/\(media.rawValue)", query: query) else {
            throw TMDBError.badResponse
        }
        return titles(from: try await get(TitleList.self, url: url),
                      defaultMedia: media)
    }

    /// This week's trending rows for the browse screen.
    public func trending(media: TMDBMedia) async throws -> [TMDBTitle] {
        guard let url = url("/trending/\(media.rawValue)/week") else {
            throw TMDBError.badResponse
        }
        return titles(from: try await get(TitleList.self, url: url),
                      defaultMedia: media)
    }

    private struct GenreList: Decodable {
        struct Genre: Decodable {
            let id: Int
            let name: String
        }
        let genres: [Genre]
    }

    /// Genre id → name for filter labels.
    public func genres(media: TMDBMedia) async throws -> [Int: String] {
        guard let url = url("/genre/\(media.rawValue)/list") else {
            throw TMDBError.badResponse
        }
        let list: GenreList = try await get(GenreList.self, url: url)
        return Dictionary(uniqueKeysWithValues:
            list.genres.map { ($0.id, $0.name) })
    }

    // MARK: - Where to watch

    private struct ProviderEntry: Decodable {
        let provider_id: Int
        let provider_name: String
        let logo_path: String?
        let display_priority: Int?
    }

    private struct RegionProviders: Decodable {
        let link: String?
        let free: [ProviderEntry]?
        let ads: [ProviderEntry]?
        let flatrate: [ProviderEntry]?
        let rent: [ProviderEntry]?
        let buy: [ProviderEntry]?
    }

    private struct ProvidersResponse: Decodable {
        let results: [String: RegionProviders]
    }

    /// Provider groups for one region (empty when TMDB knows none).
    public func providers(media: TMDBMedia, id: Int,
                          region: String = defaultRegion) async throws
        -> TMDBProviderGroups {
        guard let url = url("/\(media.rawValue)/\(id)/watch/providers") else {
            throw TMDBError.badResponse
        }
        let response: ProvidersResponse = try await get(
            ProvidersResponse.self, url: url)
        let regionData = response.results[region]
        func map(_ entries: [ProviderEntry]?) -> [TMDBProvider] {
            (entries ?? []).map {
                TMDBProvider(id: $0.provider_id, name: $0.provider_name,
                             logoPath: $0.logo_path,
                             priority: $0.display_priority ?? 99)
            }.sorted { $0.priority < $1.priority }
        }
        return TMDBProviderGroups(
            free: map(regionData?.free), ads: map(regionData?.ads),
            flatrate: map(regionData?.flatrate), rent: map(regionData?.rent),
            buy: map(regionData?.buy), link: regionData?.link)
    }
}
