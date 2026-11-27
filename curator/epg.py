"""EPG guide matching: download each candidate guide's channel list and
keep only guides that cover at least one playlist channel. Dead guides
and irrelevant 200MB aggregates never reach the published playlists."""
import gzip
import re
import xml.etree.ElementTree as ET
from urllib.request import Request, urlopen

from curator.probe import USER_AGENT

_CHANNEL_RE = re.compile(rb'<channel\s[^>]*?\bid="([^"]+)"')


def extract_channel_ids(xml):
    """Channel ids from an XMLTV document (programme refs excluded)."""
    return {m.decode("utf-8", "replace") for m in _CHANNEL_RE.findall(xml)}


def normalize_id(tvg_id):
    """Lowercase id without any @quality suffix, for fuzzy matching."""
    return (tvg_id or "").split("@")[0].strip().lower()


def fetch_ids(url, timeout=60):
    """Normalized channel ids of one guide URL, or empty set on any failure."""
    try:
        request = Request(url, headers={"User-Agent": USER_AGENT})
        with urlopen(request, timeout=timeout) as response:  # noqa: S310
            body = response.read()
    except Exception:  # noqa: BLE001 - dead guide means no match
        return set()
    if url.endswith(".gz"):
        try:
            body = gzip.decompress(body)
        except (OSError, EOFError):
            return set()
    try:
        return {i for i in (normalize_id(x) for x in
                            extract_channel_ids(body)) if i}
    except Exception:  # noqa: BLE001 - unparsable guide means no match
        return set()


def guide_size(url, timeout=20):
    """Guide file size in bytes via HEAD, or 0 when unknown."""
    try:
        request = Request(url, headers={"User-Agent": USER_AGENT},
                          method="HEAD")
        with urlopen(request, timeout=timeout) as response:  # noqa: S310
            return int(response.headers.get("Content-Length") or 0)
    except Exception:  # noqa: BLE001 - unknown size, fetch decides
        return 0


def filter_by_size(urls, max_bytes):
    """Drop guides known to exceed max_bytes; unknown sizes pass through."""
    return [u for u in urls
            if (s := guide_size(u)) == 0 or s <= max_bytes]


def coverage(playlist_ids, guide_ids, matched):
    """(covered, total) channels with at least one matched guide."""
    covered_ids = set()
    for url in matched:
        covered_ids |= guide_ids.get(url, set())
    return len(playlist_ids & covered_ids), len(playlist_ids)


def build_epg_index(guide_ids):
    """Invert guide->ids into channel-id->[guide urls], skipping dead
    guides. Lets players fetch only guides covering visible channels."""
    index = {}
    for url, ids in guide_ids.items():
        for channel_id in ids:
            index.setdefault(channel_id, []).append(url)
    for urls in index.values():
        urls.sort()
    return index


def _strip_ns(tag):
    return tag.split("}", 1)[-1] if "}" in tag else tag


def build_merged_guide(guide_bodies, wanted_ids):
    """Merge programmes for wanted channel ids across guides into one
    XMLTV document. Broken guides are skipped silently."""
    tv = ET.Element("tv")
    seen_channels = set()
    for body in guide_bodies.values():
        try:
            root = ET.fromstring(body)
        except ET.ParseError:
            continue
        for channel in root.iter():
            if _strip_ns(channel.tag) != "channel":
                continue
            cid = channel.get("id", "")
            if normalize_id(cid) not in wanted_ids:
                continue
            if cid not in seen_channels:
                seen_channels.add(cid)
                tv.append(channel)
        for programme in root.iter():
            if _strip_ns(programme.tag) != "programme":
                continue
            if normalize_id(programme.get("channel", "")) in wanted_ids:
                tv.append(programme)
    return ET.tostring(tv, encoding="utf-8", xml_declaration=True)


def guides_for(entries, guide_ids, min_coverage):
    """Matched guide URLs, or [] when coverage is too thin to justify
    the download cost on the player."""
    ids = {i for i in (normalize_id(e.tvg_id) for e in entries) if i}
    matched = select_guides(ids, guide_ids)
    covered, total = coverage(ids, guide_ids, matched)
    if total and covered / total >= min_coverage:
        return matched
    return []


def fetch_guide_body(url, timeout=120):
    """Raw (decompressed) bytes of one guide, or b"" on any failure."""
    try:
        request = Request(url, headers={"User-Agent": USER_AGENT})
        with urlopen(request, timeout=timeout) as response:  # noqa: S310
            body = response.read()
    except Exception:  # noqa: BLE001 - dead guide, skip it
        return b""
    if url.endswith(".gz"):
        try:
            return gzip.decompress(body)
        except (OSError, EOFError):
            return b""
    return body


def fetch_guide_bodies(urls, max_workers):
    """Download candidate guides concurrently; failures drop out."""
    import concurrent.futures
    bodies = {}
    with concurrent.futures.ThreadPoolExecutor(
            max_workers=max_workers) as pool:
        future_to_url = {pool.submit(fetch_guide_body, url): url
                         for url in urls}
        for future in concurrent.futures.as_completed(future_to_url):
            try:
                body = future.result()
            except Exception:  # noqa: BLE001 - dead guide, skip it
                continue
            if body:
                bodies[future_to_url[future]] = body
    return bodies


def select_guides(playlist_ids, guide_ids):
    """Guide URLs covering playlist channels, best coverage first."""
    scored = [(url, len(ids & playlist_ids))
              for url, ids in guide_ids.items()]
    return [url for url, hits in
            sorted(scored, key=lambda t: (-t[1], t[0])) if hits > 0]
