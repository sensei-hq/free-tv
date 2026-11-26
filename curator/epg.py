"""EPG guide matching: download each candidate guide's channel list and
keep only guides that cover at least one playlist channel. Dead guides
and irrelevant 200MB aggregates never reach the published playlists."""
import gzip
import re
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


def guides_for(entries, guide_ids, min_coverage):
    """Matched guide URLs, or [] when coverage is too thin to justify
    the download cost on the player."""
    ids = {i for i in (normalize_id(e.tvg_id) for e in entries) if i}
    matched = select_guides(ids, guide_ids)
    covered, total = coverage(ids, guide_ids, matched)
    if total and covered / total >= min_coverage:
        return matched
    return []


def select_guides(playlist_ids, guide_ids):
    """Guide URLs covering playlist channels, best coverage first."""
    scored = [(url, len(ids & playlist_ids))
              for url, ids in guide_ids.items()]
    return [url for url, hits in
            sorted(scored, key=lambda t: (-t[1], t[0])) if hits > 0]
