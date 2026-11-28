"""Translate non-Latin EPG titles offline (Argos Translate).

Only titles whose dominant script is unreadable to Latin readers are
translated; country hints from guide filenames disambiguate shared
scripts (Cyrillic). A persisted memory means each unique title is
translated once ever.
"""
import re
import sys
import unicodedata

# Script -> from-code, no country needed.
SCRIPT_LANGS = {
    "HEBREW": "he",
    "DEVANAGARI": "hi",
    "GREEK": "el",
    "ARABIC": "ar",
}

# Cyrillic needs a country hint from the guide filename.
CYRILLIC_LANGS = {
    "BG": "bg",
    "RU": "ru",
    "UA": "uk",
    "RS": "sr",
    "BY": "be",
    "MK": "mk",
}

_COUNTRY_RE = re.compile(r"_([A-Z]{2})\d*\.xml")


def dominant_script(text):
    counts = {}
    for char in text:
        if not char.isalpha():
            continue
        try:
            script = unicodedata.name(char).split()[0]
        except ValueError:
            continue
        counts[script] = counts.get(script, 0) + 1
    if not counts:
        return None
    return max(counts, key=counts.get)


def needs_translation(text):
    script = dominant_script(text or "")
    return script is not None and script != "LATIN"


def country_of_guide(url):
    match = _COUNTRY_RE.search(url or "")
    if match:
        return match.group(1)
    bare = re.fullmatch(r"([A-Z]{2})\d*", url or "")
    return bare.group(1) if bare else ""


def pair_for_title(text, guide_name, target="en"):
    """(from, to) model pair, or None when translation is impossible."""
    script = dominant_script(text or "")
    if script is None or script == "LATIN":
        return None
    if script in SCRIPT_LANGS:
        return (SCRIPT_LANGS[script], target)
    if script == "CYRILLIC":
        code = CYRILLIC_LANGS.get(country_of_guide(guide_name))
        return (code, target) if code else None
    return None


def make_translator(memory, targets=("en",)):
    """Offline translator closing over a persistent memory, or None when
    argostranslate is not installed (guide ships untranslated)."""
    try:
        import argostranslate.package as pkg
        import argostranslate.translate as lib
    except ImportError:
        print("argostranslate not installed; skipping guide translation",
              file=sys.stderr)
        return None
    ready = set()

    def ensure(pair):
        if pair in ready:
            return True
        installed = {(p.from_code, p.to_code)
                     for p in pkg.get_installed_packages()}
        if pair not in installed:
            pkg.update_package_index()
            available = pkg.get_available_packages()
            cand = next((p for p in available
                         if (p.from_code, p.to_code) == pair), None)
            if cand is None:
                return False
            cand.install()
        ready.add(pair)
        return True

    def translate(text, url):
        out = {}
        for target in targets:
            pair = pair_for_title(text, url, target)
            if pair is None or not ensure(pair):
                continue
            key = f"{pair[0]}:{text}"
            if key not in memory:
                memory[key] = lib.translate(text, pair[0], pair[1])
            out[target] = memory[key]
        return out

    return translate


def translate_new(texts, guide_name, memory, translate_fn, target="en"):
    """Translate uncached titles; memory maps 'lang:text' -> translation."""
    result = {}
    for text in texts:
        pair = pair_for_title(text, guide_name, target)
        if pair is None:
            continue
        key = f"{pair[0]}:{text}"
        if key not in memory:
            memory[key] = translate_fn(text, pair[0], pair[1])
        result[key] = memory[key]
    return result
