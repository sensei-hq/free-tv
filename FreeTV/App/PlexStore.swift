import Foundation
import FreeTVCore

/// Plex account, server choice, and library state. Tokens in keychain,
/// server address in UserDefaults, nothing hardcoded.
@MainActor
final class PlexStore: ObservableObject {
    @Published private(set) var linkCode: String?
    @Published private(set) var isLinking = false
    @Published private(set) var linkError: String?
    @Published private(set) var serverName: String?
    @Published private(set) var discovered: [DiscoveredServer] = []
    @Published private(set) var isScanning = false
    @Published var sections: [LibrarySection] = []

    let client: PlexClient
    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?

    var isSignedIn: Bool { serverName != nil }

    var serverURL: URL? {
        defaults.string(forKey: "free-tv-plex-url").flatMap(URL.init(string:))
    }

    var serverToken: String? {
        keychain.load(account: "plex-server-token")
    }

    init() {
        let key = "free-tv-plex-client-id"
        let identifier: String
        if let saved = defaults.string(forKey: key) {
            identifier = saved
        } else {
            identifier = UUID().uuidString
            defaults.set(identifier, forKey: key)
        }
        client = PlexClient(clientIdentifier: identifier)
        if LaunchTestHooks.resetData {
            try? KeychainStore().delete(account: "plex-user-token")
            try? KeychainStore().delete(account: "plex-server-token")
            defaults.removeObject(forKey: "free-tv-plex-name")
            defaults.removeObject(forKey: "free-tv-plex-url")
        }
        serverName = defaults.string(forKey: "free-tv-plex-name")
        if serverName != nil { refreshSections() }
    }

    // MARK: - Sign-in (plex.tv/link PIN flow)

    func beginLink() {
        guard !isLinking else { return }
        isLinking = true
        linkError = nil
        pollTask = Task {
            do {
                let pin = try await client.createPin()
                linkCode = pin.code
                for _ in 0 ..< 150 {
                    if Task.isCancelled { return }
                    try await Task.sleep(for: .seconds(2))
                    if let token = try await client.pollPin(id: pin.id) {
                        try? keychain.save(token, account: "plex-user-token")
                        await selectBestServer(userToken: token)
                        return
                    }
                }
                linkError = "Timed out — try again"
                finishLinking()
            } catch is CancellationError {
                finishLinking()
            } catch {
                linkError = error.localizedDescription
                finishLinking()
            }
        }
    }

    func cancelLink() {
        pollTask?.cancel()
        pollTask = nil
        finishLinking()
    }

    private func finishLinking() {
        isLinking = false
        linkCode = nil
    }

    private func selectBestServer(userToken: String) async {
        do {
            let servers = try await client.servers(token: userToken)
            guard let pick = servers.first(where: { $0.localURL != nil })
                ?? servers.first,
                let base = pick.bestURL else {
                linkError = "No servers on this account"
                finishLinking()
                return
            }
            saveServer(name: pick.name, url: base, token: pick.token)
            finishLinking()
            refreshSections()
        } catch {
            linkError = error.localizedDescription
            finishLinking()
        }
    }

    /// Uses a discovered (or manually picked) server with the account token.
    func useDiscovered(_ server: DiscoveredServer) {
        guard let userToken = keychain.load(account: "plex-user-token") else {
            linkError = "Sign in first, then pick a server"
            return
        }
        saveServer(name: server.name, url: server.baseURL, token: userToken)
        refreshSections()
    }

    private func saveServer(name: String, url: URL, token: String) {
        defaults.set(name, forKey: "free-tv-plex-name")
        defaults.set(url.absoluteString, forKey: "free-tv-plex-url")
        try? keychain.save(token, account: "plex-server-token")
        serverName = name
    }

    func signOut() {
        cancelLink()
        try? keychain.delete(account: "plex-user-token")
        try? keychain.delete(account: "plex-server-token")
        defaults.removeObject(forKey: "free-tv-plex-name")
        defaults.removeObject(forKey: "free-tv-plex-url")
        serverName = nil
        sections = []
    }

    // MARK: - Discovery and libraries

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            discovered = await GDMScanner().scan()
            isScanning = false
        }
    }

    func refreshSections() {
        guard let server = serverURL, let token = serverToken else { return }
        Task {
            do {
                sections = try await client.sections(server: server,
                                                     token: token)
            } catch {
                linkError = error.localizedDescription
            }
        }
    }
}
