import Foundation
import Testing

@testable import FreeTVCore

/// URLProtocol stub with a locked route registry (parallel-safe).
/// Last registered match wins, so sequential tests override freely.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes:
        [(match: String, status: Int, data: Data)] = []
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func route(_ match: String, status: Int = 200, body: String) {
        lock.withLock {
            routes.append((match, status, Data(body.utf8)))
        }
    }

    static func requests(matching substring: String) -> [URLRequest] {
        lock.withLock {
            seen.filter {
                $0.url?.absoluteString.contains(substring) == true
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let route = Self.lock.withLock {
            Self.seen.append(request)
            return Self.routes.last { url.contains($0.match) }
        }
        let (status, data) = route.map { ($0.status, $0.data) }
            ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: status,
                                       httpVersion: nil,
                                       headerFields: nil)!
        client?.urlProtocol(self, didReceive: response,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

let pinFixture = """
{"id":1613,"code":"abcd1234","product":"FreeTV","trusted":false,
 "qr":"https://plex.tv/api/v2/pins/qr/abcd1234",
 "clientIdentifier":"cid"}
"""

let pinAuthedFixture = """
{"id":1613,"code":"abcd1234","product":"FreeTV","trusted":true,
 "authToken":"USERTOKEN"}
"""

let resourcesFixture = """
{"MediaContainer":{"size":1,"Device":[
  {"name":"Yutaka","product":"Plex Media Server","provides":"server",
   "clientIdentifier":"srv1","owned":"1","accessToken":"SRVTOKEN",
   "Connection":[
     {"protocol":"http","address":"10.0.0.252","port":"32400",
      "uri":"http://10.0.0.252:32400","local":"1"},
     {"protocol":"https","address":"203.0.113.9","port":"32400",
      "uri":"https://203-0-113-9.example.com:32400","local":"0"}]}]}}
"""

let sectionsFixture = """
{"MediaContainer":{"size":2,"Directory":[
  {"key":"3","type":"movie","title":"Movies"},
  {"key":"5","type":"show","title":"TV Shows"}]}}
"""

let itemsFixture = """
{"MediaContainer":{"size":1,"Metadata":[
  {"ratingKey":"11","key":"/library/metadata/11","title":"Big Buck Bunny",
   "thumb":"/library/metadata/11/thumb/1","duration":596000,
   "Media":[{"videoCodec":"h264","audioCodec":"aac","container":"mp4",
     "Part":[{"key":"/library/parts/22/file.mp4","container":"mp4",
       "size":100}]}]}]}}
"""

@Suite("Plex API", .serialized)
struct PlexAPITests {
    @Test("creates a PIN with client headers")
    func createPin() async throws {
        MockURLProtocol.route("pins?strong=true", status: 201,
                              body: pinFixture)
        let client = PlexClient(session: mockSession(),
                                clientIdentifier: "cid")
        let pin = try await client.createPin()
        #expect(pin.id == 1613)
        #expect(pin.code == "abcd1234")
        let seenID = MockURLProtocol.requests(matching: "pins?strong=true")
            .last?.value(forHTTPHeaderField: "X-Plex-Client-Identifier")
        #expect(seenID == "cid")
    }

    @Test("poll returns token once linked")
    func pollLinked() async throws {
        MockURLProtocol.route("pins/1", body: pinAuthedFixture)
        #expect(try await PlexClient(session: mockSession()).pollPin(id: 1)
            == "USERTOKEN")
    }

    @Test("poll returns nil while pending")
    func pollPending() async throws {
        MockURLProtocol.route("pins/1", body: pinFixture)
        #expect(try await PlexClient(session: mockSession()).pollPin(id: 1)
            == nil)
    }

    @Test("lists owned servers with local connection first")
    func servers() async throws {
        MockURLProtocol.route("api/v2/resources", body: resourcesFixture)
        let servers = try await PlexClient(session: mockSession())
            .servers(token: "t")
        #expect(servers.count == 1)
        #expect(servers[0].name == "Yutaka")
        #expect(servers[0].bestURL?.absoluteString == "http://10.0.0.252:32400")
    }

    @Test("lists sections and playable items")
    func library() async throws {
        MockURLProtocol.route("library/sections", body: sectionsFixture)
        MockURLProtocol.route("sections/3/all", body: itemsFixture)
        let client = PlexClient(session: mockSession())
        let base = URL(string: "http://10.0.0.252:32400")!
        let sections = try await client.sections(server: base, token: "t")
        #expect(sections.map(\.title) == ["Movies", "TV Shows"])
        let items = try await client.items(server: base, sectionKey: "3",
                                            token: "t")
        #expect(items.count == 1)
        #expect(items[0].title == "Big Buck Bunny")
        #expect(items[0].playURL?.absoluteString.contains("/library/parts/22") == true)
        #expect(items[0].playURL?.absoluteString.contains("X-Plex-Token=t") == true)
        #expect(items[0].thumbURL?.absoluteString.contains("/thumb/1") == true)
    }
}
