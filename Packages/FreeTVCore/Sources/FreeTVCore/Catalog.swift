import Foundation

/// One playable channel from catalog.json.
public struct Channel: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { url }
    public let name: String
    public let url: String
    public let logo: String?
    public let tvgID: String?
    public let category: String
    public let country: String?
    public let sources: [String]
    public let status: String
    public let quarantined: Bool
    public let hasGuide: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case name, url, logo, category, country, sources, status, quarantined
        case tvgID = "tvg_id"
        case hasGuide = "has_guide"
    }

    public var logoURL: URL? {
        guard let logo, !logo.isEmpty else { return nil }
        return URL(string: logo)
    }

    public var streamURL: URL? { URL(string: url) }
}

public struct CatalogStats: Codable, Sendable {
    public let total: Int
    public let online: Int
    public let quarantined: Int
}

/// The published catalog.json document.
public struct Catalog: Codable, Sendable {
    public let generatedAt: String?
    public let epgURLs: [String]
    public let stats: CatalogStats?
    public let channels: [Channel]

    enum CodingKeys: String, CodingKey {
        case channels, stats
        case generatedAt = "generated_at"
        case epgURLs = "epg_urls"
    }

    public static func decode(from data: Data) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: data)
    }

    public var liveChannels: [Channel] {
        channels.filter { !$0.quarantined }
    }
}

/// One Netflix-style shelf: a category title plus its channels.
public struct Shelf: Sendable {
    public let title: String
    public let channels: [Channel]
}

/// Preferred shelf order: curated categories first, then countries A-Z.
public let preferredShelfOrder = [
    "Sports", "News", "Documentaries", "Kids", "Movies", "Music",
]

public func makeShelves(from channels: [Channel]) -> [Shelf] {
    var grouped: [String: [Channel]] = [:]
    for channel in channels {
        grouped[channel.category, default: []].append(channel)
    }
    let rank = Dictionary(uniqueKeysWithValues:
        preferredShelfOrder.enumerated().map { ($1, $0) })
    let titles = grouped.keys.sorted {
        switch (rank[$0], rank[$1]) {
        case let (a?, b?): return a < b
        case (_?, nil): return true
        case (nil, _?): return false
        default: return $0 < $1
        }
    }
    return titles.map { Shelf(title: $0, channels: grouped[$0] ?? []) }
}

public func search(channels: [Channel], query: String) -> [Channel] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return [] }
    return channels.filter { $0.name.lowercased().contains(needle) }
}
