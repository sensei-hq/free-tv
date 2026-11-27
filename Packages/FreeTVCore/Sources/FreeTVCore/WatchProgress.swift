import Foundation

/// Resume state for one watched item. VOD items carry a position;
/// live channels are recency-only (seeking makes no sense live).
public struct WatchProgress: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case live
        case vod
    }

    public let id: String
    public let title: String
    public let kind: Kind
    public let url: URL?
    public let tmdbID: Int?
    public let artwork: URL?
    public let position: Double
    public let duration: Double
    public let updatedAt: Date

    public init(id: String, title: String, kind: Kind, url: URL?,
                tmdbID: Int?, artwork: URL? = nil, position: Double,
                duration: Double, updatedAt: Date) {
        self.id = id
        self.title = title
        self.kind = kind
        self.url = url
        self.tmdbID = tmdbID
        self.artwork = artwork
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    /// Seconds to resume from, or nil for live / from-start playback.
    public var resumeFrom: Double? {
        guard kind == .vod, duration > 0, position > 10,
              !isFinished else { return nil }
        return position
    }

    public var fraction: Double {
        guard kind == .vod, duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    public var isFinished: Bool {
        kind == .vod && duration > 0 && position >= duration - 30
    }

    public var remainingText: String {
        guard kind == .vod, duration > 0 else { return "Live" }
        let left = max(0, Int(duration - position))
        if left >= 3600 {
            return "\(left / 3600) h \(left % 3600 / 60) min left"
        }
        return "\(left / 60) min left"
    }
}

/// Recency-ordered, size-capped progress list. Persistence lives in
/// the app layer; this type owns the ordering rules (testable).
public final class PlaybackMemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: WatchProgress] = [:]
    private let limit: Int

    public init(limit: Int = 20) {
        self.limit = limit
    }

    public var items: [WatchProgress] {
        lock.withLock {
            entries.values.filter { !$0.isFinished }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(limit).map { $0 }
        }
    }

    public func record(_ progress: WatchProgress) {
        lock.withLock {
            entries[progress.id] = progress
            let ordered = entries.values
                .sorted { $0.updatedAt > $1.updatedAt }
            for stale in ordered.dropFirst(limit) {
                entries.removeValue(forKey: stale.id)
            }
        }
    }

    public func clear(id: String) {
        lock.withLock { entries.removeValue(forKey: id) }
    }
}
