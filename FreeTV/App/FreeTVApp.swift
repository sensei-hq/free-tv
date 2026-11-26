import SwiftUI
import FreeTVCore

@main
struct FreeTVApp: App {
    @StateObject private var store = CatalogStore()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var sources = SourceStore()
    @StateObject private var plex = PlexStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environmentObject(favorites)
                .environmentObject(sources)
                .environmentObject(plex)
                .task {
                    try? await store.refresh(sources: sources.sources)
                }
        }
    }
}
