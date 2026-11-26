import Foundation
import FreeTVCore

/// Favorite channel URLs, persisted across launches.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var urls: Set<String> = []

    private let key = "free-tv-favorites"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        urls = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func isFavorite(_ channel: Channel) -> Bool {
        urls.contains(channel.url)
    }

    func toggle(_ channel: Channel) {
        if urls.contains(channel.url) {
            urls.remove(channel.url)
        } else {
            urls.insert(channel.url)
        }
        defaults.set(Array(urls), forKey: key)
    }
}
