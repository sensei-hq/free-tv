"""Stream health probing over plain HTTP (stdlib only).

Fetches the first bytes of each stream URL with a Range request and
classifies it as online, blocked, timeout, or error. HTML responses are
rejected so channel web pages never pass as playable streams.
"""
import socket
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

USER_AGENT = "FreeTV-Curator/1.0 (+https://github.com/iptv-org/iptv)"
SAMPLE_BYTES = 16384

PLAYLIST_TYPES = {
    "application/vnd.apple.mpegurl",
    "audio/mpegurl",
    "application/x-mpegurl",
}
MEDIA_TYPES = PLAYLIST_TYPES | {
    "video/mp2t",
    "video/mp4",
    "application/mp4",
    "application/octet-stream",
    "binary/octet-stream",
    "application/dash+xml",
    "video/webm",
}


@dataclass
class ProbeResult:
    status: str  # online | blocked | timeout | error
    reason: str


def _is_playlist_url(url):
    return url.split("?", 1)[0].lower().endswith(".m3u8")


def probe_url(url, timeout=20):
    request = Request(
        url,
        headers={"User-Agent": USER_AGENT,
                 "Range": f"bytes=0-{SAMPLE_BYTES - 1}"},
    )
    try:
        with urlopen(request, timeout=timeout) as response:  # noqa: S310
            status = getattr(response, "status", 200)
            content_type = (
                response.headers.get("Content-Type", "").split(";")[0].strip()
            ).lower()
            body = response.read(SAMPLE_BYTES)
    except HTTPError as err:
        if err.code == 403:
            return ProbeResult("blocked", f"http {err.code} forbidden")
        return ProbeResult("error", f"http {err.code} {err.msg or ''}".strip())
    except (socket.timeout, TimeoutError):
        return ProbeResult("timeout", "timed out")
    except URLError as err:
        if isinstance(err.reason, TimeoutError) or "timed out" in str(
            err.reason
        ).lower():
            return ProbeResult("timeout", "timed out")
        return ProbeResult("error", str(err.reason))
    except (ValueError, OSError) as err:
        return ProbeResult("error", str(err))

    if status >= 400:
        return ProbeResult("error", f"http {status}")
    if content_type.startswith("text/html") or body[:15].lower().startswith(
        (b"<!doctype html", b"<html")
    ):
        return ProbeResult("error", "not a media stream (served html)")
    if _is_playlist_url(url) and b"#EXTM3U" not in body:
        return ProbeResult("error", "not a media playlist (no #EXTM3U)")
    if content_type and content_type not in MEDIA_TYPES:
        return ProbeResult("error", f"unexpected content type {content_type}")
    return ProbeResult("online", "")
