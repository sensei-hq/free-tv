import SwiftUI
import FreeTVCore

/// Test hooks: `-tab <name>` starts on a tab, `-resetData` wipes
/// saved sources, favorites, and Plex state (keychain included).
enum LaunchTestHooks {
    static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-tab"),
              args.indices.contains(flag + 1) else { return 0 }
        return ["home", "search", "favorites", "plex", "settings"]
            .firstIndex(of: args[flag + 1]) ?? 0
    }

    static var resetData: Bool {
        ProcessInfo.processInfo.arguments.contains("-resetData")
    }
}

/// Home tab: Netflix-style shelves, one row per category.
struct HomeView: View {
    @EnvironmentObject private var store: CatalogStore
    @State private var tab = LaunchTestHooks.initialTab

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

            NavigationStack {
                PlexView()
            }
            .tabItem { Label("Plex", systemImage: "server.rack") }
            .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(4)
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
