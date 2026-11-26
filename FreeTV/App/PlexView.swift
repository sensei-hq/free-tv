import SwiftUI
import FreeTVCore

/// Personal Plex libraries, browsed inside the app.
struct PlexView: View {
    @EnvironmentObject private var plex: PlexStore

    var body: some View {
        if plex.isSignedIn {
            List(plex.sections, id: \.key) { section in
                NavigationLink(value: section) {
                    HStack {
                        Text(section.title).font(.headline)
                        Spacer()
                        Text(section.type).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(plex.serverName ?? "Plex")
            .navigationDestination(for: LibrarySection.self) { section in
                PlexSectionView(section: section)
            }
            .onAppear { plex.refreshSections() }
        } else {
            VStack(spacing: 16) {
                Text("Plex is not connected")
                    .font(.title2)
                Text("Sign in under Settings to browse this server")
                    .foregroundStyle(.secondary)
                if plex.isLinking, let code = plex.linkCode {
                    Text("Enter this code at plex.tv/link")
                    Text(code).font(.largeTitle).bold()
                    Button("Cancel") { plex.cancelLink() }
                } else {
                    Button("Sign in to Plex") { plex.beginLink() }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 400)
            .navigationTitle("Plex")
        }
    }
}

struct PlexSectionView: View {
    let section: LibrarySection
    @EnvironmentObject private var plex: PlexStore
    @State private var items: [PlexItem] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220),
                                        spacing: 24)],
                      spacing: 32) {
                ForEach(items, id: \.title) { item in
                    NavigationLink(value: item) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                                if let thumb = item.thumbURL {
                                    AsyncImage(url: thumb) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFit()
                                                .padding(8)
                                        }
                                    }
                                }
                            }
                            .frame(width: 220, height: 124)
                            Text(item.title).font(.caption).lineLimit(1)
                                .frame(width: 220)
                        }
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
        .navigationTitle(section.title)
        .navigationDestination(for: PlexItem.self) { item in
            PlexDetailView(item: item)
        }
        .task { await load() }
    }

    private func load() async {
        guard let server = plex.serverURL,
              let token = plex.serverToken else { return }
        items = (try? await plex.client.items(
            server: server, sectionKey: section.key, token: token)) ?? []
    }
}

struct PlexDetailView: View {
    let item: PlexItem
    @State private var playing = false

    var body: some View {
        HStack(spacing: 60) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                if let thumb = item.thumbURL {
                    AsyncImage(url: thumb) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit().padding(32)
                        }
                    }
                }
            }
            .frame(width: 420, height: 236)
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title).font(.largeTitle).bold()
                if item.playURL != nil {
                    Button("Play") { playing = true }
                } else {
                    Text("No direct-play file for this item")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(60)
        .fullScreenCover(isPresented: $playing) {
            PlayerView(title: item.title, url: item.playURL)
        }
    }
}
