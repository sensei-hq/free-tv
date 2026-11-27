"""CLI: fetch sources, merge, probe, quarantine, publish outputs."""
import argparse
import concurrent.futures
import json
import os
import re
import sys
from urllib.request import Request, urlopen

from curator.catalog import build_catalog
from curator.epg import (
    build_epg_index,
    build_merged_guide,
    coverage,
    fetch_ids,
    fetch_guide_bodies,
    fetch_guide_body,
    filter_by_size,
    guides_for,
    normalize_id,
    select_guides,
)
from curator.playlist import merge_sources, parse_m3u, render_m3u
from curator.probe import USER_AGENT, ProbeResult, probe_url
from curator.quarantine import Tracker


def playlist_ids(entries):
    return {i for i in (normalize_id(e.tvg_id) for e in entries) if i}


def match_guides(epg_urls, max_workers, max_bytes):
    """Fetch each fitting guide's channel list (empty set if dead)."""
    fitting = filter_by_size(epg_urls, max_bytes)
    print(f"guides fitting size budget: {len(fitting)}/{len(epg_urls)}")
    guide_ids = {}
    with concurrent.futures.ThreadPoolExecutor(
            max_workers=max_workers) as pool:
        future_to_url = {pool.submit(fetch_ids, url): url
                         for url in fitting}
        for future in concurrent.futures.as_completed(future_to_url):
            url = future_to_url[future]
            try:
                guide_ids[url] = future.result()
            except Exception:  # noqa: BLE001 - dead guide means no match
                guide_ids[url] = set()
    return guide_ids


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
    parser.add_argument("--no-epg", action="store_true",
                        help="skip guide matching (no guide headers)")
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

    max_bytes = config.get("epg_max_mb", 8) * 1024 * 1024
    if args.no_epg:
        guide_ids = {}
    else:
        guide_ids = match_guides(epg_urls, args.max_workers, max_bytes)
    matched_global = select_guides(playlist_ids(merged), guide_ids)
    print(f"guides matched: {len(matched_global)}, channels covered: "
          f"{coverage(playlist_ids(merged), guide_ids, matched_global)}")

    tracker = Tracker.load(args.state, max_fails=max_fails)
    catalog = build_catalog(merged, probes, tracker, matched_global)
    tracker.save(args.state)

    live = [c for c in catalog["channels"] if not c["quarantined"]]
    dead = [c for c in catalog["channels"] if c["quarantined"]]
    by_url = {e.url: e for e in merged}
    live_entries = [by_url[c["url"]] for c in live]
    dead_entries = [by_url[c["url"]] for c in dead]

    min_coverage = config.get("epg_min_coverage", 0.25)
    write(os.path.join(args.out, "curated.m3u"),
          render_m3u(live_entries,
                     guides_for(live_entries, guide_ids, min_coverage),
                     group_strategy))
    write(os.path.join(args.out, "quarantine.m3u"),
          render_m3u(dead_entries, [], group_strategy))
    write(os.path.join(args.out, "catalog.json"),
          json.dumps(catalog, indent=2) + "\n")
    write(os.path.join(args.out, "quarantine.json"),
          json.dumps(dead, indent=2) + "\n")
    write(os.path.join(args.out, "epg-index.json"),
          json.dumps(build_epg_index(guide_ids), indent=2) + "\n")
    if matched_global and not args.no_epg:
        bodies = fetch_guide_bodies(matched_global, args.max_workers)
        guide_xml = build_merged_guide(
            bodies, playlist_ids(merged))
        guide_path = os.path.join(args.out, "guide.xml")
        os.makedirs(os.path.dirname(guide_path) or ".", exist_ok=True)
        with open(guide_path, "wb") as fh:
            fh.write(guide_xml)
        print(f"guide.xml: {len(guide_xml) / 1e6:.1f} MB from "
              f"{len(bodies)} guides")

    categories = {}
    for entry in live_entries:
        categories.setdefault(entry.group or entry.category or "Unsorted",
                              []).append(entry)
    for category, cat_entries in sorted(categories.items()):
        matched = guides_for(cat_entries, guide_ids, min_coverage)
        write(os.path.join(args.out, f"{slug(category)}.m3u"),
              render_m3u(cat_entries, matched, group_strategy))

    stats = catalog["stats"]
    print(f"online={stats['online']} quarantined={stats['quarantined']} "
          f"total={stats['total']} categories={len(categories)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
