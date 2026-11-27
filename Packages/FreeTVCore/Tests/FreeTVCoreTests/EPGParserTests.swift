import Foundation
import Testing

@testable import FreeTVCore

let xmltvFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="bbc1">
    <display-name>BBC One</display-name>
    <icon src="http://example.com/bbc.png"/>
  </channel>
  <programme start="20260101080000 +0000" stop="20260101090000 +0000" channel="bbc1">
    <title>Morning News</title>
    <desc>Headlines and weather.</desc>
  </programme>
  <programme start="20260101090000 +0000" stop="20260101093000 +0000" channel="bbc1">
    <title>Talk Show</title>
  </programme>
</tv>
"""

@Suite("XMLTV parsing")
struct EPGParserTests {
    @Test("parses channels and programmes")
    func parsesGuide() throws {
        let guide = try parseXMLTV(Data(xmltvFixture.utf8))
        #expect(guide.channels.count == 1)
        #expect(guide.channels[0].name == "BBC One")
        #expect(guide.channels[0].icon?.absoluteString == "http://example.com/bbc.png")
        let programmes = guide.programmes["bbc1"] ?? []
        #expect(programmes.count == 2)
        #expect(programmes[0].title == "Morning News")
        #expect(programmes[0].desc == "Headlines and weather.")
        #expect(programmes[1].desc == nil)
    }

    @Test("finds now-playing and upcoming shows")
    func nowAndNext() throws {
        let guide = try parseXMLTV(Data(xmltvFixture.utf8))
        let at = Date(timeIntervalSince1970: 1767256200)
        let now = nowPlaying(channels: guide.programmes, id: "bbc1", at: at)
        #expect(now?.title == "Morning News")
        let upcoming = upcomingShows(channels: guide.programmes, id: "bbc1",
                                     at: at, limit: 5)
        #expect(upcoming.map(\.title) == ["Talk Show"])
    }

    @Test("normalizes ids like the curator")
    func normalizesIDs() {
        #expect(normalizeEPGID("5Gold.il@SD") == "5gold.il")
        #expect(normalizeEPGID("BBC One") == "bbc one")
    }

    @Test("parses a real trimmed guide sample")
    func parsesRealSample() throws {
        let url = Bundle.module.url(forResource: "al1-sample",
                                    withExtension: "xml")
        #expect(url != nil)
        let data = try Data(contentsOf: url!)
        let guide = try parseXMLTV(data)
        #expect(!guide.channels.isEmpty)
        #expect(!guide.programmes.isEmpty)
    }
}
