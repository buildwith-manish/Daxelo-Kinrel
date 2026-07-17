#!/usr/bin/env python3
"""
Kinrel Cameo — Asset Manifest Validator

Reads MANIFEST.json from the kinrel-cameo/ asset pack, then verifies:
  1. Every expected asset file exists.
  2. Every asset file is non-trivial (>5KB — filters out empty/corrupt PNGs).
  3. Every 1024x1024 asset has the correct canvas dimensions.

Exits with code 0 if all checks pass, 1 otherwise.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required. Install with: pip install pillow", file=sys.stderr)
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent.parent  # → Daxelo-Kinrel/
ASSET_ROOT = REPO_ROOT / "kinrel-cameo"
MANIFEST_PATH = ASSET_ROOT / "MANIFEST.json"

MIN_FILE_SIZE_BYTES = 5 * 1024  # 5 KB


def load_manifest() -> dict:
    if not MANIFEST_PATH.exists():
        print(f"ERROR: manifest not found at {MANIFEST_PATH}", file=sys.stderr)
        sys.exit(2)
    with MANIFEST_PATH.open() as f:
        return json.load(f)


def collect_expected_assets(manifest: dict) -> list[str]:
    """Walk the manifest and collect every expected relative path."""
    expected: set[str] = set()

    # Age stages — file field is just the filename, prefix with dir
    for stage in manifest.get("ageStages", []):
        if "path" in stage:
            expected.add(stage["path"])
        else:
            expected.add(f"age-stages/{stage['file']}")

    # Skin tones
    for tone in manifest.get("skinTones", []):
        if "path" in tone:
            expected.add(tone["path"])
        else:
            expected.add(f"skin-tones/{tone['file']}")

    # Face shapes
    for shape in manifest.get("faceShapes", []):
        if "path" in shape:
            expected.add(shape["path"])
        else:
            expected.add(f"face-shapes/{shape['file']}")

    # Base faces — `path` field is the full relative path (e.g. "base-faces/baby/face_baby_A.png")
    for face in manifest.get("baseFaces", []):
        if "path" in face:
            expected.add(face["path"])
        else:
            expected.add(f"base-faces/{face['file']}")

    # Parts (eyes/nose/mouth/eyebrows/eyelids/pupils/hair-front/middle/back)
    for category, items in manifest.get("parts", {}).items():
        for item in items:
            if "path" in item:
                expected.add(item["path"])
            else:
                expected.add(f"parts/{category}/{item['file']}")

    # Accessories — `path` is full relative path
    for accessory in manifest.get("accessories", []):
        if "path" in accessory:
            expected.add(accessory["path"])
        else:
            expected.add(f"accessories/{accessory['type']}/{accessory['file']}")

    # Clothing
    for category, items in manifest.get("clothing", {}).items():
        for item in items:
            if "path" in item:
                expected.add(item["path"])
            else:
                expected.add(f"clothing/{category}/{item['file']}")

    # Genetics — list of filenames
    for demo in manifest.get("genetics", []):
        if isinstance(demo, dict):
            expected.add(demo.get("path", f"genetics/{demo['file']}"))
        else:
            expected.add(f"genetics/{demo}")

    # Reference — list of filenames
    for ref in manifest.get("reference", []):
        if isinstance(ref, dict):
            expected.add(ref.get("path", f"reference/{ref['file']}"))
        else:
            expected.add(f"reference/{ref}")

    return sorted(expected)


def validate_asset(rel_path: str) -> tuple[bool, str]:
    """Returns (ok, message).

    Image generator sometimes returns JPEG bytes with .png extension — accept
    both true PNG (\\x89PNG) and JPEG (\\xff\\xd8\\xff) magic bytes.
    """
    full = ASSET_ROOT / rel_path
    if not full.exists():
        return False, "MISSING"
    size = full.stat().st_size
    if size < MIN_FILE_SIZE_BYTES:
        return False, f"TOO_SMALL ({size} bytes)"
    # Verify image signature — accept PNG or JPEG
    with full.open("rb") as f:
        sig = f.read(4)
    is_png = sig[:4] == b"\x89PNG"
    is_jpeg = sig[:3] == b"\xff\xd8\xff"
    if not (is_png or is_jpeg):
        return False, f"NOT_IMAGE (sig={sig.hex()})"
    fmt_tag = "PNG" if is_png else "JPEG"
    # Verify dimensions for 1024x1024 face/part assets
    try:
        with Image.open(full) as img:
            w, h = img.size
        # Face parts should be 1024x1024
        if rel_path.startswith(("base-faces/", "parts/", "skin-tones/", "face-shapes/", "accessories/")):
            if (w, h) != (1024, 1024):
                return False, f"WRONG_SIZE {w}x{h} (expected 1024x1024)"
        # Clothing should be 768x1344
        elif rel_path.startswith("clothing/"):
            if (w, h) != (768, 1344):
                return False, f"WRONG_SIZE {w}x{h} (expected 768x1344)"
        # Age stages: 768x1344 (full body) or 1024x1024
        elif rel_path.startswith("age-stages/"):
            if (w, h) not in [(768, 1344), (1024, 1024)]:
                return False, f"WRONG_SIZE {w}x{h}"
        # Reference sheets: any reasonable size (master sheets 1344x768,
        # composite tests are 1024x1024 / 768x1344)
        elif rel_path.startswith("reference/"):
            if w < 512 or h < 512 or w > 4096 or h > 4096:
                return False, f"WRONG_SIZE {w}x{h}"
    except Exception as e:
        return False, f"PIL_ERROR: {e}"
    return True, f"OK {fmt_tag} ({size//1024} KB)"


def main() -> int:
    print(f"=== Kinrel Cameo Manifest Validator ===")
    print(f"Asset root: {ASSET_ROOT}")
    print(f"Manifest:   {MANIFEST_PATH}")
    print()

    manifest = load_manifest()
    expected = collect_expected_assets(manifest)

    print(f"Expected assets: {len(expected)}")
    print()

    failures: list[tuple[str, str]] = []
    for rel in expected:
        ok, msg = validate_asset(rel)
        status = "✓" if ok else "✗"
        print(f"  {status} {rel:<70s} {msg}")
        if not ok:
            failures.append((rel, msg))

    print()
    print(f"=== Summary: {len(expected) - len(failures)}/{len(expected)} passed ===")

    if failures:
        print()
        print("FAILURES:")
        for rel, msg in failures:
            print(f"  - {rel}: {msg}")
        return 1

    print("All assets present and valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
