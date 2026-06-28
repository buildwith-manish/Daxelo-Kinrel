#!/usr/bin/env python3
"""
Extract the 26 most essential relationships from indian_kinship.json
to create a tiny bundled fallback (~142KB).

Run from repo root:
    python3 scripts/create_core_json.py
"""

import json
import os

ESSENTIAL_KEYS = {
    'self', 'father', 'mother', 'son', 'daughter',
    'brother', 'sister', 'elder_brother', 'younger_brother',
    'elder_sister', 'younger_sister', 'husband', 'wife',
    'paternal_grandfather', 'paternal_grandmother',
    'maternal_grandfather', 'maternal_grandmother',
    'fathers_elder_brother', 'fathers_younger_brother',
    'fathers_sister', 'mothers_brother', 'mothers_sister',
    'brothers_son', 'brothers_daughter',
    'sisters_son', 'sisters_daughter',
    'grandson', 'granddaughter',
}

INPUT = 'Daxelo-Kinrel-App/assets/data/indian_kinship.json'
OUTPUT = 'Daxelo-Kinrel-App/assets/data/kinship_core.json'

with open(INPUT) as f:
    data = json.load(f)

core_rels = [r for r in data['relationships'] if r['relationshipKey'] in ESSENTIAL_KEYS]
core_translations = {k: v for k, v in data.get('translations', {}).items() if k in ESSENTIAL_KEYS}

core_json = {
    'version': data.get('version', '5.0.0'),
    'generatedAt': data.get('generatedAt', ''),
    'totalRelationships': len(core_rels),
    'supportedLanguages': data.get('supportedLanguages', []),
    'relationships': core_rels,
    'translations': core_translations,
    '_note': 'Core subset — 26 essential relationships for offline use. Full data downloaded on first launch.',
}

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
with open(OUTPUT, 'w') as f:
    json.dump(core_json, f, ensure_ascii=False, separators=(',', ':'))

size_kb = os.path.getsize(OUTPUT) / 1024
print(f'✅ Created {OUTPUT}')
print(f'   Relationships: {len(core_rels)}')
print(f'   Size: {size_kb:.1f} KB')
