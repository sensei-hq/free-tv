# Free TV curator

Merges free, legal IPTV playlists, probes every stream, quarantines the dead
ones, and publishes one clean playlist plus a machine-readable catalog. Runs
on a schedule with zero hosting cost (GitHub Actions + Pages). This is Layer 1
of the Apple TV project; the Swift tvOS app is Layer 2.

Sources today: Free-TV curated list plus iptv-org slices for Sports, News,
Documentaries, Kids, Movies, and Music. See [research notes](RESEARCH.md).

## Quickstart

```sh
python3 -m unittest discover -s tests          # 25 tests, stdlib only
python3 -m curator.cli --limit 50 --out /tmp/ft # sample run, probes 50 streams
python3 -m curator.cli --out output             # full run, publishes everything
```

## Outputs (`--out`)

| File | Contents |
|---|---|
| `curated.m3u` | All healthy streams, one `url-tvg` guide header |
| `sports.m3u`, `news.m3u`, … | Same list split by category for small player imports |
| `quarantine.m3u` | Dead streams, kept aside for inspection |
| `catalog.json` | Every channel with logo, category, country, sources, status |
| `quarantine.json` | Dead streams with failure reasons |

`--state` (default `output/state.json`) tracks consecutive failures. A stream
is quarantined after 2 failed runs and auto-restored on success.

## Config (`config/sources.json`)

Add a country slice, a language slice, or your own M3U under `sources` with a
`name`, `url`, and `category` (empty keeps the upstream group). `blocklist`
holds URL substrings to always skip. `epg_extra` adds guide URLs.

## Scheduled publishing

The `curate` workflow rebuilds daily at 06:00 UTC and publishes to
GitHub Pages. Test in UHF on Apple TV with these URLs:

- All channels: `https://sensei-hq.github.io/free-tv/curated.m3u`
- Sports only: `https://sensei-hq.github.io/free-tv/sports.m3u`
- News only: `https://sensei-hq.github.io/free-tv/news.m3u`

In UHF: add playlist, paste the URL, and the guide loads from the
playlist's embedded guide header. Start with `sports.m3u`; it is small
and fast.

## tvOS app (Layer 2)

Native SwiftUI app in `FreeTV/`, with shared logic in
`Packages/FreeTVCore` (tested: `swift test --package-path Packages/FreeTVCore`).
Open `FreeTV/FreeTV.xcodeproj` in Xcode 16+, select an Apple TV simulator or
your Apple TV as destination, and run. The app reads
`https://sensei-hq.github.io/free-tv/catalog.json` with on-device caching.
CI builds the app and runs core tests on every push touching `FreeTV/`
or `Packages/`.
