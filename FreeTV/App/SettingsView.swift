import SwiftUI
import FreeTVCore

/// Sources, servers, and sign-in. Everything here is user-managed.
struct SettingsView: View {
    @EnvironmentObject private var sources: SourceStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var plex: PlexStore
    @EnvironmentObject private var tmdb: TMDBStore
    @State private var addingSource = false
    @State private var keyText = ""
    @State private var regionText = ""

    var body: some View {
        List {
            Section("Channel sources") {
                Button("Add source") { addingSource = true }
                ForEach(sources.sources) { source in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(source.name).font(.headline)
                            Text(source.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(source.kind == .catalog ? "Catalog" : "Playlist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(
                            get: { source.isEnabled },
                            set: { _ in
                                sources.toggle(source)
                                refresh()
                            }
                        ))
                        .labelsHidden()
                        Button("Delete") {
                            sources.remove(source)
                            refresh()
                        }
                    }
                }
            }

            Section("Movies (TMDB)") {
                if tmdb.hasKey {
                    Text("API key saved")
                    Text("Region: \(tmdb.region)")
                    Button("Remove key") { tmdb.clearKey() }
                } else {
                    SecureField("TMDB API key", text: $keyText)
                    Button("Save key") {
                        tmdb.saveKey(keyText)
                        keyText = ""
                    }
                }
                TextField("Region code (e.g. US)", text: $regionText)
                Button("Save region") {
                    tmdb.saveRegion(regionText)
                    regionText = ""
                }
            }

            Section("Plex") {
                if plex.isSignedIn {
                    Text("Server: \(plex.serverName ?? "")")
                    NavigationLink("Plex libraries") { PlexView() }
                    Button("Sign out") { plex.signOut() }
                } else if plex.isLinking, let code = plex.linkCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter this code at plex.tv/link")
                        Text(code).font(.largeTitle).bold()
                    }
                    Button("Cancel") { plex.cancelLink() }
                } else {
                    Button("Sign in to Plex") { plex.beginLink() }
                }
                if let error = plex.linkError {
                    Text(error).foregroundStyle(.red)
                }
                Button(plex.isScanning ? "Scanning…" : "Find local servers") {
                    plex.scan()
                }
                .disabled(plex.isScanning)
                ForEach(plex.discovered, id: \.identifier) { server in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name).font(.headline)
                            Text(server.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use") { plex.useDiscovered(server) }
                    }
                }
            }
        }

        .sheet(isPresented: $addingSource) {
            AddSourceView(onSave: refresh)
        }
    }

    private func refresh() {
        let list = sources.sources
        Task { try? await catalog.refresh(sources: list) }
    }
}

struct AddSourceView: View {
    var onSave: () -> Void
    @EnvironmentObject private var sources: SourceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlText = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("Add source").font(.title2).bold()
            TextField("Name (e.g. Sports)", text: $name)
                .focused($nameFocused)
                .frame(maxWidth: 600)
            TextField("URL (catalog .json or playlist .m3u)", text: $urlText)
                .frame(maxWidth: 600)
            if let error {
                Text(error).foregroundStyle(.red)
            }
            HStack(spacing: 20) {
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
            }
        }
        .padding(60)
        .onAppear {
            for delay in [0.5, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    nameFocused = true
                }
            }
        }
    }

    private func save() {
        guard let url = URL(string: urlText.trimmingCharacters(
            in: .whitespaces)),
            ["http", "https"].contains(url.scheme?.lowercased()) else {
            error = "Enter a valid http(s) URL"
            return
        }
        let title = name.trimmingCharacters(in: .whitespaces)
        sources.add(name: title.isEmpty ? url.host ?? "Source" : title,
                    url: url)
        onSave()
        dismiss()
    }
}
