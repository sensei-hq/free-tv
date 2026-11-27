"""EPG index: map each channel id to the guides covering it."""
import unittest

from curator.epg import build_epg_index


class EpgIndexTest(unittest.TestCase):
    def test_inverts_guide_to_channels(self):
        guide_ids = {
            "http://x/uk.xml": {"bbc1", "itv1"},
            "http://x/us.xml": {"itv1", "cnn"},
        }
        index = build_epg_index(guide_ids)
        self.assertEqual(index["bbc1"], ["http://x/uk.xml"])
        self.assertEqual(sorted(index["itv1"]),
                         ["http://x/uk.xml", "http://x/us.xml"])
        self.assertEqual(index["cnn"], ["http://x/us.xml"])

    def test_empty_guides_contribute_nothing(self):
        index = build_epg_index({"http://x/dead.xml": set()})
        self.assertEqual(index, {})


if __name__ == "__main__":
    unittest.main()
