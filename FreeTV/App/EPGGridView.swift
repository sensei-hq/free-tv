import SwiftUI
import FreeTVCore

/// TV guide grid: channel rows against a 3-hour timeline.
struct EPGGridView: View {
    @EnvironmentObject private var store: CatalogStore
    @EnvironmentObject private var epg: EPGStore
    @EnvironmentObject private var playback: PlaybackStore
    @State private var shelfTitle: String?
    @State private var playing: Channel?
    @State private var now = Date()

    private let pxPerMinute: Double = 8
    private let rowHeaderWidth: Double = 300
    private let windowHours = 3

    private var windowStart: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour,
                                             .minute], from: now)
        let floored = (parts.minute ?? 0) / 30 * 30
        return calendar.date(from: DateComponents(
            year: parts.year, month: parts.month, day: parts.day,
            hour: parts.hour, minute: floored)) ?? now
    }

    private var windowEnd: Date {
        windowStart.addingTimeInterval(Double(windowHours * 3600))
    }

    private var channels: [Channel] {
        let shelf = store.shelves.first {
            $0.title == (shelfTitle ?? defaultShelfTitle)
        }
        return Array((shelf?.channels ?? []).prefix(20))
    }

    /// First shelf with guided channels, so the grid opens with data.
    private var defaultShelfTitle: String? {
        store.shelves.first {
            $0.channels.contains { $0.hasGuide == true }
        }?.title ?? store.shelves.first?.title
    }

    private var titles: [String] {
        store.shelves.map(\.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(titles, id: \.self) { title in
                        Button(title) { shelfTitle = title }
                            .buttonStyle(.card)
                            .opacity(shelfTitle == title
                                || (shelfTitle == nil
                                    && title == titles.first) ? 1.0 : 0.6)
                    }
                }
                .padding(.horizontal, 60)
            }
            Text(epgStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 60)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    timeHeader
                    ForEach(channels) { channel in
                        channelRow(channel)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
                .overlay(alignment: .leading) { nowLine }
            }
        }
        .task {
            await epg.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
        .fullScreenCover(item: $playing) { channel in
            PlayerView(channel: channel)
        }
    }

    private var epgStatus: String {
        if epg.isLoading { return "Loading guide…" }
        return "\(epg.programmeCount) programmes"
    }

    private var timeHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: rowHeaderWidth)
            ForEach(0 ..< windowHours * 2, id: \.self) { slot in
                Text(headerLabel(slot: slot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30 * pxPerMinute, alignment: .leading)
            }
        }
    }

    private func headerLabel(slot: Int) -> String {
        let date = windowStart.addingTimeInterval(Double(slot * 1800))
        let format = DateFormatter()
        format.timeStyle = .short
        return format.string(from: date)
    }

    private var nowLine: some View {
        let elapsed = max(0, now.timeIntervalSince(windowStart) / 60)
        return Rectangle()
            .fill(Color.red)
            .frame(width: 3)
            .padding(.leading, 60 + rowHeaderWidth + elapsed * pxPerMinute)
    }

    private func channelRow(_ channel: Channel) -> some View {
        HStack(spacing: 0) {
            Button {
                play(channel)
            } label: {
                HStack(spacing: 12) {
                    if let logo = channel.logoURL {
                        AsyncImage(url: logo) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name).font(.headline).lineLimit(1)
                        Text(nowTitle(channel)).font(.caption)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(width: rowHeaderWidth, alignment: .leading)
            }
            .buttonStyle(.card)
            programmesStrip(channel)
        }
    }

    private func nowTitle(_ channel: Channel) -> String {
        nowPlaying(channels: epg.guide?.programmes ?? [:],
                   id: normalizeEPGID(channel.tvgID ?? ""),
                   at: now)?.title ?? "No guide data"
    }

    private func programmesStrip(_ channel: Channel) -> some View {
        let shows = epg.programmes(for: channel).filter {
            $0.stop > windowStart && $0.start < windowEnd
        }
        return HStack(spacing: 4) {
            if shows.isEmpty {
                Button { play(channel) } label: {
                    Text("No guide data — play")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 240, height: 72, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.card)
            } else {
                ForEach(shows, id: \.title) { show in
                    programmeCell(show, channel: channel)
                }
            }
        }
    }

    private func programmeCell(_ show: EPGProgramme,
                               channel: Channel) -> some View {
        let start = max(show.start, windowStart)
        let stop = min(show.stop, windowEnd)
        let width = max(110, stop.timeIntervalSince(start) / 60 * pxPerMinute)
        return Button { play(channel) } label: {
            Text(show.title)
                .font(.caption)
                .lineLimit(2)
                .frame(width: width, height: 72, alignment: .leading)
                .padding(.horizontal, 12)
                .background(show.start <= now && now < show.stop
                    ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.card)
    }

    private func play(_ channel: Channel) {
        playback.record(WatchProgress(
            id: channel.url, title: channel.name, kind: .live,
            url: channel.streamURL, tmdbID: nil, artwork: channel.logoURL,
            position: 0, duration: 0, updatedAt: Date()))
        playing = channel
    }
}
