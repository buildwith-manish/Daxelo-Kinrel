#!/usr/bin/env python3
"""
v10 — pixel-level diff between scenario 1 (with proximity glow) and
scenario 2 (no proximity glow) to confirm the glow is actually visible.

Outputs:
  - download/v10_visual_pass/diff_01_vs_02.png — pixel diff (red = pixels
    that differ between the two renders, with intensity proportional to
    the magnitude of the difference)
  - download/v10_visual_pass/diff_01_vs_02.json — summary stats
"""

import json
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    print("Installing pillow...")
    import subprocess
    subprocess.check_call(["pip3", "install", "--quiet", "pillow"])
    from PIL import Image, ImageChops

OUT_DIR = Path("/home/z/my-project/download/v10_visual_pass")
S1_PATH = OUT_DIR / "01_default_pitch50_with_proximity_glow.png"
S2_PATH = OUT_DIR / "02_no_family_pin_no_proximity_glow.png"
DIFF_PATH = OUT_DIR / "diff_01_vs_02.png"
STATS_PATH = OUT_DIR / "diff_01_vs_02.json"

img1 = Image.open(S1_PATH).convert("RGB")
img2 = Image.open(S2_PATH).convert("RGB")

# Resize to common size if needed (should be same already, but be defensive)
if img1.size != img2.size:
    w = min(img1.size[0], img2.size[0])
    h = min(img1.size[1], img2.size[1])
    img1 = img1.resize((w, h))
    img2 = img2.resize((w, h))

# Pixel diff
diff = ImageChops.difference(img1, img2)

# Convert to a heatmap — amplify the differences so they're visible
amplified = diff.point(lambda v: min(255, v * 8))
amplified.save(DIFF_PATH)

# Compute stats
import numpy as np
arr1 = np.array(img1).astype(int)
arr2 = np.array(img2).astype(int)
diff_arr = np.abs(arr1 - arr2)
total_pixels = arr1.shape[0] * arr1.shape[1]
diff_pixels = int((diff_arr.sum(axis=2) > 5).sum())  # pixels with >5 unit diff
diff_pct = 100.0 * diff_pixels / total_pixels

# Find the color of the differing pixels (sample the largest-diff pixel)
max_diff_idx = np.unravel_index(diff_arr.sum(axis=2).argmax(), diff_arr.shape[:2])
sample_pixel_img1 = arr1[max_diff_idx[0], max_diff_idx[1]].tolist()
sample_pixel_img2 = arr2[max_diff_idx[0], max_diff_idx[1]].tolist()

stats = {
    "scenario_1": str(S1_PATH),
    "scenario_2": str(S2_PATH),
    "image_size": [int(img1.size[0]), int(img1.size[1])],
    "total_pixels": int(total_pixels),
    "differing_pixels": int(diff_pixels),
    "differing_pct": round(float(diff_pct), 3),
    "max_diff_pixel_location": [int(max_diff_idx[0]), int(max_diff_idx[1])],
    "scenario_1_color_at_max_diff": [int(x) for x in sample_pixel_img1],
    "scenario_2_color_at_max_diff": [int(x) for x in sample_pixel_img2],
    "interpretation": (
        "If proximity glow is visible in scenario 1, the differing pixels "
        "should be clustered around the family-place coordinate (the "
        "center of the viewport) and scenario 1's color at the max-diff "
        "pixel should be more orange/amber (#E8612A-ish) than scenario 2."
    ),
}

STATS_PATH.write_text(json.dumps(stats, indent=2))
print(json.dumps(stats, indent=2))
