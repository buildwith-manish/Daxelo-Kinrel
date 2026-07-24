#!/usr/bin/env python3
"""
Fix missing 3D buildings in kinrel_dark_style.json

ROOT CAUSES (verified by decoding real OpenFreeMap tiles):
  1. `render_height = 0` buildings → fill-extrusion-height = 0 → invisible.
     Bengaluru z14: 1/124, Bengaluru z13: 1/1, London z13: 1/1.
  2. `render_min_height = null` → bare ["get","render_min_height"] returns null
     → feature may be skipped by MapLibre renderer.
     Bengaluru z13: 1/1, London z13: 1/1.
  3. `render_min_height < 0` (underground basements) → undefined extrusion.
     London z14: 2/508.
  4. Duplicate building-3d layers (`building-3d` + `kinrel-3d-buildings`) cause
     z-fighting on overlapping features.

FIXES:
  A. fill-extrusion-height uses `case` to fall back to 5m when render_height
     is 0 or null.
  B. fill-extrusion-base uses `max(0, coalesce(render_min_height, 0))` so null
     becomes 0 and negatives are clamped to 0.
  C. Remove duplicate `building-3d` and `building-3d-warm-glow` layers; keep
     only `kinrel-3d-buildings` and `kinrel-3d-buildings-warm-glow` (which have
     explicit maxzoom=22).
  D. Bump opacity to fully 1.0 at z14+ (was 0.8) so buildings are not washed out.

Also writes a backup of the original file before overwriting.
"""
from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

STYLE_PATH = Path(
    "/home/z/my-project/Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json"
)
BACKUP_PATH = STYLE_PATH.with_suffix(".json.bak-pre-3d-fix")


def build_height_expr() -> list:
    """If render_height > 0, use it; else fall back to 5m."""
    return [
        "case",
        [">", ["coalesce", ["get", "render_height"], 0], 0],
        ["get", "render_height"],
        5,
    ]


def build_base_expr() -> list:
    """max(0, coalesce(render_min_height, 0)) — clamp null/negatives to 0."""
    return ["max", 0, ["coalesce", ["get", "render_min_height"], 0]]


def build_opacity_expr() -> list:
    """Full 1.0 opacity from z14 onward (was 0.8)."""
    return [
        "interpolate",
        ["linear"],
        ["zoom"],
        12, 0.0,
        13, 0.7,
        14, 1.0,
        17, 1.0,
    ]


def build_height_zoom_interp(height_expr: list) -> list:
    """Per-zoom height multiplier applied to the resolved height value."""
    return [
        "interpolate",
        ["linear"],
        ["zoom"],
        13, ["*", height_expr, 3.0],
        14, ["*", height_expr, 2.0],
        15, ["*", height_expr, 1.5],
        17, height_expr,
        22, height_expr,
    ]


def fix_kinrel_3d_buildings(layer: dict) -> dict:
    """Apply render_height / render_min_height / opacity fixes."""
    paint = layer.setdefault("paint", {})

    # Keep the color interpolation as-is (preserves the warm dark palette).
    # Height: use 5m fallback when render_height is 0/null, then apply zoom
    # multiplier.
    paint["fill-extrusion-height"] = build_height_zoom_interp(build_height_expr())

    # Base: clamp null + negatives to 0.
    paint["fill-extrusion-base"] = build_base_expr()

    # Opacity: full at z14+.
    paint["fill-extrusion-opacity"] = build_opacity_expr()

    # Ensure vertical gradient stays on.
    paint["fill-extrusion-vertical-gradient"] = True

    # Make sure minzoom is 13 (data exists from z13) and maxzoom=22.
    layer["minzoom"] = 13
    layer["maxzoom"] = 22

    return layer


def fix_kinrel_3d_warm_glow(layer: dict) -> dict:
    """Apply same fixes to the warm-glow accent layer (tall buildings only)."""
    paint = layer.setdefault("paint", {})

    paint["fill-extrusion-height"] = build_height_zoom_interp(build_height_expr())
    paint["fill-extrusion-base"] = build_base_expr()
    # Keep the warm-glow low opacity — it's an accent.
    paint["fill-extrusion-opacity"] = [
        "interpolate",
        ["linear"],
        ["zoom"],
        12, 0.0,
        13, 0.08,
        15, 0.15,
        17, 0.15,
    ]
    paint["fill-extrusion-vertical-gradient"] = True

    # Filter: only buildings ≥ 30m (preserve existing intent). Use coalesce
    # so null render_height doesn't break the comparison.
    layer["filter"] = [">=", ["coalesce", ["get", "render_height"], 0], 30]
    layer["minzoom"] = 13
    layer["maxzoom"] = 22

    return layer


def main() -> int:
    if not STYLE_PATH.exists():
        print(f"ERROR: style not found: {STYLE_PATH}", file=sys.stderr)
        return 2

    # Backup (only first time).
    if not BACKUP_PATH.exists():
        shutil.cop2 = shutil.copy2  # noqa: keep alias for clarity
        shutil.copy2(STYLE_PATH, BACKUP_PATH)
        print(f"Backup written: {BACKUP_PATH}")
    else:
        print(f"Backup already exists, leaving as-is: {BACKUP_PATH}")

    with STYLE_PATH.open("r", encoding="utf-8") as f:
        style = json.load(f)

    layers = style.get("layers", [])
    print(f"Loaded style with {len(layers)} layers")

    # Identify what we have.
    target_ids = {
        "building-3d",
        "building-3d-warm-glow",
        "kinrel-3d-buildings",
        "kinrel-3d-buildings-warm-glow",
    }
    found = {layer.get("id"): layer for layer in layers if layer.get("id") in target_ids}
    print(f"3D building layers found: {sorted(found.keys())}")

    # Fix the kinrel-* layers in place.
    if "kinrel-3d-buildings" in found:
        fix_kinrel_3d_buildings(found["kinrel-3d-buildings"])
        print("Patched: kinrel-3d-buildings")
    else:
        print("WARN: kinrel-3d-buildings layer not found", file=sys.stderr)

    if "kinrel-3d-buildings-warm-glow" in found:
        fix_kinrel_3d_warm_glow(found["kinrel-3d-buildings-warm-glow"])
        print("Patched: kinrel-3d-buildings-warm-glow")
    else:
        print("WARN: kinrel-3d-buildings-warm-glow layer not found", file=sys.stderr)

    # Remove duplicate `building-3d` and `building-3d-warm-glow` (kinrel-* layers
    # cover the same source-layer with identical paint — keeping both causes
    # z-fighting and wastes GPU).
    remove_ids = {"building-3d", "building-3d-warm-glow"}
    before = len(layers)
    layers = [layer for layer in layers if layer.get("id") not in remove_ids]
    after = len(layers)
    if before != after:
        print(f"Removed {before - after} duplicate layer(s): {sorted(remove_ids & set(found.keys()))}")
    else:
        print("No duplicate layers to remove")

    style["layers"] = layers

    # Write back (compact but readable).
    tmp_path = STYLE_PATH.with_suffix(".json.tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(style, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp_path, STYLE_PATH)
    print(f"Wrote: {STYLE_PATH} ({len(layers)} layers)")

    # Sanity check: reload and verify.
    with STYLE_PATH.open("r", encoding="utf-8") as f:
        verify = json.load(f)
    v_layers = {l.get("id"): l for l in verify["layers"]}

    def contains(node, key) -> bool:
        if isinstance(node, str):
            return node == key
        if isinstance(node, list):
            return any(contains(x, key) for x in node)
        if isinstance(node, dict):
            return key in node or any(contains(v, key) for v in node.values())
        return False

    if "kinrel-3d-buildings" in v_layers:
        h = v_layers["kinrel-3d-buildings"]["paint"]["fill-extrusion-height"]
        b = v_layers["kinrel-3d-buildings"]["paint"]["fill-extrusion-base"]
        assert contains(h, "case"), "height expr missing case fallback"
        assert contains(b, "max"), "base expr missing max clamp"
        # Duplicates must be gone.
        assert "building-3d" not in v_layers, "building-3d duplicate still present"
        assert "building-3d-warm-glow" not in v_layers, "building-3d-warm-glow duplicate still present"
        print("Sanity check: PASSED (height has case fallback, base has max clamp, duplicates removed)")
    else:
        print("Sanity check: FAILED (kinrel-3d-buildings missing)", file=sys.stderr)
        return 3

    return 0


if __name__ == "__main__":
    sys.exit(main())
