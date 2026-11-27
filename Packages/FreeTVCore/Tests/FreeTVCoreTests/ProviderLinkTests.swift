import Foundation
import Testing

@testable import FreeTVCore

@Suite("Provider app links")
struct ProviderLinkTests {
    @Test("maps known providers to launch URLs, schemes first")
    func mapsKnown() {
        let netflix = ProviderLink.links(for: 8)
        #expect(netflix?.candidates.first?.scheme == "nflx")
        #expect(netflix?.candidates.last?.host == "www.netflix.com")
        #expect(ProviderLink.links(for: 73)?.candidates.last?.absoluteString
            == "https://tubitv.com")
        #expect(ProviderLink.links(for: 192)?.candidates.first?.scheme
            == "youtube")
        #expect(ProviderLink.links(for: 538)?.candidates.first?.scheme
            == "plex")
    }

    @Test("unknown providers have no launch URLs")
    func unknownHasNone() {
        #expect(ProviderLink.links(for: 999999) == nil)
        #expect(ProviderLink.links(for: 350) == nil)
    }

    @Test("cost order puts owned and free first")
    func costOrder() {
        #expect(WatchCost.owned.rank == 0)
        #expect(WatchCost.free.rank < WatchCost.subscription.rank)
        #expect(WatchCost.subscription.rank < WatchCost.rent.rank)
        #expect(WatchCost.rent.rank < WatchCost.buy.rank)
    }
}
