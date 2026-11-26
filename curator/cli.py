"""CLI: fetch sources, merge, probe, quarantine, publish outputs."""
import argparse
import concurrent.futures
import json
import os
import re
import sys
from urllib.request import Request, urlopen

from curator.catalog import build_catalog
from curator.playlist import merge_sources, parse_m3u, render_m3u
from curator.probe import USER_AGENT, ProbeResult, probe_url
from curator.quarantine import Tracker


def safe_result(future):
    """Return future.result(), converting any unexpected exception into an
    error probe so one bad stream never aborts the whole run."""
    try:
        return future.result()
    except Exception as err:  # noqa: BLE001 - quarantine, don't crash
        return ProbeResult("error", str(err))


def load_config(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def fetch_text(url, timeout=60):
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=timeout) as response:  # noqa: S310
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "misc"


def write(path, content):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Curate free IPTV sources.")
    parser.add_argument("--config", default="config/sources.json")
    parser.add_argument("--out", default="output")
    parser.add_argument("--state", default="output/state.json")
    parser.add_argument("--limit", type=int, default=0,
                        help="probe only the first N channels (0 = all)")
    parser.add_argument("--no-probe", action="store_true",
                        help="skip health probing")
    parser.add_argument("--max-workers", type=int, default=32)
    parser.add_argument("--timeout", type=int, default=20)
    args = parser.parse_args(argv)

    config = load_config(args.config)
    probe_config = config.get("probe", {})
    max_fails = probe_config.get("max_fails", 2)
    blocklist = config.get("blocklist", [])
    group_strategy = config.get("group_strategy", "category")

    sources = []
    epg_urls = list(config.get("epg_extra", []))
    for source in config.get("sources", []):
        try:
            text = fetch_text(source["url"])
        except Exception as err:  # noqa: BLE001 - one bad source skips
            print(f"skip {source['name']}: {err}", file=sys.stderr)
            continue
        playlist = parse_m3u(text)
        epg_urls.extend(u for u in playlist.epg_urls if u not in epg_urls)
        sources.append((source["name"], source.get("category", ""),
                        playlist))
        print(f"fetched {source['name']}: {len(playlist.entries)} entries")
    if not sources:
        print("no sources fetched, aborting", file=sys.stderr)
        return 1

    merged = merge_sources(sources)
    before = len(merged)
    merged = [e for e in merged
              if not any(b in e.url for b in blocklist)]
    print(f"merged {before} entries, {before - len(merged)} blocklisted, "
          f"{len(merged)} unique")

    if args.limit:
        merged = merged[:args.limit]
        print(f"limited to first {len(merged)} entries")

    probes = {}
    if not args.no_probe:
        with concurrent.futures.ThreadPoolExecutor(
                max_workers=args.max_workers) as pool:
            future_to_url = {
                pool.submit(probe_url, e.url, args.timeout): e.url
                for e in merged
            }
            for future in concurrent.futures.as_completed(future_to_url):
                probes[future_to_url[future]] = safe_result(future)

    tracker = Tracker.load(args.state, max_fails=max_fails)
    catalog = build_catalog(merged, probes, tracker, epg_urls)
    tracker.save(args.state)

    live = [c for c in catalog["channels"] if not c["quarantined"]]
    dead = [c for c in catalog["channels"] if c["quarantined"]]
    by_url = {e.url: e for e in merged}
    live_entries = [by_url[c["url"]] for c in live]
    dead_entries = [by_url[c["url"]] for c in dead]

    write(os.path.join(args.out, "curated.m3u"),
          render_m3u(live_entries, epg_urls, group_strategy))
    write(os.path.join(args.out, "quarantine.m3u"),
          render_m3u(dead_entries, [], group_strategy))
    write(os.path.join(args.out, "catalog.json"),
          json.dumps(catalog, indent=2) + "\n")
    write(os.path.join(args.out, "quarantine.json"),
          json.dumps(dead, indent=2) + "\n")

    categories = {}
    for entry in live_entries:
        categories.setdefault(entry.group or entry.category or "Unsorted",
                              []).append(entry)
    for category, cat_entries in sorted(categories.items()):
        write(os.path.join(args.out, f"{slug(category)}.m3u"),
              render_m3u(cat_entries, epg_urls, group_strategy))

    stats = catalog["stats"]
    print(f"online={stats['online']} quarantined={stats['quarantined']} "
          f"total={stats['total']} categories={len(categories)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
