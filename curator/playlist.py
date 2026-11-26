"""M3U parsing, multi-source merge/dedupe, and rendering."""
import re
from dataclasses import dataclass, field
from urllib.parse import urlsplit, urlunsplit

_ATTR_RE = re.compile(r'([\w-]+)="([^"]*)"')
_COUNTRY_RE = re.compile(r"\.([a-z]{2})(?:@|$)", re.IGNORECASE)


@dataclass
class Entry:
    name: str
    url: str
    tvg_id: str = ""
    logo: str = ""
    group: str = ""
    country: str = ""
    category: str = ""
    sources: list = field(default_factory=list)


@dataclass
class Playlist:
    epg_urls: list
    entries: list


def _split_extinf(line):
    """Split an EXTINF line into (attrs_text, display_name) on the first
    comma outside quotes, so names may contain commas."""
    body = line.split(":", 1)[1]
    in_quotes = False
    for i, ch in enumerate(body):
        if ch == '"':
            in_quotes = not in_quotes
        elif ch == "," and not in_quotes:
            return body[:i], body[i + 1:]
    return body, ""


def _country_from_tvg_id(tvg_id):
    match = _COUNTRY_RE.search(tvg_id or "")
    return match.group(1).upper() if match else ""


def parse_m3u(text):
    epg_urls = []
    entries = []
    pending = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXTM3U"):
            attrs = dict(_ATTR_RE.findall(line))
            for key in ("x-tvg-url", "url-tvg"):
                if key in attrs:
                    epg_urls.extend(
                        u.strip() for u in attrs[key].split(",") if u.strip()
                    )
        elif line.startswith("#EXTINF"):
            attrs_text, name = _split_extinf(line)
            attrs = dict(_ATTR_RE.findall(attrs_text))
            tvg_id = attrs.get("tvg-id", "")
            pending = Entry(
                name=name.strip(),
                url="",
                tvg_id=tvg_id,
                logo=attrs.get("tvg-logo", ""),
                group=attrs.get("group-title", ""),
                country=attrs.get("tvg-country", "")
                or _country_from_tvg_id(tvg_id),
            )
        elif line.startswith("#") or pending is None:
            continue
        else:
            pending.url = line
            entries.append(pending)
            pending = None
    return Playlist(epg_urls=list(dict.fromkeys(epg_urls)), entries=entries)


def normalize_url(url):
    try:
        parts = urlsplit(url.strip())
        return urlunsplit(
            (parts.scheme.lower(), parts.netloc.lower(), parts.path,
             parts.query, parts.fragment)
        )
    except ValueError:
        return url.strip()


def merge_sources(sources):
    """Merge [(name, category, Playlist)] into deduped entries by stream URL.
    Duplicates fill in missing metadata and record every source name."""
    merged = {}
    for name, category, playlist in sources:
        for entry in playlist.entries:
            if not entry.url:
                continue
            key = normalize_url(entry.url)
            if key in merged:
                keep = merged[key]
                for attr in ("tvg_id", "logo", "group", "country"):
                    if not getattr(keep, attr) and getattr(entry, attr):
                        setattr(keep, attr, getattr(entry, attr))
                if name not in keep.sources:
                    keep.sources.append(name)
            else:
                entry.category = category or ""
                entry.sources = [name]
                merged[key] = entry
    return list(merged.values())


def _escape(value):
    return (value or "").replace('"', "'")


def render_m3u(entries, epg_urls, group_strategy="category"):
    lines = []
    if epg_urls:
        joined = ",".join(epg_urls)
        lines.append(f'#EXTM3U url-tvg="{joined}" x-tvg-url="{joined}"')
    else:
        lines.append("#EXTM3U")
    for entry in entries:
        if group_strategy == "category":
            group = entry.category or entry.group
        else:
            group = entry.group or entry.category
        attrs = f'tvg-id="{_escape(entry.tvg_id)}"'
        if entry.logo:
            attrs += f' tvg-logo="{_escape(entry.logo)}"'
        if group:
            attrs += f' group-title="{_escape(group)}"'
        if entry.country:
            attrs += f' tvg-country="{_escape(entry.country)}"'
        lines.append(f"#EXTINF:-1 {attrs},{entry.name}")
        lines.append(entry.url)
    return "\n".join(lines) + "\n"
