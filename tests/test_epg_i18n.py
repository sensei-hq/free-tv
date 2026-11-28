"""EPG translation: non-Latin titles get English variants via offline models."""
import unittest

from curator.epg_i18n import (
    needs_translation,
    pair_for_title,
    translate_new,
)


class I18nTest(unittest.TestCase):
    def test_detects_non_latin_scripts(self):
        self.assertTrue(needs_translation("סרטים אולימפיים"))
        self.assertTrue(needs_translation("छत्तीसगढ़ की बात"))
        self.assertTrue(needs_translation("Извънземни от древността"))
        self.assertFalse(needs_translation("Morning News"))
        self.assertFalse(needs_translation("883"))
        self.assertFalse(needs_translation(""))

    def test_pair_uses_script_and_country(self):
        self.assertEqual(pair_for_title("סרטים", "IL1"), ("he", "en"))
        self.assertEqual(pair_for_title("छत्तीसगढ़", "IN1"), ("hi", "en"))
        self.assertEqual(pair_for_title("Новини", "BG1"), ("bg", "en"))
        self.assertEqual(pair_for_title("Новини", "RU1"), ("ru", "en"))
        self.assertIsNone(pair_for_title("Новини", "XX1"))
        self.assertIsNone(pair_for_title("Morning News", "US1"))

    def test_memory_avoids_retranslation(self):
        calls = []

        def fake_translate(text, from_code, to_code):
            calls.append(text)
            return f"[{text}]"

        memory = {"he:ידוע": "Known"}
        out = translate_new(["ידוע", "סרטים"], "IL1", memory,
                            fake_translate)
        self.assertEqual(out, {"he:ידוע": "Known",
                               "he:סרטים": "[סרטים]"})
        self.assertEqual(calls, ["סרטים"])
        self.assertEqual(memory["he:סרטים"], "[סרטים]")


if __name__ == "__main__":
    unittest.main()
