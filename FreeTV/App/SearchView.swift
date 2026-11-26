import SwiftUI
import FreeTVCore

struct SearchView: View {
    @EnvironmentObject private var store: CatalogStore
    @State private var query = ""
    @State private var focusTask: Task<Void, Never>?
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
            focusTask?.cancel()
            focusTask = Task {
                // Toggle false/true: SwiftUI only issues a focus request
                // on change, so repeat shots must reset first.
                for _ in 0 ..< 4 {
                    if Task.isCancelled { return }
                    fieldFocused = false
                    try? await Task.sleep(for: .seconds(0.3))
                    if Task.isCancelled { return }
                    fieldFocused = true
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        .onDisappear { focusTask?.cancel() }
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
