import Foundation
import FreeTVCore

/// Program guide: one merged guide.xml covering our channels.
@MainActor
final class EPGStore: ObservableObject {
    nonisolated static let defaultGuide = URL(
        string: "https://sensei-hq.github.io/free-tv/guide.xml")!

    @Published private(set) var guide: EPGGuide?
    @Published private(set) var isLoading = false
    @Published private(set) var programmeCount = 0

    private let defaults = UserDefaults.standard

    var guideURL: URL {
        defaults.string(forKey: "free-tv-guide-url")
            .flatMap(URL.init(string:)) ?? Self.defaultGuide
    }

    func saveGuideURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return
        }
        defaults.set(trimmed, forKey: "free-tv-guide-url")
        guide = nil
    }

    func load() async {
        if guide != nil || isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: guideURL)
            let parsed = try parseXMLTV(data)
            guide = parsed
            programmeCount = parsed.programmes.values
                .reduce(0) { $0 + $1.count }
        } catch {
            guide = EPGGuide(channels: [], programmes: [:])
            programmeCount = 0
        }
    }

    func programmes(for channel: Channel) -> [EPGProgramme] {
        guide?.programmes[normalizeEPGID(channel.tvgID ?? "")] ?? []
    }
}
