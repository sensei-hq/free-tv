import Foundation

/// One entry of an M3U playlist.
public struct M3UEntry: Sendable {
    public let name: String
    public let url: String
    public let tvgID: String
    public let logo: String
    public let group: String
    public let country: String

    public init(name: String, url: String, tvgID: String = "",
                logo: String = "", group: String = "", country: String = "") {
        self.name = name
        self.url = url
        self.tvgID = tvgID
        self.logo = logo
        self.group = group
        self.country = country
    }

    public func toChannel(source: String) -> Channel {
        Channel(name: name, url: url,
                logo: logo.isEmpty ? nil : logo,
                tvgID: tvgID.isEmpty ? nil : tvgID,
                category: group.isEmpty ? "Unsorted" : group,
                country: country.isEmpty ? nil : country,
                sources: [source], status: "unchecked",
                quarantined: false)
    }
}

public struct M3UPlaylist: Sendable {
    public let epgURLs: [String]
    public let entries: [M3UEntry]
}

private func splitExtinf(_ line: String) -> (attrs: String, name: String) {
    let body = line.split(separator: ":", maxSplits: 1).last.map(String.init)
        ?? line
    var inQuotes = false
    for index in body.indices {
        let char = body[index]
        if char == "\"" { inQuotes.toggle() }
        if char == "," && !inQuotes {
            return (String(body[..<index]), String(body[body.index(after: index)...]))
        }
    }
    return (body, "")
}

private func parseAttrs(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    let pattern = #"([\w-]+)="([^"]*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return result
    }
    let range = NSRange(text.startIndex..., in: text)
    for match in regex.matches(in: text, range: range) {
        if let key = Range(match.range(at: 1), in: text),
           let value = Range(match.range(at: 2), in: text) {
            result[String(text[key])] = String(text[value])
        }
    }
    return result
}

private func countryFromTvgID(_ tvgID: String) -> String {
    let pattern = #"\.([a-z]{2})(?:@|$)"#
    guard let regex = try? NSRegularExpression(
        pattern: pattern, options: .caseInsensitive) else { return "" }
    let range = NSRange(tvgID.startIndex..., in: tvgID)
    guard let match = regex.firstMatch(in: tvgID, range: range),
          let code = Range(match.range(at: 1), in: tvgID) else { return "" }
    return String(tvgID[code]).uppercased()
}

public func parseM3U(_ text: String) -> M3UPlaylist {
    var epgURLs: [String] = []
    var entries: [M3UEntry] = []
    var pending: M3UEntry?
    for raw in text.components(separatedBy: .newlines) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("#EXTM3U") {
            let attrs = parseAttrs(line)
            for key in ["x-tvg-url", "url-tvg"] {
                if let value = attrs[key] {
                    epgURLs += value.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            }
        } else if line.hasPrefix("#EXTINF") {
            let parts = splitExtinf(line)
            let attrs = parseAttrs(parts.attrs)
            let tvgID = attrs["tvg-id"] ?? ""
            pending = M3UEntry(
                name: parts.name.trimmingCharacters(in: .whitespaces),
                url: "",
                tvgID: tvgID,
                logo: attrs["tvg-logo"] ?? "",
                group: attrs["group-title"] ?? "",
                country: attrs["tvg-country"].flatMap { $0.isEmpty ? nil : $0 }
                    ?? countryFromTvgID(tvgID))
        } else if line.hasPrefix("#") || pending == nil {
            continue
        } else {
            pending = M3UEntry(name: pending!.name, url: line,
                               tvgID: pending!.tvgID, logo: pending!.logo,
                               group: pending!.group,
                               country: pending!.country)
            entries.append(pending!)
            pending = nil
        }
    }
    var seen = Set<String>()
    let unique = epgURLs.filter { seen.insert($0).inserted }
    return M3UPlaylist(epgURLs: unique, entries: entries)
}

private func normalizeURL(_ url: String) -> String {
    guard var parts = URLComponents(string: url.trimmingCharacters(
        in: .whitespacesAndNewlines)) else { return url }
    parts.scheme = parts.scheme?.lowercased()
    parts.host = parts.host?.lowercased()
    return parts.string ?? url
}

/// Merge channels from several sources, deduping by stream URL.
public func mergeChannels(_ channels: [Channel]) -> [Channel] {
    var merged: [Channel] = []
    var indexByURL: [String: Int] = [:]
    for channel in channels {
        let key = normalizeURL(channel.url)
        if let index = indexByURL[key] {
            let keep = merged[index]
            merged[index] = Channel(
                name: keep.name, url: keep.url,
                logo: (keep.logo ?? "").isEmpty ? channel.logo : keep.logo,
                tvgID: (keep.tvgID ?? "").isEmpty ? channel.tvgID : keep.tvgID,
                category: keep.category, country: keep.country,
                sources: Array(Set(keep.sources + channel.sources)).sorted(),
                status: keep.status,
                quarantined: keep.quarantined && channel.quarantined)
        } else {
            indexByURL[key] = merged.count
            merged.append(channel)
        }
    }
    return merged
}
