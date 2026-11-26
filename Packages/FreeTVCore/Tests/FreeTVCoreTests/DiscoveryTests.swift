import Foundation
import Testing

@testable import FreeTVCore

let gdmFixture = """
HTTP/1.0 200 OK
Name: Yutaka
Port: 32400
Resource-Identifier: 9b0a80dcd453e26e85161822e16fb036a9442fc4
Server-Class: Primary
Content-Type: plex/media-server
"""

@Suite("GDM discovery parsing")
struct GDMTests {
    @Test("parses a discovery reply")
    func parsesReply() {
        let found = parseGDMResponse(gdmFixture, host: "10.0.0.252")
        #expect(found?.name == "Yutaka")
        #expect(found?.baseURL.absoluteString == "http://10.0.0.252:32400")
        #expect(found?.identifier.hasPrefix("9b0a80dc") == true)
    }

    @Test("rejects incomplete replies")
    func rejectsIncomplete() {
        #expect(parseGDMResponse("HTTP/1.0 200 OK\nName: X\n",
                                host: "10.0.0.1") == nil)
    }
}

@Suite("Keychain token storage")
struct KeychainTests {
    @Test("round-trips a token")
    func roundTrip() throws {
        let store = KeychainStore(service: "tv.freetv.test")
        try store.delete(account: "plex-test")
        #expect(store.load(account: "plex-test") == nil)
        try store.save("secret-token", account: "plex-test")
        #expect(store.load(account: "plex-test") == "secret-token")
        try store.delete(account: "plex-test")
        #expect(store.load(account: "plex-test") == nil)
    }
}
