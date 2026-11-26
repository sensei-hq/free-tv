import SwiftUI
import FreeTVCore

@main
struct FreeTVApp: App {
    @StateObject private var store = CatalogStore()
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environmentObject(favorites)
                .task {
                    try? await store.refresh()
                }
        }
    }
}
