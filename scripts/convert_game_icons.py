#!/usr/bin/env python3
"""
Convert game icons from PNG to WebP.

Usage:
  python3 scripts/convert_game_icons.py

Reads:  Daxelo-Kinrel-App/assets/icons/games/*.png  (1024x1024, 400-700KB each)
Writes: Daxelo-Kinrel-App/assets/icons/games/*.webp (256x256, ~10-30KB each)

The originals are NOT deleted — they're kept in the repo as design source.
The pubspec.yaml asset entries and game_icons.dart paths are updated to
reference .webp instead of .png.

Quality: 88 (lossy). If transparency edges show artifacts, re-run with
quality=100 (lossless) — but lossless WebP at 256x256 is still ~3-5x
smaller than 1024x1024 PNG.
"""

import os
import sys
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
ICONS_DIR = REPO_ROOT / "Daxelo-Kinrel-App" / "assets" / "icons" / "games"

# Target size: 256x256 (3x of ~85px display size = 255px, rounded to 256).
# This covers up to 3x DPR at the display size used in game_icons.dart.
TARGET_SIZE = 256
QUALITY = 88

def main():
    if not ICONS_DIR.exists():
        print(f"FATAL: icons dir not found: {ICONS_DIR}")
        sys.exit(1)

    pngs = sorted(ICONS_DIR.glob("*.png"))
    if not pngs:
        print(f"FATAL: no .png files found in {ICONS_DIR}")
        sys.exit(1)

    print(f"Found {len(pngs)} PNG icons to convert.")
    total_before = 0
    total_after = 0

    for png in pngs:
        webp_path = png.with_suffix(".webp")

        # Open the PNG
        img = Image.open(png)

        # Resize to target size (high-quality LANCZOS resampling)
        if img.size[0] != TARGET_SIZE or img.size[1] != TARGET_SIZE:
            img = img.resize((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)

        # Convert RGBA if the image has transparency
        if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
            img = img.convert("RGBA")
        else:
            img = img.convert("RGB")

        # Save as WebP
        img.save(webp_path, "WEBP", quality=QUALITY, method=6)

        before = png.stat().st_size
        after = webp_path.stat().st_size
        total_before += before
        total_after += after
        reduction = (1 - after / before) * 100
        print(f"  {png.name}: {before // 1024}KB → {after // 1024}KB "
              f"({reduction:.0f}% reduction)")

    print(f"\nTotal: {total_before // 1024}KB → {total_after // 1024}KB "
          f"({(1 - total_after / total_before) * 100:.0f}% reduction)")
    print(f"\nWebP files written to: {ICONS_DIR}")
    print(f"Original PNGs kept as design source (NOT in pubspec assets).")

if __name__ == "__main__":
    main()
