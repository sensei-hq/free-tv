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

In UHF: add a playlist with the M3U8 option, paste the URL, wait for
import, then open the Live section (channels do not appear under Home).
Start with `sports.m3u`; it is small and fast.

Each playlist carries a guide header only when matched guides cover at
least 25% of its channels; thin coverage ships no header so imports stay
fast. Full guide work (iptv-org EPG integration) is on the roadmap.

## tvOS app (Layer 2)

Native SwiftUI app in `FreeTV/`, with shared logic in
`Packages/FreeTVCore` (tested: `swift test --package-path Packages/FreeTVCore`).
Open `FreeTV/FreeTV.xcodeproj` in Xcode 16+, select an Apple TV simulator or
your Apple TV as destination, and run. Nothing is hardcoded: Settings holds
any number of catalog or M3U sources (the curated catalog is just the
default), and the Plex tab signs in via plex.tv/link plus local GDM
discovery, with tokens in the keychain. The Movies tab adds TMDB search,
year/genre browse, trending rows, and per-region where-to-watch cards
ordered owned → free → subscription → rent → buy, with app launch
where installed (verified schemes only) and Plex ownership matching
(key + region in Settings, key in keychain). Plex lives under Settings
as a source, not a tab. Home opens with a hero plus continue-watching
shelf (progress tracked in-player, resume seek for VOD, recency for
live). Search is unified across live channels, TMDB, and Plex. The
Channels tab renders a 3-hour EPG grid from the published `guide.xml`
(merged from matched guides for our channels only). Direct-play only
in v1; no prices exist in TMDB.
CI builds the app and runs core + UI tests on every push touching `FreeTV/`
or `Packages/`.
