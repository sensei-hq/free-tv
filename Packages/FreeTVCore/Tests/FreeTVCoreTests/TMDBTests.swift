import Foundation
import Testing

@testable import FreeTVCore

let tmdbSearchFixture = """
{"page":1,"total_results":2,"results":[
  {"id":27205,"media_type":"movie","title":"Inception",
   "release_date":"2010-07-16","poster_path":"/p.jpg",
   "overview":"A thief.","genre_ids":[28,878],"vote_average":8.4},
  {"id":1396,"media_type":"tv","name":"Breaking Bad",
   "first_air_date":"2008-01-20","poster_path":null,
   "overview":"A teacher.","genre_ids":[18],"vote_average":9.5}]}
"""

let tmdbProvidersFixture = """
{"id":27205,"results":{
  "US":{"link":"https://www.justwatch.com/us/movie/x",
    "free":[{"provider_id":73,"provider_name":"Tubi",
      "logo_path":"/tubi.jpg","display_priority":1}],
    "flatrate":[{"provider_id":8,"provider_name":"Netflix",
      "logo_path":"/nf.jpg","display_priority":0}]},
  "IN":{"link":"https://www.justwatch.com/in/movie/x",
    "flatrate":[{"provider_id":385,"provider_name":"YuppTV",
      "logo_path":"/yupp.jpg","display_priority":5}]}}}
"""

let tmdbGenresFixture = """
{"genres":[{"id":28,"name":"Action"},{"id":18,"name":"Drama"}]}
"""

let plexSearchFixture = """
{"MediaContainer":{"size":1,"Metadata":[
  {"ratingKey":"7","key":"/library/metadata/7","title":"Inception",
   "thumb":"/library/metadata/7/thumb/1","duration":8880000,
   "Media":[{"container":"mp4","Part":[
     {"key":"/library/parts/9/f.mp4","container":"mp4"}]}]}]}}
"""

@Suite("TMDB client", .serialized)
struct TMDBTests {
    @Test("searches titles across movies and TV")
    func search() async throws {
        MockURLProtocol.route("search/multi", body: tmdbSearchFixture)
        let client = TMDBClient(apiKey: "k", session: mockSession())
        let titles = try await client.search(query: "incept", region: "US")
        #expect(titles.count == 2)
        #expect(titles[0].name == "Inception")
        #expect(titles[0].mediaType == .movie)
        #expect(titles[0].year == "2010")
        #expect(titles[1].mediaType == .show)
        #expect(titles[0].posterURL?.absoluteString.contains("/p.jpg") == true)
    }

    @Test("discovers by year and genre")
    func discover() async throws {
        MockURLProtocol.route("discover/movie", body: tmdbSearchFixture)
        let client = TMDBClient(apiKey: "k", session: mockSession())
        let titles = try await client.discover(media: .movie, year: "2010",
                                               genreID: 28, region: "US")
        #expect(titles.count == 2)
        let seen = MockURLProtocol.requests(matching: "discover/movie").last
        #expect(seen?.url?.absoluteString.contains("primary_release_year=2010")
            == true)
        #expect(seen?.url?.absoluteString.contains("with_genres=28") == true)
    }

    @Test("fetches providers per region")
    func providers() async throws {
        MockURLProtocol.route("watch/providers",
                              body: tmdbProvidersFixture)
        let client = TMDBClient(apiKey: "k", session: mockSession())
        let groups = try await client.providers(media: .movie, id: 27205,
                                                region: "US")
        #expect(groups.flat().map(\.name).sorted() == ["Netflix", "Tubi"])
        #expect(groups.free.map(\.name) == ["Tubi"])
        let india = try await client.providers(media: .movie, id: 27205,
                                               region: "IN")
        #expect(india.flatrate.map(\.name) == ["YuppTV"])
    }

    @Test("fetches genre names")
    func genres() async throws {
        MockURLProtocol.route("genre/movie/list", body: tmdbGenresFixture)
        let client = TMDBClient(apiKey: "k", session: mockSession())
        let genres = try await client.genres(media: .movie)
        #expect(genres[28] == "Action")
    }

    @Test("trending uses the same title shape")
    func trending() async throws {
        MockURLProtocol.route("trending/movie/week",
                              body: tmdbSearchFixture)
        let client = TMDBClient(apiKey: "k", session: mockSession())
        let titles = try await client.trending(media: .movie)
        #expect(titles.count == 2)
    }
}

@Suite("Plex title search", .serialized)
struct PlexSearchTests {
    @Test("finds owned titles by name")
    func searchTitles() async throws {
        MockURLProtocol.route("library/search", body: plexSearchFixture)
        let client = PlexClient(session: mockSession())
        let base = URL(string: "http://10.0.0.252:32400")!
        let items = try await client.searchTitles(server: base, query: "Incep",
                                                  token: "t")
        #expect(items.count == 1)
        #expect(items[0].title == "Inception")
        #expect(items[0].playURL != nil)
    }
}
