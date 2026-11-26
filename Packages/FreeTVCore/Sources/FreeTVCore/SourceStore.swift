import Foundation

/// True when launched with `-resetData` (UI tests start clean).
enum ResetHook {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-resetData")
    }
}

/// A user-added channel source: our curated catalog or any M3U playlist.
/// Nothing is hardcoded; the default catalog is just the seed.
public struct Source: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case catalog
        case m3u
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    public var url: URL
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, kind: Kind, url: URL,
                isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.isEnabled = isEnabled
    }

    public static func detectKind(url: URL) -> Kind {
        url.pathExtension.lowercased() == "json" ? .catalog : .m3u
    }

    public static var `default`: Source {
        Source(name: "Free TV", kind: .catalog,
               url: CatalogStore.defaultSource)
    }
}

@MainActor
public final class SourceStore: ObservableObject {
    @Published public private(set) var sources: [Source] = []

    private let defaults: UserDefaults
    private let key = "free-tv-sources"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ResetHook.enabled {
            defaults.removeObject(forKey: key)
        }
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([Source].self, from: data) {
            sources = saved
        } else {
            sources = [.default]
        }
    }

    public func add(name: String, url: URL) {
        sources.append(Source(name: name, kind: Source.detectKind(url: url),
                              url: url))
        save()
    }

    public func remove(_ source: Source) {
        sources.removeAll { $0.id == source.id }
        save()
    }

    public func toggle(_ source: Source) {
        guard let index = sources.firstIndex(of: source) else { return }
        sources[index].isEnabled.toggle()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: key)
        }
    }
}
