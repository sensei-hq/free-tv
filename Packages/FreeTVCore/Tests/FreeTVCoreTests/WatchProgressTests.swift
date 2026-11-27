import Foundation
import Testing

@testable import FreeTVCore

@Suite("Watch progress")
struct WatchProgressTests {
    @Test("fraction and remaining time")
    func fractionAndRemaining() {
        let progress = WatchProgress(id: "x", title: "Film",
                                     kind: .vod, url: nil, tmdbID: nil,
                                     position: 600, duration: 3600,
                                     updatedAt: Date())
        #expect(abs(progress.fraction - 1.0 / 6.0) < 0.001)
        #expect(progress.remainingText == "50 min left")
    }

    @Test("live items never resume-seek")
    func liveHasNoPosition() {
        let progress = WatchProgress(id: "y", title: "News",
                                     kind: .live,
                                     url: URL(string: "http://x/n")!,
                                     tmdbID: nil, position: 0, duration: 0,
                                     updatedAt: Date())
        #expect(progress.resumeFrom == nil)
        #expect(progress.fraction == 0)
    }

    @Test("finished items drop out")
    func finishedDropsOut() {
        let progress = WatchProgress(id: "x", title: "Film",
                                     kind: .vod, url: nil, tmdbID: nil,
                                     position: 3590, duration: 3600,
                                     updatedAt: Date())
        #expect(progress.isFinished == true)
    }

    @Test("store keeps recency order and caps size")
    func storeOrdersAndCaps() {
        let store = PlaybackMemoryStore(limit: 2)
        store.record(WatchProgress(id: "a", title: "A", kind: .live, url: nil,
                                   tmdbID: nil, position: 0, duration: 0,
                                   updatedAt: Date(timeIntervalSince1970: 1)))
        store.record(WatchProgress(id: "b", title: "B", kind: .live, url: nil,
                                   tmdbID: nil, position: 0, duration: 0,
                                   updatedAt: Date(timeIntervalSince1970: 2)))
        store.record(WatchProgress(id: "c", title: "C", kind: .live, url: nil,
                                   tmdbID: nil, position: 0, duration: 0,
                                   updatedAt: Date(timeIntervalSince1970: 3)))
        #expect(store.items.map(\.id) == ["c", "b"])
        store.clear(id: "c")
        #expect(store.items.map(\.id) == ["b"])
    }
}
