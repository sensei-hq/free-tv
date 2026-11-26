# Checkpoint: playlists live, app CI pending

Slice: free-tv Layers 1+2. Repo: sensei-hq/free-tv (public).
Done: curator green in CI, Pages live with 5,785 channels (3,856 online
first run); tvOS app v1 pushed (shelves, search, favorites, AVPlayer).
Remains: app CI result (core tests + tvOS build), UHF test by user.
Next command: `gh run view 45861189525 --repo sensei-hq/free-tv`.
Live: https://sensei-hq.github.io/free-tv/curated.m3u (+ sports.m3u,
news.m3u, catalog.json). Quarantine fills on 2nd scheduled run.
Open questions: user's country slice; strict-probe false positives.
Known-broken: none. (/sensei:checkpoint unavailable in this runtime.)
