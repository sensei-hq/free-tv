"""Parsing, merge/dedupe, and rendering of M3U playlists."""
import unittest

from curator.playlist import parse_m3u, merge_sources, render_m3u


SAMPLE = (
    '#EXTM3U x-tvg-url="http://example.com/a.xml,http://example.com/b.xml"\r\n'
    '#EXTINF:-1 tvg-id="News1.us" tvg-logo="http://img/n1.png" '
    'group-title="News" tvg-country="US",News One\r\n'
    'http://cdn.example.com/n1.m3u8\r\n'
    '#EXTVLCOPT:http-user-agent=Foo\r\n'
    '#EXTINF:-1 tvg-id="Sport1" group-title="Sports",Sport, Live & More\n'
    'https://cdn.example.com/s1.m3u8\n'
    '\n'
    '#EXTINF:-1 tvg-id="NoLogo" group-title="Sports",No Logo\n'
    'https://cdn.example.com/nologo\n'
)


class ParseTest(unittest.TestCase):
    def test_header_epg_urls(self):
        playlist = parse_m3u(SAMPLE)
        self.assertEqual(
            playlist.epg_urls,
            ["http://example.com/a.xml", "http://example.com/b.xml"],
        )

    def test_entry_count_and_fields(self):
        playlist = parse_m3u(SAMPLE)
        self.assertEqual(len(playlist.entries), 3)
        first = playlist.entries[0]
        self.assertEqual(first.name, "News One")
        self.assertEqual(first.url, "http://cdn.example.com/n1.m3u8")
        self.assertEqual(first.tvg_id, "News1.us")
        self.assertEqual(first.logo, "http://img/n1.png")
        self.assertEqual(first.group, "News")
        self.assertEqual(first.country, "US")

    def test_name_may_contain_comma(self):
        playlist = parse_m3u(SAMPLE)
        self.assertEqual(playlist.entries[1].name, "Sport, Live & More")

    def test_crlf_and_lf_mixed(self):
        playlist = parse_m3u(SAMPLE)
        urls = [e.url for e in playlist.entries]
        self.assertNotIn(True, ["\r" in u for u in urls])
        self.assertEqual(len(urls), 3)

    def test_country_from_tvg_id_suffix(self):
        playlist = parse_m3u(SAMPLE)
        self.assertEqual(playlist.entries[0].country, "US")


class MergeTest(unittest.TestCase):
    def test_duplicate_url_keeps_logo_and_merges_sources(self):
        a = parse_m3u(
            '#EXTM3U\n#EXTINF:-1 tvg-id="X" group-title="Sports",X\n'
            "HTTP://cdn.example.com/x.m3u8\n"
        )
        b = parse_m3u(
            '#EXTM3U\n#EXTINF:-1 tvg-id="X" tvg-logo="http://img/x.png" '
            'group-title="Sports",X\nhttp://cdn.example.com/x.m3u8\n'
        )
        merged = merge_sources([("sports", "Sports", a), ("extra", "Sports", b)])
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].logo, "http://img/x.png")
        self.assertEqual(sorted(merged[0].sources), ["extra", "sports"])

    def test_distinct_urls_all_kept(self):
        a = parse_m3u(
            '#EXTM3U\n#EXTINF:-1 group-title="News",A\nhttp://x/a.m3u8\n'
            '#EXTINF:-1 group-title="News",B\nhttp://x/b.m3u8\n'
        )
        merged = merge_sources([("news", "News", a)])
        self.assertEqual(len(merged), 2)


class RenderTest(unittest.TestCase):
    def test_round_trip(self):
        playlist = parse_m3u(SAMPLE)
        merged = merge_sources([("news", "News", playlist)])
        text = render_m3u(
            merged, epg_urls=["http://example.com/a.xml"], group_strategy="keep"
        )
        self.assertIn('#EXTM3U url-tvg="http://example.com/a.xml"', text)
        self.assertIn('group-title="News" tvg-country="US",News One', text)
        reparsed = parse_m3u(text)
        self.assertEqual(len(reparsed.entries), 3)

    def test_category_strategy_overrides_group(self):
        playlist = parse_m3u(SAMPLE)
        merged = merge_sources([("sports", "Sports", playlist)])
        text = render_m3u(merged, epg_urls=[], group_strategy="category")
        self.assertIn('group-title="Sports" tvg-country="US",News One', text)


if __name__ == "__main__":
    unittest.main()
