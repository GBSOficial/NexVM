#!/usr/bin/env python3
"""Fails if an L("key") used in Sources/NexVMApp is missing from any .strings table,
if a table has keys the code no longer uses, or if the three tables disagree."""
import re, sys
from pathlib import Path
root = Path(__file__).resolve().parent.parent / "Sources/NexVMApp"
used = set()
for p in root.rglob("*.swift"):
    used |= set(re.findall(r'\bL\("([^"]+)"', p.read_text()))
used |= {"library.count.one", "library.count.other"}  # chosen by a ternary
# keys built dynamically via titleKey properties
for p in root.rglob("*.swift"):
    used |= set(re.findall(r'"((?:guest|state|sidebar|wizard\.step)\.[a-z0-9]+)"', p.read_text()))
tables = {}
for lang in ("en", "pt-BR", "pt-PT"):
    f = root / f"Resources/{lang}.lproj/Localizable.strings"
    tables[lang] = dict(re.findall(r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)";', f.read_text(), re.M))
bad = False
for lang, t in tables.items():
    for k in sorted(used - t.keys()):
        print(f"{lang}: missing {k}"); bad = True
    for k in sorted(t.keys() - used):
        print(f"{lang}: unused {k}")
ref = set(tables["en"])
for lang in ("pt-BR", "pt-PT"):
    for k in sorted(ref ^ set(tables[lang])):
        print(f"{lang}: differs from en: {k}"); bad = True
print("OK" if not bad else "FAILED", f"({len(used)} keys)")
sys.exit(1 if bad else 0)
