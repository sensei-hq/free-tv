import Foundation
import Testing

@testable import FreeTVCore

let fixtureCatalog = """
{
  "generated_at": "2026-11-26T10:00:00+00:00",
  "epg_urls": ["http://example.com/g.xml"],
  "stats": {"total": 3, "online": 2, "quarantined": 1},
  "channels": [
    {"name": "News One", "url": "http://cdn.example.com/n1.m3u8",
     "logo": "http://img/n.png", "tvg_id": "N1.us", "category": "News",
     "country": "US", "sources": ["news"], "status": "online",
     "quarantined": false},
    {"name": "Sport One", "url": "http://cdn.example.com/s1.m3u8",
     "logo": "", "tvg_id": "S1", "category": "Sports",
     "country": "", "sources": ["sports"], "status": "online",
     "quarantined": false},
    {"name": "Dead One", "url": "http://cdn.example.com/d1.m3u8",
     "logo": "", "tvg_id": "", "category": "News",
     "country": "", "sources": ["news"], "status": "error",
     "quarantined": true}
  ]
}
"""

@Suite("Catalog decoding")
struct CatalogDecodingTests {
    @Test("decodes channels with facets")
    func decodesChannels() throws {
        let catalog = try Catalog.decode(from: Data(fixtureCatalog.utf8))
        #expect(catalog.channels.count == 3)
        let first = catalog.channels[0]
        #expect(first.name == "News One")
        #expect(first.category == "News")
        #expect(first.country == "US")
        #expect(first.tvgID == "N1.us")
        #expect(first.sources == ["news"])
        #expect(first.quarantined == false)
    }

    @Test("empty logo string means no logo URL")
    func emptyLogoMeansNil() throws {
        let catalog = try Catalog.decode(from: Data(fixtureCatalog.utf8))
        #expect(catalog.channels[0].logoURL != nil)
        #expect(catalog.channels[1].logoURL == nil)
    }

    @Test("stream URL parses")
    func streamURLParses() throws {
        let catalog = try Catalog.decode(from: Data(fixtureCatalog.utf8))
        #expect(catalog.channels[0].streamURL?.scheme == "http")
    }

    @Test("live channels exclude quarantined")
    func liveExcludesQuarantined() throws {
        let catalog = try Catalog.decode(from: Data(fixtureCatalog.utf8))
        #expect(catalog.liveChannels.count == 2)
        #expect(catalog.liveChannels.allSatisfy { !$0.quarantined })
    }
}

@Suite("Shelves")
struct ShelfTests {
    @Test("groups by category in first-appearance order")
    func groupsByCategory() throws {
        let catalog = try Catalog.decode(from: Data(fixtureCatalog.utf8))
        let shelves = makeShelves(from: catalog.liveChannels)
        #expect(shelves.map(\.title) == ["News", "Sports"])
        #expect(shelves[0].channels.map(\.name) == ["News One"])
    }

    @Test("search matches names case-insensitively")
    func searchMatchesNames() throws {
        let catalog = try Catalog.decode(from: Data(fixtureCatalog.utf8))
        let hits = search(channels: catalog.liveChannels, query: "sport")
        #expect(hits.map(\.name) == ["Sport One"])
    }
}

@Suite("Catalog store")
struct CatalogStoreTests {
    @Test("loads from a local file URL")
    func loadsFromFile() async throws {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("catalog-test.json")
        try Data(fixtureCatalog.utf8).write(to: file)
        let store = await CatalogStore(sourceURL: file)
        try await store.refresh()
        let channels = await store.channels
        #expect(channels.count == 3)
    }
}
