import Foundation
import Testing

@testable import FreeTVCore

private func channel(_ name: String) -> Channel {
    Channel(name: name, url: "http://x/\(name)", logo: nil, tvgID: nil,
            category: "News", country: nil, sources: [], status: "online",
            quarantined: false)
}

private func title(_ name: String, media: TMDBMedia) -> TMDBTitle {
    TMDBTitle(id: name.hashValue, mediaType: media, name: name, year: "2020",
              posterPath: nil, backdropPath: nil, overview: "",
              genreIDs: [], rating: 0)
}

@Suite("Unified search scopes")
struct UnifiedSearchTests {
    let channels = [channel("Sky News"), channel("Sport Zone")]
    let titles = [title("Skyfall", media: .movie),
                  title("Sky Castle", media: .show)]

    @Test("all scope keeps everything matching")
    func allScope() {
        let results = applyScope(.all, channels: channels, titles: titles)
        #expect(results.channels.count == 2)
        #expect(results.titles.count == 2)
    }

    @Test("media scopes split movies, shows, channels")
    func mediaScopes() {
        let movies = applyScope(.movies, channels: channels, titles: titles)
        #expect(movies.channels.isEmpty)
        #expect(movies.titles.map(\.name) == ["Skyfall"])
        let shows = applyScope(.shows, channels: channels, titles: titles)
        #expect(shows.titles.map(\.name) == ["Sky Castle"])
        let live = applyScope(.channels, channels: channels, titles: titles)
        #expect(live.channels.count == 2)
        #expect(live.titles.isEmpty)
    }

    @Test("query filters each kind by name")
    func queryFilters() {
        let results = unifiedSearch(query: "sky", channels: channels,
                                    titles: titles)
        #expect(results.channels.map(\.name) == ["Sky News"])
        #expect(results.titles.map(\.name).sorted() == ["Sky Castle",
                                                        "Skyfall"])
        #expect(unifiedSearch(query: "zzz", channels: channels,
                              titles: titles).channels.isEmpty)
    }
}
