import Foundation

/// Plex sign-in (plex.tv PIN flow), server list, and library browsing.
/// Uses plex.tv account APIs plus direct local-server access; tokens are
/// held by the caller (see KeychainStore) and never logged.
public struct PlexPin: Sendable {
    public let id: Int
    public let code: String
}

public struct PlexServer: Sendable {
    public let name: String
    public let identifier: String
    public let token: String
    public let localURL: URL?
    public let remoteURL: URL?

    public var bestURL: URL? { localURL ?? remoteURL }
}

public struct LibrarySection: Hashable, Sendable {
    public let key: String
    public let type: String
    public let title: String
}

public struct PlexItem: Hashable, Sendable {
    public let title: String
    public let thumbURL: URL?
    public let durationMS: Int?
    public let playURL: URL?
}

public enum PlexError: Error {
    case badResponse
    case unauthorized
}

public final class PlexClient: Sendable {
    private let session: URLSession
    private let clientIdentifier: String

    public init(session: URLSession = .shared,
                clientIdentifier: String = UUID().uuidString) {
        self.session = session
        self.clientIdentifier = clientIdentifier
    }

    private func plexRequest(url: URL, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientIdentifier,
                         forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("FreeTV", forHTTPHeaderField: "X-Plex-Product")
        request.setValue("1.0", forHTTPHeaderField: "X-Plex-Version")
        request.setValue("tvOS", forHTTPHeaderField: "X-Plex-Platform")
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
        return request
    }

    private func get<T: Decodable>(_ type: T.Type, url: URL,
                                   token: String? = nil) async throws -> T {
        let (data, response) = try await session.data(
            for: plexRequest(url: url, token: token))
        guard let http = response as? HTTPURLResponse else {
            throw PlexError.badResponse
        }
        if http.statusCode == 401 { throw PlexError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw PlexError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Sign-in

    private struct PinResponse: Decodable {
        let id: Int
        let code: String
        let authToken: String?
    }

    /// Creates a link PIN; the user enters `code` at plex.tv/link.
    public func createPin() async throws -> PlexPin {
        var request = plexRequest(
            url: URL(string: "https://plex.tv/api/v2/pins?strong=true")!)
        request.httpMethod = "POST"
        let (data, _) = try await session.data(for: request)
        let pin = try JSONDecoder().decode(PinResponse.self, from: data)
        return PlexPin(id: pin.id, code: pin.code)
    }

    /// Returns the user token once the PIN is linked, nil while pending.
    public func pollPin(id: Int) async throws -> String? {
        let pin: PinResponse = try await get(
            PinResponse.self,
            url: URL(string: "https://plex.tv/api/v2/pins/\(id)")!)
        return pin.authToken
    }

    // MARK: - Servers and libraries

    private struct ResourceConnection: Decodable {
        let uri: String?
        let local: String?
    }

    private struct ResourceDevice: Decodable {
        let name: String?
        let provides: String?
        let clientIdentifier: String?
        let accessToken: String?
        let Connection: [ResourceConnection]?
    }

    private struct ResourcesResponse: Decodable {
        struct Container: Decodable {
            let Device: [ResourceDevice]?
        }
        let MediaContainer: Container
    }

    /// Owned servers, local connections preferred.
    public func servers(token: String) async throws -> [PlexServer] {
        let response: ResourcesResponse = try await get(
            ResourcesResponse.self,
            url: URL(string: "https://plex.tv/api/v2/resources?includeHttps=1")!,
            token: token)
        return (response.MediaContainer.Device ?? []).compactMap { device in
            guard (device.provides ?? "").contains("server"),
                  let name = device.name,
                  let identifier = device.clientIdentifier,
                  let accessToken = device.accessToken else { return nil }
            var local: URL?
            var remote: URL?
            for connection in device.Connection ?? [] {
                guard let uri = connection.uri,
                      let url = URL(string: uri) else { continue }
                if connection.local == "1", local == nil {
                    local = url
                } else if remote == nil {
                    remote = url
                }
            }
            return PlexServer(name: name, identifier: identifier,
                              token: accessToken, localURL: local,
                              remoteURL: remote)
        }
    }

    private struct SectionDirectory: Decodable {
        let key: String
        let type: String
        let title: String
    }

    private struct SectionsResponse: Decodable {
        struct Container: Decodable {
            let Directory: [SectionDirectory]?
        }
        let MediaContainer: Container
    }

    public func sections(server: URL, token: String) async throws
        -> [LibrarySection] {
        let response: SectionsResponse = try await get(
            SectionsResponse.self,
            url: server.appendingPathComponent("library/sections"),
            token: token)
        return (response.MediaContainer.Directory ?? []).map {
            LibrarySection(key: $0.key, type: $0.type, title: $0.title)
        }
    }

    private struct ItemPart: Decodable {
        let key: String?
    }

    private struct ItemMedia: Decodable {
        let Part: [ItemPart]?
    }

    private struct ItemMetadata: Decodable {
        let title: String?
        let thumb: String?
        let duration: Int?
        let Media: [ItemMedia]?
    }

    private struct ItemsResponse: Decodable {
        struct Container: Decodable {
            let Metadata: [ItemMetadata]?
        }
        let MediaContainer: Container
    }

    /// Library-wide title search (matches owned media for TMDB titles).
    public func searchTitles(server: URL, query: String,
                             token: String) async throws -> [PlexItem] {
        guard var components = URLComponents(
            url: server.appendingPathComponent("library/search"),
            resolvingAgainstBaseURL: false) else {
            throw PlexError.badResponse
        }
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components.url else { throw PlexError.badResponse }
        let response: ItemsResponse = try await get(ItemsResponse.self,
                                                    url: url, token: token)
        return items(from: response, server: server, token: token)
    }

    private func items(from response: ItemsResponse, server: URL,
                       token: String) -> [PlexItem] {
        (response.MediaContainer.Metadata ?? []).compactMap { meta in
            guard let title = meta.title else { return nil }
            func authed(_ path: String?) -> URL? {
                guard var components = path.flatMap({
                    URLComponents(url: server.appendingPathComponent($0),
                                  resolvingAgainstBaseURL: false)
                }) else { return nil }
                components.queryItems = [URLQueryItem(name: "X-Plex-Token",
                                                     value: token)]
                return components.url
            }
            let partKey = meta.Media?.first?.Part?.first?.key
            return PlexItem(title: title,
                            thumbURL: authed(meta.thumb),
                            durationMS: meta.duration,
                            playURL: authed(partKey))
        }
    }

    /// Items with direct-play URLs (no transcoding in v1).
    public func items(server: URL, sectionKey: String,
                      token: String) async throws -> [PlexItem] {
        let response: ItemsResponse = try await get(
            ItemsResponse.self,
            url: server.appendingPathComponent(
                "library/sections/\(sectionKey)/all"),
            token: token)
        return items(from: response, server: server, token: token)
    }
}
