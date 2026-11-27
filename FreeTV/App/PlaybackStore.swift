import Foundation
import FreeTVCore

/// Continue-watching state, persisted across launches.
@MainActor
final class PlaybackStore: ObservableObject {
    @Published private(set) var items: [WatchProgress] = []

    private let memory = PlaybackMemoryStore()
    private let defaults = UserDefaults.standard
    private let key = "free-tv-playback"

    init() {
        if LaunchTestHooks.resetData {
            defaults.removeObject(forKey: key)
        }
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([WatchProgress].self,
                                                 from: data) {
            saved.forEach(memory.record)
        }
        items = memory.items
    }

    func record(_ progress: WatchProgress) {
        memory.record(progress)
        persist()
    }

    func clear(id: String) {
        memory.clear(id: id)
        persist()
    }

    func progress(id: String) -> WatchProgress? {
        memory.items.first { $0.id == id }
    }

    private func persist() {
        items = memory.items
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
