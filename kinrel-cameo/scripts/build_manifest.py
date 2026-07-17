#!/usr/bin/env python3
"""
Build a fresh MANIFEST.json for kinrel-cameo that:
  (1) Matches the schema expected by validate_manifest.py
  (2) Lists every ACTUAL asset file in the asset_root directory
  (3) Tags each asset with metadata (id, label) for the Flutter resolver

Run from anywhere — auto-discovers asset_root from this script's location.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from PIL import Image

ASSET_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = ASSET_ROOT / "MANIFEST.json"

# ---- Discovery helpers ----

def list_dir(rel_dir: str):
    d = ASSET_ROOT / rel_dir
    if not d.exists():
        return []
    return sorted([p.name for p in d.glob("*.png") if p.stat().st_size > 5*1024])

def img_size(rel_path: str):
    p = ASSET_ROOT / rel_path
    if not p.exists():
        return None
    with Image.open(p) as img:
        return img.size

# ---- Build manifest sections ----

def build_age_stages():
    files = list_dir("age-stages")
    out = []
    for fn in files:
        # stage_<id>.png -> id
        stem = fn[:-4]
        if stem.startswith("stage_"):
            sid = stem[6:]
        else:
            sid = stem
        out.append({"id": sid, "label": sid.replace("_", " ").title(), "file": fn})
    return out

def build_skin_tones():
    files = list_dir("skin-tones")
    out = []
    for fn in files:
        # skin_01.png -> id "skin_01"
        out.append({"id": fn[:-4], "file": fn})
    return out

def build_face_shapes():
    files = list_dir("face-shapes")
    out = []
    for fn in files:
        # shape_oval.png -> id "oval"
        stem = fn[:-4]
        sid = stem[6:] if stem.startswith("shape_") else stem
        out.append({"id": sid, "file": fn})
    return out

def build_base_faces():
    """Walk base-faces/ recursively — collect all face PNGs.
    Each entry: {path: 'baby/face_baby_A.png', stage: 'baby', variant: 'A', gender: 'neutral'}
    """
    out = []
    bf_root = ASSET_ROOT / "base-faces"
    # Walk subdirectories first (new A/B/C/D layout)
    for sub in sorted(bf_root.iterdir()):
        if not sub.is_dir():
            continue
        stage = sub.name
        for p in sorted(sub.glob("*.png")):
            if p.stat().st_size < 5*1024:
                continue
            stem = p.stem  # face_baby_A
            # Try to extract variant letter (last char if A/B/C/D)
            variant = ""
            if stem.endswith(("_A","_B","_C","_D")):
                variant = stem[-1]
            # Try to extract gender
            gender = "neutral"
            if "_boy_" in stem or "_male_" in stem or stem.endswith("_male"):
                gender = "male"
            elif "_girl_" in stem or "_female_" in stem or stem.endswith("_female"):
                gender = "female"
            out.append({
                "path": f"base-faces/{stage}/{p.name}",
                "stage": stage,
                "variant": variant,
                "gender": gender,
                "file": p.name,
            })
    # Also walk top-level legacy files (face_adult_male.png, face_baby_0_2.png, etc.)
    for p in sorted(bf_root.glob("*.png")):
        if p.stat().st_size < 5*1024:
            continue
        stem = p.stem  # face_adult_male
        out.append({
            "path": f"base-faces/{p.name}",
            "stage": "legacy",
            "variant": "",
            "gender": "neutral",
            "file": p.name,
        })
    return out

def build_parts():
    """parts/<category>/<file>.png"""
    parts_root = ASSET_ROOT / "parts"
    out = {}
    if not parts_root.exists():
        return out
    for sub in sorted(parts_root.iterdir()):
        if not sub.is_dir():
            continue
        cat = sub.name  # eyes, nose, eyebrows, ...
        items = []
        for p in sorted(sub.glob("*.png")):
            if p.stat().st_size < 5*1024:
                continue
            stem = p.stem  # eyes_almond
            # strip leading category prefix
            sid = stem
            if stem.startswith(cat + "_"):
                sid = stem[len(cat)+1:]
            elif stem.startswith("eyebrows_"):
                sid = stem[len("eyebrows_"):]
            elif stem.startswith("eyelids_"):
                sid = stem[len("eyelids_"):]
            elif stem.startswith("pupils_"):
                sid = stem[len("pupils_"):]
            items.append({"id": stem, "short_id": sid, "file": p.name})
        if items:
            out[cat] = items
    return out

def build_accessories():
    """accessories/<type>/<file>.png"""
    acc_root = ASSET_ROOT / "accessories"
    out = []
    if not acc_root.exists():
        return out
    for sub in sorted(acc_root.iterdir()):
        if not sub.is_dir():
            continue
        acc_type = sub.name
        for p in sorted(sub.glob("*.png")):
            if p.stat().st_size < 5*1024:
                continue
            out.append({
                "path": f"accessories/{acc_type}/{p.name}",
                "type": acc_type,
                "id": p.stem,
                "file": p.name,
            })
    return out

def build_clothing():
    """clothing/<category>/<file>.png"""
    cl_root = ASSET_ROOT / "clothing"
    out = {}
    if not cl_root.exists():
        return out
    for sub in sorted(cl_root.iterdir()):
        if not sub.is_dir():
            continue
        cat = sub.name
        items = []
        for p in sorted(sub.glob("*.png")):
            if p.stat().st_size < 5*1024:
                continue
            stem = p.stem
            sid = stem
            if stem.startswith(cat + "_"):
                sid = stem[len(cat)+1:]
            items.append({"id": stem, "short_id": sid, "file": p.name})
        if items:
            out[cat] = items
    return out

def build_genetics():
    return [p.name for p in sorted((ASSET_ROOT / "genetics").glob("*.png")) if p.stat().st_size > 5*1024] if (ASSET_ROOT / "genetics").exists() else []

def build_reference():
    return [p.name for p in sorted((ASSET_ROOT / "reference").glob("*.png")) if p.stat().st_size > 5*1024] if (ASSET_ROOT / "reference").exists() else []

# ---- Main ----

def main():
    print(f"Building manifest from {ASSET_ROOT}...")
    age_stages = build_age_stages()
    skin_tones = build_skin_tones()
    face_shapes = build_face_shapes()
    base_faces = build_base_faces()
    parts = build_parts()
    accessories = build_accessories()
    clothing = build_clothing()
    genetics = build_genetics()
    reference = build_reference()

    # Count totals
    parts_count = sum(len(v) for v in parts.values())
    accessories_count = len(accessories)
    clothing_count = sum(len(v) for v in clothing.values())

    # Load existing manifest to preserve documentation/style sections
    existing = {}
    if MANIFEST_PATH.exists():
        with MANIFEST_PATH.open() as f:
            existing = json.load(f)

    manifest = {
        "name": "Kinrel Cameo v2 — Modular Genetics-Aware Avatar System",
        "version": "2.1.0",
        "description": "Modular, swappable, genetics-aware 2D avatar parts for the Kinrel family-relationship platform. Generated with the locked MASTER STYLE LOCK. v2 implements 13 user-requested improvements over v1.",
        "project": "Daxelo Kinrel",
        "repository": "https://github.com/buildwith-manish/Daxelo-Kinrel",
        "tagline": "A Cameo is never a standalone avatar. Always a member of the family.",

        "canvas_rules": existing.get("canvas_rules", {
            "head_and_shoulders": "1024x1024, character centered, eyes at Y=400px, nose center at X=512px, mouth center at Y=620px, hair top at Y=200px, plain warm beige background",
            "full_body": "768x1344, character centered, top of head at Y=100, waist at Y=680, feet at Y=1280",
            "master_sheet": "1344x768 landscape, editorial layout"
        }),

        "background_lock": {
            "color_rgb": [220, 190, 158],
            "color_hex": "#DCBE9E",
            "tolerance": 60.0,
            "rule": "Solid flat warm beige, edge-to-edge, no gradient/vignette, 80px margin, all 4 corners uniform. Required for chroma-key compositing."
        },

        "color_palette": existing.get("color_palette", {}),

        "layered_architecture": existing.get("layered_architecture", {}),

        "v2_improvements": existing.get("v2_improvements", []),

        "asset_counts": {
            "age_stages": len(age_stages),
            "skin_tones": len(skin_tones),
            "face_shapes": len(face_shapes),
            "base_faces": len(base_faces),
            "parts_total": parts_count,
            "parts_breakdown": {k: len(v) for k, v in parts.items()},
            "accessories": accessories_count,
            "clothing_total": clothing_count,
            "clothing_breakdown": {k: len(v) for k, v in clothing.items()},
            "genetics": len(genetics),
            "reference": len(reference),
            "total": len(age_stages) + len(skin_tones) + len(face_shapes) + len(base_faces) + parts_count + accessories_count + clothing_count + len(genetics) + len(reference),
        },

        "ageStages": age_stages,
        "skinTones": skin_tones,
        "faceShapes": face_shapes,
        "baseFaces": base_faces,
        "parts": parts,
        "accessories": accessories,
        "clothing": clothing,
        "genetics": genetics,
        "reference": reference,

        "documentation": existing.get("documentation", {}),
    }

    # Save
    with MANIFEST_PATH.open("w") as f:
        json.dump(manifest, f, indent=2)

    print(f"Wrote {MANIFEST_PATH}")
    print(f"  age_stages:   {len(age_stages)}")
    print(f"  skin_tones:   {len(skin_tones)}")
    print(f"  face_shapes:  {len(face_shapes)}")
    print(f"  base_faces:   {len(base_faces)}")
    print(f"  parts:        {parts_count}  ({dict((k, len(v)) for k, v in parts.items())})")
    print(f"  accessories:  {accessories_count}")
    print(f"  clothing:     {clothing_count}  ({dict((k, len(v)) for k, v in clothing.items())})")
    print(f"  genetics:     {len(genetics)}")
    print(f"  reference:    {len(reference)}")
    print(f"  TOTAL:        {manifest['asset_counts']['total']}")


if __name__ == "__main__":
    main()
