import Foundation

/// Cost ladder for ordering sources: owned first, purchases last.
/// (TMDB publishes no prices, so ordering is by cost category.)
public enum WatchCost: Sendable {
    case owned
    case free
    case subscription
    case rent
    case buy

    public var rank: Int {
        switch self {
        case .owned: return 0
        case .free: return 1
        case .subscription: return 2
        case .rent: return 3
        case .buy: return 4
        }
    }

    public var badge: String {
        switch self {
        case .owned: return "OWNED"
        case .free: return "FREE"
        case .subscription: return "SUB"
        case .rent: return "RENT"
        case .buy: return "BUY"
        }
    }
}

/// Curated launch URLs per TMDB provider id. Custom schemes first
/// (tvOS handles them best), https fallbacks last. Only schemes with
/// published evidence are listed; anything else resolves to nil and
/// the UI shows that provider as unavailable.
public struct ProviderLink: Equatable, Sendable {
    public let candidates: [URL]

    private static let table: [Int: [String]] = [
        8: ["nflx://", "https://www.netflix.com"],
        175: ["nflx://", "https://www.netflix.com"],
        1796: ["nflx://", "https://www.netflix.com"],
        9: ["aiv://", "https://www.amazon.com/gp/video"],
        613: ["aiv://", "https://www.amazon.com/gp/video"],
        2100: ["aiv://", "https://www.amazon.com/gp/video"],
        15: ["hulu://", "https://www.hulu.com"],
        73: ["https://tubitv.com"],
        192: ["youtube://", "https://www.youtube.com"],
        188: ["youtube://", "https://www.youtube.com"],
        235: ["youtube://", "https://www.youtube.com"],
        538: ["plex://", "https://app.plex.tv"],
        300: ["https://www.pluto.tv"],
        207: ["https://therokuchannel.roku.com"],
        209: ["https://www.pbs.org"],
        191: ["https://www.kanopy.com"],
        212: ["https://www.hoopladigital.com"],
    ]

    public static func links(for providerID: Int) -> ProviderLink? {
        guard let urls = table[providerID] else { return nil }
        let parsed = urls.compactMap(URL.init(string:))
        return parsed.isEmpty ? nil : ProviderLink(candidates: parsed)
    }
}
