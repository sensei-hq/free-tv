"""Quarantine state machine: grace failures, quarantine, restore."""
import json
import os
import tempfile
import unittest

from curator.quarantine import Tracker


class TrackerTest(unittest.TestCase):
    def test_first_failure_is_grace_not_quarantine(self):
        tracker = Tracker(max_fails=2)
        entry = tracker.update("http://x/a", "timeout", "timed out")
        self.assertFalse(entry.quarantined)
        self.assertEqual(entry.fails, 1)

    def test_second_failure_quarantines(self):
        tracker = Tracker(max_fails=2)
        tracker.update("http://x/a", "timeout", "timed out")
        entry = tracker.update("http://x/a", "error", "http 500")
        self.assertTrue(entry.quarantined)
        self.assertEqual(entry.reason, "error: http 500")

    def test_success_resets_and_restores(self):
        tracker = Tracker(max_fails=2)
        tracker.update("http://x/a", "timeout", "timed out")
        tracker.update("http://x/a", "error", "http 500")
        entry = tracker.update("http://x/a", "online", "")
        self.assertFalse(entry.quarantined)
        self.assertEqual(entry.fails, 0)
        self.assertTrue(entry.last_ok)

    def test_online_first_seen_is_clean(self):
        tracker = Tracker(max_fails=2)
        entry = tracker.update("http://x/new", "online", "")
        self.assertFalse(entry.quarantined)
        self.assertEqual(entry.fails, 0)

    def test_state_round_trips_through_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "state.json")
            tracker = Tracker(max_fails=2)
            tracker.update("http://x/a", "timeout", "timed out")
            tracker.save(path)
            with open(path, encoding="utf-8") as fh:
                raw = json.load(fh)
            self.assertEqual(raw["http://x/a"]["fails"], 1)
            loaded = Tracker.load(path, max_fails=2)
            entry = loaded.update("http://x/a", "error", "http 500")
            self.assertTrue(entry.quarantined)

    def test_missing_state_file_starts_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            tracker = Tracker.load(os.path.join(tmp, "nope.json"), max_fails=2)
            entry = tracker.update("http://x/a", "online", "")
            self.assertEqual(entry.fails, 0)


if __name__ == "__main__":
    unittest.main()
