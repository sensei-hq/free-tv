import Foundation
import Testing

@testable import FreeTVCore

private func testDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "FreeTVCoreTests")!
    defaults.removeObject(forKey: "free-tv-sources")
    return defaults
}

@Suite("Source store")
struct SourceStoreTests {
    @Test("seeds the default catalog on first launch")
    @MainActor
    func seedsDefault() {
        let store = SourceStore(defaults: testDefaults())
        #expect(store.sources.count == 1)
        #expect(store.sources[0].kind == .catalog)
    }

    @Test("detects kind from URL")
    func detectsKind() {
        #expect(Source.detectKind(url: URL(string: "http://x/c.json")!) == .catalog)
        #expect(Source.detectKind(url: URL(string: "http://x/p.m3u")!) == .m3u)
        #expect(Source.detectKind(url: URL(string: "http://x/p.m3u8")!) == .m3u)
    }

    @Test("adds, toggles, removes, persists")
    @MainActor
    func crud() {
        let defaults = testDefaults()
        let store = SourceStore(defaults: defaults)
        store.add(name: "Sports", url: URL(string: "http://x/s.m3u")!)
        #expect(store.sources.count == 2)
        let added = store.sources[1]
        #expect(added.kind == .m3u)
        store.toggle(added)
        #expect(store.sources[1].isEnabled == false)
        let reloaded = SourceStore(defaults: defaults)
        #expect(reloaded.sources.count == 2)
        store.remove(added)
        #expect(store.sources.count == 1)
    }
}
