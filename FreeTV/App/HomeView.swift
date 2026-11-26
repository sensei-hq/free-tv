import SwiftUI
import FreeTVCore

/// Home tab: Netflix-style shelves, one row per category.
struct HomeView: View {
    @EnvironmentObject private var store: CatalogStore
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ScrollView {
                    if store.shelves.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading channels…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 40) {
                            ForEach(store.shelves, id: \.title) { shelf in
                                ShelfRow(shelf: shelf)
                            }
                        }
                        .padding(.vertical, 40)
                    }
                }
                .navigationDestination(for: Channel.self) { channel in
                    ChannelDetailView(channel: channel)
                }
                .navigationTitle("Free TV")
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                SearchView()
                    .navigationDestination(for: Channel.self) { channel in
                        ChannelDetailView(channel: channel)
                    }
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(1)

            NavigationStack {
                FavoritesView()
                    .navigationDestination(for: Channel.self) { channel in
                        ChannelDetailView(channel: channel)
                    }
            }
            .tabItem { Label("Favorites", systemImage: "heart") }
            .tag(2)
        }
    }
}

struct ShelfRow: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2)
                .bold()
                .padding(.horizontal, 60)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(shelf.channels) { channel in
                        NavigationLink(value: channel) {
                            ChannelCard(channel: channel)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60)
            }
        }
    }
}
