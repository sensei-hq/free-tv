import SwiftUI
import FreeTVCore

struct SearchView: View {
    @EnvironmentObject private var store: CatalogStore
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search channels", text: $query)
                .focused($fieldFocused)
                .frame(maxWidth: 600)
                .padding(.top, 40)
            ChannelGrid(
                channels: search(channels: store.channels, query: query),
                emptyText: query.isEmpty
                    ? "Type to search \(store.channels.count) channels"
                    : "No channels match “\(query)”"
            )
        }
        .navigationTitle("Search")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                fieldFocused = true
            }
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var store: CatalogStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        ChannelGrid(
            channels: store.channels.filter { favorites.isFavorite($0) },
            emptyText: "No favorites yet — open a channel and ♡ it"
        )
        .navigationTitle("Favorites")
    }
}
