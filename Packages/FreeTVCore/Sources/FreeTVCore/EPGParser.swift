import Foundation

/// One XMLTV channel and its programmes.
public struct EPGChannel: Hashable, Sendable {
    public let id: String
    public let name: String
    public let icon: URL?
}

public struct EPGProgramme: Hashable, Sendable {
    public let channelID: String
    public let start: Date
    public let stop: Date
    public let title: String
    public let desc: String?
}

public struct EPGGuide: Sendable {
    public let channels: [EPGChannel]
    public let programmes: [String: [EPGProgramme]]

    public init(channels: [EPGChannel], programmes: [String: [EPGProgramme]]) {
        self.channels = channels
        self.programmes = programmes
    }
}

/// Same normalization as the curator (lowercase, strip @suffix).
public func normalizeEPGID(_ id: String) -> String {
    id.split(separator: "@").first.map(String.init)?.lowercased()
        .trimmingCharacters(in: .whitespaces) ?? ""
}

private final class XMLTVParserDelegate: NSObject, XMLParserDelegate,
    @unchecked Sendable {
    var channels: [EPGChannel] = []
    var programmes: [String: [EPGProgramme]] = [:]
    var currentChannelID = ""
    var currentName = ""
    var currentIcon: String?
    var currentStart = ""
    var currentStop = ""
    var currentTitle = ""
    var currentDesc = ""
    var text = ""
    var inChannel = false
    var inProgramme = false
    var inTitle = false
    var inDesc = false
    var inDisplayName = false

    static let dateFormat: DateFormatter = {
        let format = DateFormatter()
        format.dateFormat = "yyyyMMddHHmmss Z"
        format.locale = Locale(identifier: "en_US_POSIX")
        return format
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "channel":
            inChannel = true
            currentChannelID = attributes["id"] ?? ""
            currentName = ""
            currentIcon = nil
        case "programme":
            inProgramme = true
            currentChannelID = attributes["channel"] ?? ""
            currentStart = attributes["start"] ?? ""
            currentStop = attributes["stop"] ?? ""
            currentTitle = ""
            currentDesc = ""
        case "display-name": inDisplayName = true
        case "title": inTitle = true
        case "desc": inDesc = true
        case "icon":
            if inChannel { currentIcon = attributes["src"] }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "display-name":
            if !value.isEmpty, currentName.isEmpty { currentName = value }
            inDisplayName = false
        case "title":
            currentTitle += value
            inTitle = false
        case "desc":
            currentDesc += (currentDesc.isEmpty ? "" : " ") + value
            inDesc = false
        case "channel":
            channels.append(EPGChannel(
                id: currentChannelID,
                name: currentName.isEmpty ? currentChannelID : currentName,
                icon: currentIcon.flatMap(URL.init(string:))))
            inChannel = false
        case "programme":
            if let start = Self.dateFormat.date(from: currentStart),
               let stop = Self.dateFormat.date(from: currentStop) {
                programmes[currentChannelID, default: []].append(
                    EPGProgramme(channelID: currentChannelID, start: start,
                                 stop: stop, title: currentTitle,
                                 desc: currentDesc.isEmpty ? nil : currentDesc))
            }
            inProgramme = false
        default: break
        }
        text = ""
    }
}

public enum EPGParseError: Error {
    case invalidDocument
}

/// Parses an XMLTV document into channels and per-channel programmes.
public func parseXMLTV(_ data: Data) throws -> EPGGuide {
    let delegate = XMLTVParserDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() else { throw EPGParseError.invalidDocument }
    var programmes: [String: [EPGProgramme]] = [:]
    for (id, shows) in delegate.programmes {
        programmes[normalizeEPGID(id), default: []]
            += shows.sorted { $0.start < $1.start }
    }
    return EPGGuide(channels: delegate.channels, programmes: programmes)
}

/// Programme airing at `at`, if any.
public func nowPlaying(channels: [String: [EPGProgramme]], id: String,
                       at: Date = Date()) -> EPGProgramme? {
    (channels[normalizeEPGID(id)] ?? []).first {
        $0.start <= at && at < $0.stop
    }
}

/// Next programmes after `at`, soonest first.
public func upcomingShows(channels: [String: [EPGProgramme]], id: String,
                          at: Date = Date(), limit: Int = 10)
    -> [EPGProgramme] {
    (channels[normalizeEPGID(id)] ?? []).filter { $0.start > at }
        .sorted { $0.start < $1.start }
        .prefix(limit).map { $0 }
}
