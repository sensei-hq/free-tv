"""Merged guide.xml: programmes for our channels only."""
import unittest
import xml.etree.ElementTree as ET

from curator.epg import build_merged_guide

SAMPLE = b"""<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="bbc1"><display-name>BBC One</display-name></channel>
  <channel id="zzz"><display-name>Other</display-name></channel>
  <programme start="20260101080000 +0000" stop="20260101090000 +0000" channel="bbc1">
    <title>Morning News</title><desc>Headlines.</desc>
  </programme>
  <programme start="20260101080000 +0000" stop="20260101090000 +0000" channel="zzz">
    <title>Other Show</title>
  </programme>
</tv>
"""


class MergedGuideTest(unittest.TestCase):
    def test_keeps_only_wanted_channels(self):
        out = build_merged_guide({"http://x/g.xml": SAMPLE}, {"bbc1"})
        root = ET.fromstring(out)
        ids = [c.get("id") for c in root.findall("channel")]
        self.assertEqual(ids, ["bbc1"])
        titles = [t.text for t in root.findall("programme/title")]
        self.assertEqual(titles, ["Morning News"])

    def test_merges_across_guides(self):
        other = SAMPLE.replace(b"bbc1", b"cnn").replace(
            b"Morning News", b"News Hour")
        out = build_merged_guide({"http://x/a.xml": SAMPLE,
                                  "http://x/b.xml": other},
                                 {"bbc1", "cnn"})
        root = ET.fromstring(out)
        self.assertEqual(len(root.findall("channel")), 2)
        self.assertEqual(len(root.findall("programme")), 2)

    def test_empty_when_nothing_matches(self):
        out = build_merged_guide({"http://x/g.xml": SAMPLE}, {"nope"})
        root = ET.fromstring(out)
        self.assertEqual(len(root.findall("channel")), 0)
        self.assertEqual(len(root.findall("programme")), 0)

    def test_lang_variants_appended(self):
        out = build_merged_guide(
            {"http://x/g.xml": SAMPLE}, {"bbc1"},
            translate=lambda text, url: {"en": f"EN:{text}"})
        root = ET.fromstring(out)
        titles = [(t.text, t.get("lang"))
                  for t in root.findall("programme/title")]
        self.assertEqual(titles, [("Morning News", None),
                                  ("EN:Morning News", "en")])

    def test_broken_guide_is_skipped(self):
        out = build_merged_guide({"http://x/bad.xml": b"not xml {{{",
                                  "http://x/g.xml": SAMPLE},
                                 {"bbc1"})
        root = ET.fromstring(out)
        self.assertEqual(len(root.findall("programme")), 1)


if __name__ == "__main__":
    unittest.main()
