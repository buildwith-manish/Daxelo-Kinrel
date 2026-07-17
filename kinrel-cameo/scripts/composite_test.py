#!/usr/bin/env python3
"""
Kinrel Cameo — Composite Coherence Test

Stacks modular PNG layers (base-face + eyes + nose + mouth + hair-back +
hair-middle + hair-front) using chroma-key background removal, then saves
the resulting composite as a PNG for visual review.

Used by:
  - CI (composite-coherence job) to upload a visual regression artifact on
    every PR touching kinrel-cameo/**
  - Local devs running `python composite_test.py` to sanity-check that
    newly generated assets still stack coherently

The chroma-key algorithm samples the top-left 10x10 corner of each PNG,
treats that color as the background, and removes all pixels within
`--tolerance` RGB units of it. This matches the algorithm the Flutter
CameoLayeredPainter uses at runtime.

Usage:
  python composite_test.py \\
    --asset-root kinrel-cameo \\
    --output-dir /tmp/composite-out \\
    --faces base-faces/young-adult/face_ya_male_A.png \\
             base-faces/senior/face_sr_male_A.png

If --faces is omitted, runs a default set of 4 faces covering young-adult
male/female, senior, and baby.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow required. Install: pip install pillow", file=sys.stderr)
    sys.exit(2)


# Default faces to composite if --faces not provided
DEFAULT_FACES = [
    "base-faces/young-adult/face_ya_male_A.png",
    "base-faces/young-adult/face_ya_female_A.png",
    "base-faces/senior/face_sr_male_A.png",
    "base-faces/baby/face_baby_A.png",
]

# Default layer stack (bottom → top) for head-only composite
# All paths relative to asset-root
DEFAULT_LAYERS = [
    # (layer_name, relative_path_or_None)
    ("hair-back",   "parts/hair-back/hair_back_wavy_shoulder.png"),
    ("base-face",   "{face}"),  # replaced per-face
    ("eyes",        "parts/eyes/eyes_almond.png"),
    ("nose",        "parts/nose/nose_button.png"),
    ("mouth",       "parts/mouth/mouth_smile.png"),
    ("hair-middle", "parts/hair-middle/hair_middle_wavy_shoulder.png"),
    ("hair-front",  "parts/hair-front/hair_front_wavy_shoulder_female.png"),
]

# For baby faces, skip hair layers (babies are bald in our asset set)
BABY_LAYERS = [
    ("base-face", "{face}"),
    ("eyes",      "parts/eyes/eyes_round.png"),
    ("nose",      "parts/nose/nose_button.png"),
    ("mouth",     "parts/mouth/mouth_smile.png"),
]


def sample_corner_color(img: Image.Image) -> tuple[int, int, int]:
    """Sample the average color of the top-left 10x10 corner."""
    img = img.convert("RGB")
    rs, gs, bs, n = 0, 0, 0, 0
    for x in range(10):
        for y in range(10):
            r, g, b = img.getpixel((x, y))[:3]
            rs += r; gs += g; bs += b; n += 1
    return (rs // n, gs // n, bs // n)


def chroma_key(img: Image.Image, bg_color: tuple[int, int, int], tolerance: float) -> Image.Image:
    """Remove pixels within `tolerance` RGB distance of `bg_color`.

    Returns an RGBA image where background-matching pixels are fully
    transparent and all other pixels retain their original RGB.
    """
    img = img.convert("RGB")
    rgba = img.convert("RGBA")
    pixels = rgba.load()
    w, h = img.size
    bg_r, bg_g, bg_b = bg_color
    tol_sq = tolerance * tolerance
    for y in range(h):
        for x in range(w):
            r, g, b = pixels[x, y][:3]
            dr = r - bg_r
            dg = g - bg_g
            db = b - bg_b
            if dr*dr + dg*dg + db*db < tol_sq:
                pixels[x, y] = (r, g, b, 0)
    return rgba


def load_layered(asset_root: Path, rel_path: str, tolerance: float) -> Image.Image | None:
    """Load a PNG, sample its corner color, chroma-key it. Returns RGBA or None."""
    full = asset_root / rel_path
    if not full.exists():
        print(f"  SKIP (missing): {rel_path}", file=sys.stderr)
        return None
    with Image.open(full) as img:
        bg = sample_corner_color(img)
        keyed = chroma_key(img, bg, tolerance)
    return keyed


def composite_face(asset_root: Path, face_rel: str, output_dir: Path, tolerance: float = 40.0) -> Path | None:
    """Composite a single face with its layer stack. Returns output path."""
    face_full = asset_root / face_rel
    if not face_full.exists():
        print(f"  SKIP face (missing): {face_rel}", file=sys.stderr)
        return None

    # Pick layer set — baby faces get the bald stack
    is_baby = "baby" in face_rel.lower()
    layers = BABY_LAYERS if is_baby else DEFAULT_LAYERS

    print(f"  Compositing: {face_rel}  ({'baby stack' if is_baby else 'full stack'})")

    # Composite onto a beige background (so we can see the result clearly)
    bg_color = (220, 190, 158)
    canvas = Image.new("RGB", (1024, 1024), bg_color)

    # Save step-by-step images for debugging
    step_dir = output_dir / "steps" / Path(face_rel).stem
    step_dir.mkdir(parents=True, exist_ok=True)

    step_idx = 0
    for layer_name, layer_path_template in layers:
        layer_path = layer_path_template.format(face=face_rel)
        layer_img = load_layered(asset_root, layer_path, tolerance)
        if layer_img is None:
            continue
        # Composite onto canvas
        canvas_rgba = canvas.convert("RGBA")
        canvas_rgba.alpha_composite(layer_img)
        canvas = canvas_rgba.convert("RGB")

        step_idx += 1
        step_path = step_dir / f"{step_idx:02d}_{layer_name}.png"
        canvas.save(step_path)
        print(f"    + {layer_name:14s} → {step_path.name}")

    # Save final composite
    final_name = f"composite_{Path(face_rel).stem}.png"
    final_path = output_dir / final_name
    canvas.save(final_path)
    print(f"  → {final_path}")
    return final_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-root", default="kinrel-cameo",
                        help="Path to kinrel-cameo asset root (default: kinrel-cameo)")
    parser.add_argument("--output-dir", default="/tmp/composite-out",
                        help="Where to write composite PNGs")
    parser.add_argument("--tolerance", type=float, default=40.0,
                        help="Chroma-key RGB tolerance (default: 40.0)")
    parser.add_argument("--faces", nargs="*", default=None,
                        help="Face asset paths (relative to asset root) to composite. "
                             "If omitted, uses a default set of 4.")
    args = parser.parse_args()

    asset_root = Path(args.asset_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if not asset_root.exists():
        print(f"ERROR: asset root not found: {asset_root}", file=sys.stderr)
        return 2

    faces = args.faces if args.faces else DEFAULT_FACES
    print(f"=== Kinrel Cameo Composite Coherence Test ===")
    print(f"  Asset root:  {asset_root}")
    print(f"  Output dir:  {output_dir}")
    print(f"  Tolerance:   {args.tolerance}")
    print(f"  Faces:       {len(faces)}")
    print()

    successes = 0
    failures = 0
    for face_rel in faces:
        result = composite_face(asset_root, face_rel, output_dir, args.tolerance)
        if result is not None:
            successes += 1
        else:
            failures += 1

    print()
    print(f"=== Summary: {successes} composites generated, {failures} skipped ===")
    print(f"  Artifacts in: {output_dir}")
    return 0 if successes > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
