#!/usr/bin/env python3
"""
create_core_json.py

Creates a tiny kinship_core.json (~200-300KB) from the full
indian_kinship.json (55MB). This core file is bundled in the APK
as an instant offline fallback before the full JSON downloads from
GitHub Releases.

Selection criteria:
  - generation in [-2, -1, 0, 1, 2] (core + immediate family)
  - relationshipCategory in ['core', 'paternal', 'maternal', 'sibling',
    'offspring', 'spouse', 'grandparent', 'in_law', 'step']
  - Includes chainRules, inverseKey, graphDisplay for each entry
  - Includes translations for all selected entries

Target: ~200-300 core entries, <300KB file size

Usage:
    python scripts/create_core_json.py <indian_kinship.json> <kinship_core.json>
"""

import json
import sys
import os

INPUT = sys.argv[1] if len(sys.argv) > 1 else "indian_kinship.json"
OUTPUT = sys.argv[2] if len(sys.argv) > 2 else "kinship_core.json"

# Generations to include (core + immediate family only)
INCLUDED_GENERATIONS = {-2, -1, 0, 1, 2}

# Categories to include — only the most essential
INCLUDED_CATEGORIES = {
    'core', 'paternal', 'maternal', 'sibling', 'offspring',
    'spouse', 'grandparent', 'in_law', 'step',
}

# Only include entries with path length 1 (single-step relationships like
# "father", "brother", "son" — NOT compound keys like "fathers_elder_brother")
# This drastically reduces the count from 5158 to ~63 core entries
MAX_PATH_LENGTH = 1

# Additionally, always include these critical compound keys that are
# commonly needed for chain resolution
ALWAYS_INCLUDE_KEYS = {
    'fathers_elder_brother', 'fathers_younger_brother', 'fathers_sister',
    'fathers_sisters_husband', 'fathers_elder_brothers_wife',
    'fathers_younger_brothers_wife',
    'mothers_brother', 'mothers_sister', 'mothers_brothers_wife',
    'mothers_sisters_husband',
    'paternal_grandfather', 'paternal_grandmother',
    'maternal_grandfather', 'maternal_grandmother',
    'husbands_father', 'husbands_mother',
    'wifes_father', 'wifes_mother',
    'husbands_elder_brother', 'husbands_younger_brother', 'husbands_sister',
    'wifes_brother', 'wifes_sister',
    'sons_wife', 'daughters_husband',
    'brothers_son', 'brothers_daughter',
    'sisters_son', 'sisters_daughter',
    'sons_son', 'sons_daughter',
    'daughters_son', 'daughters_daughter',
}


def main():
    if not os.path.exists(INPUT):
        print(f"ERROR: Input file not found: {INPUT}")
        sys.exit(1)

    input_size = os.path.getsize(INPUT)
    print(f"Input:  {INPUT} ({input_size / 1024 / 1024:.2f} MB)")

    with open(INPUT, 'r', encoding='utf-8') as f:
        data = json.load(f)

    all_rels = data.get('relationships', [])
    all_translations = data.get('translations', {})
    print(f"Total relationships in source: {len(all_rels)}")

    # Filter relationships
    core_rels = []
    core_keys = set()

    for rel in all_rels:
        gen = rel.get('generation', 0)
        cat = rel.get('relationshipCategory', '')
        key = rel.get('relationshipKey', '')
        path = rel.get('relationshipPath', [])
        path_len = len(path) if path else 1

        # Always include critical compound keys
        if key in ALWAYS_INCLUDE_KEYS:
            core_rels.append(rel)
            core_keys.add(key)
            continue

        # For non-compound keys, include only if:
        # - generation is in range
        # - category is included
        # - path length is 1 (single-step relationship)
        if gen not in INCLUDED_GENERATIONS:
            continue
        if cat not in INCLUDED_CATEGORIES:
            continue
        if path_len > MAX_PATH_LENGTH:
            continue

        core_rels.append(rel)
        core_keys.add(key)

    print(f"Core relationships selected: {len(core_rels)}")

    # Filter translations to only include core keys
    core_translations = {}
    for key, langs in all_translations.items():
        if key in core_keys:
            core_translations[key] = langs

    print(f"Core translations: {len(core_translations)} keys")

    # Build output JSON
    output = {
        'version': data.get('version', '5.0.0-core'),
        'generatedAt': data.get('generatedAt', ''),
        'totalRelationships': len(core_rels),
        'supportedLanguages': data.get('supportedLanguages', []),
        'engineVersion': data.get('engineVersion', '2.0.0'),
        'features': data.get('features', {}),
        'isCoreFallback': True,
        'note': 'This is a reduced core dataset. Download the full indian_kinship.json for all 5363 relationships.',
        'translations': core_translations,
        'relationships': core_rels,
    }

    # Write output
    with open(OUTPUT, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=True, indent=1)

    output_size = os.path.getsize(OUTPUT)
    print()
    print(f"Output: {OUTPUT} ({output_size / 1024:.1f} KB)")
    print(f"Compression: {input_size / output_size:.1f}x smaller")
    print(f"Relationships: {len(core_rels)} / {len(all_rels)} ({len(core_rels)/len(all_rels)*100:.1f}%)")

    # Verify chainRules are present
    chain_count = sum(1 for r in core_rels if r.get('chainRules'))
    print(f"Entries with chainRules: {chain_count} / {len(core_rels)}")

    # Sample verification
    father = next((r for r in core_rels if r['relationshipKey'] == 'father'), None)
    if father:
        print(f"Sample (father):")
        print(f"  chainRules count: {len(father.get('chainRules', []))}")
        print(f"  inverseKey: {father.get('inverseKey')}")
        print(f"  graphDisplay: {father.get('graphDisplay', {}).get('edgeColor')}")


if __name__ == '__main__':
    main()
