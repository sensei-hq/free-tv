"""EPG guide matching: keep only guides that cover playlist channels."""
import gzip
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import URLError

from curator.epg import (
    coverage,
    extract_channel_ids,
    fetch_ids,
    filter_by_size,
    guide_size,
    guides_for,
    normalize_id,
    select_guides,
)

SAMPLE_XML = (
    b'<?xml version="1.0"?><tv>'
    b'<channel id="5Gold.il"><display-name>5 Gold</display-name></channel>'
    b'<channel id="N1.us"><display-name>News</display-name></channel>'
    b'<programme start="20260101000000 +0000" channel="5Gold.il">'
    b"<title>X</title></programme></tv>"
)


class FakeResponse:
    def __init__(self, body, headers=None):
        self._body = body
        self.headers = headers or {}

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class EpgTest(unittest.TestCase):
    def test_extracts_channel_ids_not_programme_refs(self):
        self.assertEqual(extract_channel_ids(SAMPLE_XML),
                         {"5Gold.il", "N1.us"})

    def test_normalize_strips_quality_suffix(self):
        self.assertEqual(normalize_id("5Gold.il@SD"), "5gold.il")
        self.assertEqual(normalize_id("N1.us"), "n1.us")
        self.assertEqual(normalize_id(""), "")

    def test_fetch_ids_decompresses_gzip(self):
        with patch("curator.epg.urlopen",
                   return_value=FakeResponse(gzip.compress(SAMPLE_XML))):
            self.assertEqual(fetch_ids("http://x/g.xml.gz"),
                             {"5gold.il", "n1.us"})

    def test_fetch_failure_returns_empty(self):
        with patch("curator.epg.urlopen", side_effect=URLError("nope")):
            self.assertEqual(fetch_ids("http://x/g.xml"), set())

    def test_select_guides_keeps_only_covering(self):
        guides = {
            "http://x/sports.xml": {"5gold.il", "other"},
            "http://x/nothing.xml": {"zzz"},
        }
        self.assertEqual(select_guides({"5gold.il"}, guides),
                         ["http://x/sports.xml"])

    def test_select_guides_orders_by_coverage(self):
        guides = {
            "http://x/one.xml": {"a"},
            "http://x/two.xml": {"a", "b"},
        }
        self.assertEqual(select_guides({"a", "b"}, guides),
                         ["http://x/two.xml", "http://x/one.xml"])

    def test_guide_size_reads_content_length(self):
        fake = FakeResponse(b"", {"Content-Length": "12345"})
        with patch("curator.epg.urlopen", return_value=fake) as m:
            self.assertEqual(guide_size("http://x/g.xml.gz"), 12345)
        request = m.call_args[0][0]
        self.assertEqual(request.get_method(), "HEAD")

    def test_guide_size_failure_is_zero(self):
        with patch("curator.epg.urlopen", side_effect=URLError("nope")):
            self.assertEqual(guide_size("http://x/g.xml.gz"), 0)

    def test_coverage_counts_covered_channels(self):
        guides = {"g1": {"a", "b"}, "g2": {"c"}}
        self.assertEqual(coverage({"a", "b", "z"}, guides, ["g1", "g2"]),
                         (2, 3))

    def test_guides_for_drops_thin_coverage(self):
        entries = [SimpleNamespace(tvg_id=n)
                   for n in ["a", "b", "c", "d", "z"]]
        guides = {"g1": {"a"}}
        self.assertEqual(guides_for(entries, guides, 0.25), [])
        self.assertEqual(guides_for(entries, guides, 0.2), ["g1"])

    def test_filter_by_size_drops_only_known_oversized(self):
        sizes = {"small": 100, "huge": 10**9, "unknown": 0}
        with patch("curator.epg.guide_size",
                   side_effect=lambda u: sizes[u]):
            self.assertEqual(
                filter_by_size(["small", "huge", "unknown"], 1000),
                ["small", "unknown"])


if __name__ == "__main__":
    unittest.main()
