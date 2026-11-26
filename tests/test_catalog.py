"""Catalog JSON: facets per channel plus run stats."""
import unittest

from curator.catalog import build_catalog
from curator.playlist import parse_m3u, merge_sources
from curator.probe import ProbeResult
from curator.quarantine import Tracker


SAMPLE = (
    '#EXTM3U x-tvg-url="http://example.com/g.xml"\n'
    '#EXTINF:-1 tvg-id="N1.us" tvg-logo="http://img/n.png" '
    'group-title="News" tvg-country="US",News One\n'
    "http://cdn.example.com/n1.m3u8\n"
    '#EXTINF:-1 tvg-id="S1" group-title="Sports",Sport One\n'
    "http://cdn.example.com/s1.m3u8\n"
)


def _merged():
    playlist = parse_m3u(SAMPLE)
    return merge_sources([("mix", "Mix", playlist)])


class CatalogTest(unittest.TestCase):
    def test_entry_facets(self):
        merged = _merged()
        probes = {
            "http://cdn.example.com/n1.m3u8": ProbeResult("online", ""),
            "http://cdn.example.com/s1.m3u8": ProbeResult("online", ""),
        }
        catalog = build_catalog(merged, probes, Tracker(max_fails=2),
                                ["http://example.com/g.xml"])
        by_name = {c["name"]: c for c in catalog["channels"]}
        news = by_name["News One"]
        self.assertEqual(news["logo"], "http://img/n.png")
        self.assertEqual(news["tvg_id"], "N1.us")
        self.assertEqual(news["country"], "US")
        self.assertEqual(news["sources"], ["mix"])
        self.assertEqual(news["status"], "online")
        self.assertFalse(news["quarantined"])

    def test_stats_and_quarantine_flag(self):
        merged = _merged()
        tracker = Tracker(max_fails=1)
        probes = {
            "http://cdn.example.com/n1.m3u8": ProbeResult("online", ""),
            "http://cdn.example.com/s1.m3u8": ProbeResult("error", "http 500"),
        }
        catalog = build_catalog(merged, probes, tracker,
                                ["http://example.com/g.xml"])
        self.assertEqual(catalog["stats"]["total"], 2)
        self.assertEqual(catalog["stats"]["online"], 1)
        self.assertEqual(catalog["stats"]["quarantined"], 1)
        self.assertEqual(catalog["epg_urls"], ["http://example.com/g.xml"])
        by_name = {c["name"]: c for c in catalog["channels"]}
        self.assertTrue(by_name["Sport One"]["quarantined"])

    def test_category_falls_back_to_slice(self):
        merged = _merged()
        probes = {e.url: ProbeResult("online", "") for e in merged}
        catalog = build_catalog(merged, probes, Tracker(max_fails=2), [])
        by_name = {c["name"]: c for c in catalog["channels"]}
        self.assertEqual(by_name["News One"]["category"], "News")
        self.assertEqual(by_name["Sport One"]["category"], "Sports")


if __name__ == "__main__":
    unittest.main()
