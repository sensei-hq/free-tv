import Foundation
import Testing

@testable import FreeTVCore

let fixtureM3U = "#EXTM3U x-tvg-url=\"http://example.com/a.xml\"\r\n" +
    "#EXTINF:-1 tvg-id=\"N1.us\" tvg-logo=\"http://img/n.png\" " +
    "group-title=\"News\" tvg-country=\"US\",News One\r\n" +
    "http://cdn.example.com/n1.m3u8\r\n" +
    "#EXTINF:-1 tvg-id=\"S1\" group-title=\"Sports\",Sport, Live\n" +
    "https://cdn.example.com/s1.m3u8\n"

@Suite("M3U parsing")
struct M3UParserTests {
    @Test("parses entries with attributes")
    func parsesEntries() {
        let playlist = parseM3U(fixtureM3U)
        #expect(playlist.entries.count == 2)
        let first = playlist.entries[0]
        #expect(first.name == "News One")
        #expect(first.url == "http://cdn.example.com/n1.m3u8")
        #expect(first.tvgID == "N1.us")
        #expect(first.logo == "http://img/n.png")
        #expect(first.group == "News")
        #expect(first.country == "US")
    }

    @Test("reads guide header and comma names")
    func headerAndNames() {
        let playlist = parseM3U(fixtureM3U)
        #expect(playlist.epgURLs == ["http://example.com/a.xml"])
        #expect(playlist.entries[1].name == "Sport, Live")
    }

    @Test("converts to channels and merges duplicates")
    func convertsAndMerges() {
        let playlist = parseM3U(fixtureM3U)
        let channels = playlist.entries.map { $0.toChannel(source: "test") }
        #expect(channels[0].category == "News")
        #expect(channels[0].sources == ["test"])
        let dup = M3UEntry(name: "News One", url: "HTTP://cdn.example.com/n1.m3u8",
                           tvgID: "", logo: "http://img/n2.png", group: "",
                           country: "").toChannel(source: "other")
        let merged = mergeChannels([channels[0], dup])
        #expect(merged.count == 1)
        #expect(merged[0].logo == "http://img/n.png")
        #expect(merged[0].sources.sorted() == ["other", "test"])
    }
}
