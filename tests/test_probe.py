"""Stream health probing with mocked HTTP (no network in tests)."""
import io
import socket
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from curator.probe import probe_url


class FakeResponse:
    def __init__(self, status=200, content_type="application/octet-stream",
                 body=b"#EXTM3U\n#EXT-X-VERSION:3\n"):
        self.status = status
        self.headers = {"Content-Type": content_type}
        self._body = body

    def read(self, n=-1):
        return self._body[:n] if n != -1 else self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _patch_open(side_effect=None, return_value=None):
    return patch("curator.probe.urlopen",
                 side_effect=side_effect, return_value=return_value)


class ProbeTest(unittest.TestCase):
    def test_online_m3u8(self):
        with _patch_open(return_value=FakeResponse()) as m:
            result = probe_url("http://x/a.m3u8", timeout=5)
        self.assertEqual(result.status, "online")
        request = m.call_args[0][0]
        self.assertIn("Range", request.headers)
        self.assertIn("User-agent", request.headers)

    def test_html_page_is_not_a_stream(self):
        fake = FakeResponse(content_type="text/html",
                            body=b"<html>twitch page</html>")
        with _patch_open(return_value=fake):
            result = probe_url("https://www.twitch.tv/somechannel", timeout=5)
        self.assertEqual(result.status, "error")
        self.assertIn("media", result.reason)

    def test_m3u8_without_playlist_marker_is_error(self):
        fake = FakeResponse(content_type="application/octet-stream",
                            body=b"<!DOCTYPE html>nope")
        with _patch_open(return_value=fake):
            result = probe_url("http://x/a.m3u8", timeout=5)
        self.assertEqual(result.status, "error")

    def test_403_is_blocked(self):
        err = HTTPError("http://x/a.m3u8", 403, "Forbidden", {}, None)
        with _patch_open(side_effect=err):
            result = probe_url("http://x/a.m3u8", timeout=5)
        self.assertEqual(result.status, "blocked")

    def test_404_is_error(self):
        err = HTTPError("http://x/a.m3u8", 404, "Not Found", {}, None)
        with _patch_open(side_effect=err):
            result = probe_url("http://x/a.m3u8", timeout=5)
        self.assertEqual(result.status, "error")

    def test_timeout(self):
        with _patch_open(side_effect=socket.timeout("timed out")):
            result = probe_url("http://x/a.m3u8", timeout=1)
        self.assertEqual(result.status, "timeout")

    def test_url_error(self):
        with _patch_open(side_effect=URLError("conn refused")):
            result = probe_url("http://x/a.m3u8", timeout=5)
        self.assertEqual(result.status, "error")


if __name__ == "__main__":
    unittest.main()
