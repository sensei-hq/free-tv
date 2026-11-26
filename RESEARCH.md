# Free-TV Research — free legal sources + Apple TV hub plan

Status: research complete, curated-apps-first plan agreed.
Choices: all genres (general + regional, sports, fitness, docs, family learning), Apple TV only, curated apps first, custom Swift app later.

## 1. IPTV sources (free-to-air only)

Rule: legal = the broadcaster itself streams it free on its own site or app. If a playlist has pay-TV sports or premium movie channels free, it is pirated. Avoid those.

- iptv-org/iptv (GitHub, 10k+ channels, daily updates). Main index plus slices by country, category, language. Also publishes JSON for app builders.
  - `https://iptv-org.github.io/iptv/index.m3u` (everything, heavy, some dead entries)
  - `https://iptv-org.github.io/iptv/countries/us.m3u` (swap `us` for your code)
  - `https://iptv-org.github.io/iptv/categories/news.m3u`, `.../categories/sports.m3u`
  - `https://iptv-org.github.io/iptv/languages/eng.m3u`
- Free-TV/IPTV (GitHub, few hundred channels, hand-curated, HD-first, one entry per channel). Best starter list.
  - `https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8`
- free-codecs IPTV Finder (web tool over public lists). Filter by country, category, language, test in web player, export custom M3U for VLC/TiviMate/Kodi. Good for building small focused playlists instead of loading the 10k index.
- Regional open lists: TDTChannels for Spain is the model example. Prefer a regional list when one exists for your country.

## 2. Program guides (EPG) and logos

- iptv-org/epg: open-source grabbers plus prebuilt per-country XMLTV. Pairs with iptv-org playlists via `tvg-id`. Self-host with Docker for daily refresh.
- epg.pw: quick per-country XMLTV/JSON links, daily refresh. Easiest copy-paste.
- open-epg.com: curated public links plus a guide editor for channel matching.
- Why VLC on Apple TV looks flat: it plays M3U fine but largely ignores `tvg-logo`, `group-title`, and EPG. So no Netflix-style art, categories, or guide. That is a VLC tvOS UI limit, not a playlist defect. Fix = small curated playlists now, native tvOS app later.

## 3. FAST apps (the easy legal live TV)

Pluto TV (cable grid, single-show loop channels), Tubi Live (live + deep on-demand), Plex Live TV (600+ channels), PBS app (local station live feed). All have native Apple TV apps and need no M3U.

## 4. Curator / quarantine design (for the later Swift phase)

- Nightly script (GitHub Action or Mac mini/NAS job): pull iptv-org slices + Free-TV, probe each stream (HTTP + ffprobe), drop geo-blocked/dead to `quarantine.m3u`, publish `curated.m3u` + `guide.xml` + `meta.json` (logo, language, country, category, last-ok).
- tvOS app reads only `curated.m3u` + `meta.json`. New sources appear automatically, dead ones vanish without breaking favorites.
- Playback: TVVLCKit (VLCKit) for odd codecs/containers, AVPlayer first where it can play. Swift/SwiftUI, GRDB/SQLite cache, Siri Remote focus. Reference: MKS-IPTV-App (Swift 6, iOS/macOS/tvOS) and SwiftVLC wrapper.

## 5. Apple TV hub (what we build first)

One folder named Watch Free + Apple TV app Up Next as the cross-app watchlist. Nine installs cover all eight categories: Pluto TV, Tubi, Plex, PBS, Kanopy, Hoopla, YouTube, Spotify, Apple Podcasts. VLC holds 2-4 small M3U slices (news, sports, country, family). Games live in a second folder. Books live on iPhone/web via Libby + Hoopla; Apple TV is not a reader.

See chat handoff for per-category tables and setup steps.

## 6. Free sports on Apple TV (added after follow-up)

Honest baseline: no free legal service carries full NFL/NBA/MLB/NHL live schedules. Free = sports news, replays, niche/international live, selected big events.
- Red Bull TV (tvOS app, free, no ads): live action sports, motorsport, MTB, snow, surf, climbing. Best true-live free sports app.
- DAZN app (tvOS 15+, free download with free tier): FIFA+ football content plus 10+ free linear channels (Red Bull TV, Matchroom, Lacrosse TV, Padel). Premium behind paywall, catalog varies by country.
- Tubi Sports row (already installed): NFL Channel, fubo Sports Network, Stadium, PGA Tour, MLB, Fox Sports programming, selected live Fox events (free account needed for some).
- Pluto TV sports section (already installed): CBS Sports HQ, Fox Sports feeds, beIN Xtra, NFL/combat/motorsport channels. Mostly news, highlights, replays.
- NFL Channel (NFL app + Pluto/Tubi/Plex): 24/7 news, replays, NFL Films. No live games.
- YouTube league channels: NFL/NBA/MLB/NHL/FIFA highlights plus growing live minor-league coverage.
- Antenna + network tuner (e.g. HDHomeRun) into Channels/Plex app: free OTA NFL, college sports, golf, Olympics on CBS/Fox/NBC/ABC. Only path to free live majors.
- iptv-org sports slice via VLC (`.../categories/sports.m3u`): global free-to-air sports streams, uneven quality, some geo-blocked.

## 7. Apple TV players with real guide + search (VLC has neither)

VLC on tvOS plays M3U but ignores EPG, logos, and groups. These tvOS App Store players add the grid guide, search, and favorites. Gotcha: most tvOS players read the guide address from the playlist's `url-tvg` header, so the M3U and XMLTV must be paired. The phase-2 curator publishes that pair.
- UHF: free core, top-rated. Best free starting point.
- IPTVX (tvOS 16+): EPG grid, catch-up, iCloud sync. Free download, paid plans from $3.99/mo.
- iPlayTV: ~$5.99 one-time, Apple TV only, M3U-focused, native feel.
- Smarters Player Lite: free, M3U + Xtream, clean guide.
- GSE Smart IPTV: free/paid tiers, power-user pick.
- Channels app: best guide experience but custom M3U needs Channels DVR Server on a home computer/NAS, 750-channel M3U limit. Server route, not Apple-TV-only.

## 8. Build-vs-buy verdict (user is right, with nuances)

- No single Apple TV app merges public sources, quarantines dead streams, and does Netflix-style discovery. UHF/IPTVX cover playback + guide + search only.
- Closest misses live outside tvOS: TiviMate-style channel health on mobile, Android-only health-tracking players. None merge/curate public sources.
- Upstream already helps: iptv-bot probes every stream daily (online/blocked/timeout/error) and playlists rebuild daily; free-codecs runs its own check. Our curator builds on that instead of starting from zero.
- Proven zero-cost pattern: open-source curators on GitHub Actions + Pages doing health scoring, dead-link retirement, merged EPG, static JSON API. No home server needed.
- Build plan: Layer 1 = curator (scheduled action, publishes curated.m3u + guide.xml + catalog.json). Layer 2 = Swift/SwiftUI tvOS app (discovery UI, AVPlayer + VLCKit playback). Layer 1 is usable immediately in UHF/IPTVX.
