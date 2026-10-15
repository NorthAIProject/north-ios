#!/usr/bin/env python3
"""Fail when a string catalog has a key without a translation in a shipped language.

    python3 scripts/check-translations.py

Xcode adds a key to a catalog the moment code uses it, with no translation; the
app then shows English in every other language and nothing fails. Run this
after adding copy (and in CI) so an untranslated key is a red line instead.

A key marked "shouldTranslate": false in the catalog is skipped, as is a key
whose English is only format specifiers and punctuation ("%@", "%1$@ %2$@").
"""
import glob
import json
import re
import sys

LANGUAGES = ["es", "pt-PT", "pt-BR"]
CATALOGS = [
    "khepri/Resources/*.xcstrings",
    "KhepriWidgets/*.xcstrings",
    "KhepriShare/*.xcstrings",
    "NorthKit/Sources/*/Resources/*.xcstrings",
]
NOTHING_TO_TRANSLATE = re.compile(r"^[\s%@\d$lld.·:,()/–—+-]*$")


def translated(entry, language):
    unit = entry.get("localizations", {}).get(language, {})
    if "stringUnit" in unit:
        return unit["stringUnit"].get("state") == "translated" and unit["stringUnit"].get("value", "").strip() != ""
    # App Shortcut phrases: a set of spoken variants.
    if "stringSet" in unit:
        values = unit["stringSet"].get("values", [])
        return unit["stringSet"].get("state") == "translated" and values and all(v.strip() for v in values)
    # Plural or device variations: every variation must be translated.
    variations = unit.get("variations")
    if not variations:
        return False
    return all(
        v.get("stringUnit", {}).get("state") == "translated"
        for kind in variations.values()
        for v in kind.values()
    )


def main():
    missing = []
    for pattern in CATALOGS:
        for path in sorted(glob.glob(pattern)):
            catalog = json.load(open(path, encoding="utf-8"))
            for key, entry in catalog.get("strings", {}).items():
                if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
                    continue
                if NOTHING_TO_TRANSLATE.match(key):
                    continue
                for language in LANGUAGES:
                    if not translated(entry, language):
                        missing.append(f"{path}: {language}: {key!r}")
    for line in missing:
        print(line)
    if missing:
        print(f"\n{len(missing)} untranslated entries", file=sys.stderr)
        return 1
    print("every catalog key is translated in", ", ".join(LANGUAGES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
