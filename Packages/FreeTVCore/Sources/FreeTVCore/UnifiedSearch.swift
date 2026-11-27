import Foundation

/// One search across live channels, TMDB titles, and Plex items.
public struct UnifiedResults: Sendable {
    public let channels: [Channel]
    public let titles: [TMDBTitle]
    public let plexItems: [PlexItem]

    public init(channels: [Channel] = [], titles: [TMDBTitle] = [],
                plexItems: [PlexItem] = []) {
        self.channels = channels
        self.titles = titles
        self.plexItems = plexItems
    }

    public var isEmpty: Bool {
        channels.isEmpty && titles.isEmpty && plexItems.isEmpty
    }
}

public enum SearchScope: String, CaseIterable, Sendable {
    case all = "All"
    case movies = "Movies"
    case shows = "Shows"
    case channels = "Channels"
}

/// Filters pre-fetched lists by query (case-insensitive name match).
public func unifiedSearch(query: String, channels: [Channel],
                          titles: [TMDBTitle],
                          plexItems: [PlexItem] = []) -> UnifiedResults {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else {
        return UnifiedResults()
    }
    return UnifiedResults(
        channels: channels.filter {
            $0.name.lowercased().contains(needle)
        },
        titles: titles.filter { $0.name.lowercased().contains(needle) },
        plexItems: plexItems.filter {
            $0.title.lowercased().contains(needle)
        })
}

/// Narrows combined results to one media scope.
public func applyScope(_ scope: SearchScope, channels: [Channel],
                       titles: [TMDBTitle]) -> UnifiedResults {
    switch scope {
    case .all:
        return UnifiedResults(channels: channels, titles: titles)
    case .movies:
        return UnifiedResults(
            titles: titles.filter { $0.mediaType == .movie })
    case .shows:
        return UnifiedResults(
            titles: titles.filter { $0.mediaType == .show })
    case .channels:
        return UnifiedResults(channels: channels)
    }
}
