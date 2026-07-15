#!/usr/bin/env python3
"""P8.1 HARD GATE 1: Count kinship languages in kinship_core.json."""
import json
import sys

with open('assets/data/kinship_core.json') as f:
    data = json.load(f)

langs = data.get('supportedLanguages', [])
count = len(langs)
print(f"Kinship languages: {count}")
print(f"Languages: {langs}")

if count < 9:
    print(f"FAIL: Expected >= 9 languages, got {count}")
    sys.exit(1)

print(f"PASS: {count} languages >= 9")
