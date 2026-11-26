import Foundation

/// Loads catalog.json from the published URL and caches it on disk.
/// Falls back to the cache when the network is unavailable.
@MainActor
public final class CatalogStore: ObservableObject {
    public static let defaultSource = URL(
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
        do {
            let (data, _) = try await session.data(from: sourceURL)
            try apply(data: data)
            try? data.write(to: cacheURL, options: .atomic)
            lastError = nil
        } catch {
            if let cached = try? Data(contentsOf: cacheURL) {
                try apply(data: cached)
                lastError = nil
            } else {
                lastError = error.localizedDescription
                throw error
            }
        }
    }

    private func apply(data: Data) throws {
        let catalog = try Catalog.decode(from: data)
        let live = catalog.liveChannels
        channels = live
        shelves = makeShelves(from: live)
    }
}
