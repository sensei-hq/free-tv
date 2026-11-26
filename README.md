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

Push to GitHub, enable Pages for the `gh-pages` branch, and the
`curate` workflow rebuilds daily at 06:00 UTC. Paste the published
`curated.m3u` URL (or a small `sports.m3u`) into UHF or IPTVX on Apple TV.
