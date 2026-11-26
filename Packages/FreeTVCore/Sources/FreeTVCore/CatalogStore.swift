import Foundation

/// Loads catalog.json from the published URL and caches it on disk.
/// Falls back to the cache when the network is unavailable.
@MainActor
public final class CatalogStore: ObservableObject {
    nonisolated public static let defaultSource = URL(
        string: "https://sensei-hq.github.io/free-tv/catalog.json")!

    @Published public private(set) var channels: [Channel] = []
    @Published public private(set) var shelves: [Shelf] = []
    @Published public private(set) var lastError: String?

    private let sourceURL: URL
    private let session: URLSession
    private let cacheURL: URL

    public init(
        sourceURL: URL = CatalogStore.defaultSource,
        session: URLSession = .shared,
        cacheURL: URL? = nil
    ) {
        self.sourceURL = sourceURL
        self.session = session
        self.cacheURL = cacheURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("free-tv-catalog.json")
    }

    public func refresh() async throws {
        try await refresh(sources: [Source(name: "default", kind: .catalog,
                                           url: sourceURL)])
    }

    /// Loads every enabled source (catalog JSON or M3U) and merges them.
    public func refresh(sources: [Source]) async throws {
        var merged: [Channel] = []
        var failures = 0
        for source in sources where source.isEnabled {
            do {
                let (data, _) = try await session.data(from: source.url)
                switch source.kind {
                case .catalog:
                    merged += try Catalog.decode(from: data).liveChannels
                case .m3u:
                    let text = String(data: data, encoding: .utf8) ?? ""
                    merged += parseM3U(text).entries.map {
                        $0.toChannel(source: source.name)
                    }
                }
            } catch {
                failures += 1
            }
        }
        if merged.isEmpty, failures > 0,
           let cached = try? Data(contentsOf: cacheURL) {
            try apply(data: cached)
            lastError = nil
            return
        }
        if merged.isEmpty, failures > 0 {
            lastError = "All sources failed to load"
            throw URLError(.cannotLoadFromNetwork)
        }
        let live = mergeChannels(merged).filter { !$0.quarantined }
        channels = live
        shelves = makeShelves(from: live)
        lastError = nil
        let snapshot = Catalog(generatedAt: nil, epgURLs: [], stats: nil,
                               channels: live)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func apply(data: Data) throws {
        let catalog = try Catalog.decode(from: data)
        let live = catalog.liveChannels
        channels = live
        shelves = makeShelves(from: live)
    }
}
