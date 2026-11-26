import Foundation
import Testing

@testable import FreeTVCore

private let catalogFixture = """
{"generated_at":"t","epg_urls":[],"stats":null,"channels":[
  {"name":"News One","url":"http://cdn.example.com/n1.m3u8","logo":null,
   "tvg_id":"N1","category":"News","country":null,"sources":["c"],
   "status":"online","quarantined":false}]}
"""

private let m3uFixture = """
#EXTM3U
#EXTINF:-1 tvg-id="S1" group-title="Sports",Sport One
http://cdn.example.com/s1.m3u8
#EXTINF:-1 tvg-id="N1" group-title="News",News One
http://cdn.example.com/n1.m3u8
"""

@Suite("Multi-source refresh", .serialized)
struct CatalogSourcesTests {
    @Test("merges catalog and playlist sources, one failure tolerated")
    @MainActor
    func mergesSources() async throws {
        MockURLProtocol.route("x/c.json", body: catalogFixture)
        MockURLProtocol.route("x/p.m3u", body: m3uFixture)
        MockURLProtocol.route("x/dead.m3u", status: 500, body: "")
        let store = await CatalogStore(session: mockSession())
        try await store.refresh(sources: [
            Source(name: "c", kind: .catalog,
                   url: URL(string: "http://x/c.json")!),
            Source(name: "p", kind: .m3u,
                   url: URL(string: "http://x/p.m3u")!),
            Source(name: "dead", kind: .m3u,
                   url: URL(string: "http://x/dead.m3u")!),
        ])
        let channels = await store.channels
        #expect(channels.count == 2)
        let shelves = await store.shelves
        #expect(shelves.map(\.title).sorted() == ["News", "Sports"])
        let news = channels.first { $0.name == "News One" }
        #expect(news?.sources.sorted() == ["c", "p"])
    }
}
