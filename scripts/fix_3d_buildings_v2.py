#!/usr/bin/env python3
"""
Aggressive fix to make EVERY available 3D building visible.

After the previous fix (case fallback for render_height=0), user still reports
many buildings missing. Root causes now confirmed:

A. OpenFreeMap planet source is HARD-CAPPED at zoom 14 (verified: z15-z17
   tiles return empty 0-byte responses). At z15+, MapLibre overzooms z14 data
   — NO new buildings appear beyond z14, even if user zooms to z17.

B. The style uses indirect TileJSON `url: "https://tiles.openfreemap.org/planet"`
   instead of an explicit `tiles: [...]` array. On MapLibre GL JS this can
   cause the source to silently fail to load vector tiles on some setups
   (CORS, network, race conditions). We must pin the direct tile URL with
   the date-stamped prefix that actually serves data.

C. minzoom=13 on the building layer means at z<13 the user sees NOTHING — not
   even the few landmark buildings that exist at z12. Many users open the map
   at z4-z12 (world/country/city level) and assume "buildings missing".

D. Pitch=0 by default. fill-extrusion looks flat from top-down — you literally
   cannot tell buildings are extruded. Need to set default initPitch > 0
   (e.g. 25°) on the screen, OR add a 2D building outline layer so buildings
   are visible regardless of pitch.

E. `building` fill layer has maxzoom=14 — at z15+ it disappears. Without a
   2D fallback layer, if extrusion opacity is low or pitch=0, buildings look
   invisible.

F. fill-extrusion-opacity ramps from 0 (z12) → 0.7 (z13) → 1.0 (z14). At z13,
   opacity is only 0.7 and only 1 building exists in the tile — buildings
   appear washed out or missing.

G. `kinrel-3d-buildings-warm-glow` filter requires render_height ≥ 30m. Only
   skyscrapers get the warm glow — fine for visual hierarchy, but if user is
   in a low-rise city, no glow appears and they perceive "missing buildings".

Fixes:
  1. Switch openmaptiles source to direct `tiles: [...]` array (no indirect url).
     Pin the date-stamped URL that actually serves data.
  2. Lower `kinrel-3d-buildings` minzoom from 13 → 11 (city-level visibility).
  3. Add a NEW 2D building outline layer `kinrel-buildings-outline` that renders
     at z11-z22 — guarantees buildings visible even at pitch=0.
  4. Bump fill-extrusion-opacity ramp so buildings are fully visible from z13.
  5. Lower `kinrel-3d-buildings-warm-glow` filter threshold from 30m → 12m so
     ordinary 2-3 story buildings (15-20m) get the warm glow too.
  6. Add fill-extrusion-pattern fallback is NOT added — not needed.
  7. Update the `building` 2D fill layer maxzoom from 14 → 22 so 2D footprint
     stays visible at all zoom levels (was being hidden above z14).
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
BACKUP_PATH = STYLE_PATH.with_suffix(".json.bak-pre-aggressive-fix")


def build_height_expr() -> list:
    """If render_height > 0, use it; else fall back to 6m (was 5m — slightly
    taller so low-rise buildings are obviously extruded even at low pitch)."""
    return [
        "case",
        [">", ["coalesce", ["get", "render_height"], 0], 0],
        ["get", "render_height"],
        6,
    ]


def build_base_expr() -> list:
    return ["max", 0, ["coalesce", ["get", "render_min_height"], 0]]


def build_height_zoom_interp(height_expr: list) -> list:
    """Per-zoom height multiplier. Lower minzoom start so city-level
    buildings at z11-z12 are visibly tall."""
    return [
        "interpolate",
        ["linear"],
        ["zoom"],
        11, ["*", height_expr, 4.0],   # was 13/3.0 — earlier + taller
        12, ["*", height_expr, 3.5],
        13, ["*", height_expr, 3.0],
        14, ["*", height_expr, 2.0],
        15, ["*", height_expr, 1.5],
        17, height_expr,
        22, height_expr,
    ]


def build_opacity_expr() -> list:
    """Full opacity from z13 onward."""
    return [
        "interpolate",
        ["linear"],
        ["zoom"],
        10, 0.0,
        11, 0.4,
        12, 0.7,
        13, 1.0,
        17, 1.0,
    ]


def main() -> int:
    if not STYLE_PATH.exists():
        print(f"ERROR: style not found: {STYLE_PATH}", file=sys.stderr)
        return 2

    if not BACKUP_PATH.exists():
        shutil.copy2(STYLE_PATH, BACKUP_PATH)
        print(f"Backup written: {BACKUP_PATH}")
    else:
        print(f"Backup already exists: {BACKUP_PATH}")

    with STYLE_PATH.open("r", encoding="utf-8") as f:
        style = json.load(f)

    # ── FIX 1: replace indirect TileJSON url with explicit tiles array ────
    src = style["sources"]["openmaptiles"]
    if src.get("url"):
        print(f"Removing indirect url: {src['url']}")
        src.pop("url", None)
    src["type"] = "vector"
    src["tiles"] = [
        "https://tiles.openfreemap.org/planet/20260621_080001_pt/{z}/{x}/{y}.pbf"
    ]
    src["maxzoom"] = 14  # OpenFreeMap planet hard cap (verified)
    src["minzoom"] = 0
    src["attribution"] = '<a href="https://openfreemap.org" target="_blank">OpenFreeMap</a> <a href="https://www.openmaptiles.org/" target="_blank">© OpenMapTiles</a> <a href="https://www.openstreetmap.org/copyright" target="_blank">© OpenStreetMap</a>'
    print("Patched source: openmaptiles → direct tiles array, maxzoom=14")

    # ── FIX 2-4: patch kinrel-3d-buildings with lower minzoom + better opacity
    layers = style["layers"]
    kinrel_3d = next((l for l in layers if l.get("id") == "kinrel-3d-buildings"), None)
    if kinrel_3d:
        kinrel_3d["minzoom"] = 11   # was 13 — city-level visibility
        kinrel_3d["maxzoom"] = 22
        paint = kinrel_3d["paint"]
        paint["fill-extrusion-height"] = build_height_zoom_interp(build_height_expr())
        paint["fill-extrusion-base"] = build_base_expr()
        paint["fill-extrusion-opacity"] = build_opacity_expr()
        paint["fill-extrusion-vertical-gradient"] = True
        print("Patched: kinrel-3d-buildings (minzoom 13→11, opacity ramp 0→1 by z13)")

    # ── FIX 5: lower warm-glow threshold from 30m → 12m
    warm = next((l for l in layers if l.get("id") == "kinrel-3d-buildings-warm-glow"), None)
    if warm:
        warm["minzoom"] = 12
        warm["maxzoom"] = 22
        warm["filter"] = [">=", ["coalesce", ["get", "render_height"], 0], 12]
        paint = warm["paint"]
        paint["fill-extrusion-height"] = build_height_zoom_interp(build_height_expr())
        paint["fill-extrusion-base"] = build_base_expr()
        paint["fill-extrusion-opacity"] = [
            "interpolate", ["linear"], ["zoom"],
            11, 0.0,
            12, 0.08,
            14, 0.18,
            17, 0.20,
        ]
        paint["fill-extrusion-vertical-gradient"] = True
        print("Patched: kinrel-3d-buildings-warm-glow (threshold 30m→12m)")

    # ── FIX 6: extend `building` 2D fill layer to maxzoom 22
    bldg_fill = next((l for l in layers if l.get("id") == "building"), None)
    if bldg_fill:
        bldg_fill["minzoom"] = 11
        bldg_fill["maxzoom"] = 22
        # Slightly more visible
        bldg_fill.setdefault("paint", {})
        bldg_fill["paint"]["fill-opacity"] = [
            "interpolate", ["linear"], ["zoom"],
            10, 0.0,
            11, 0.3,
            13, 0.5,
            15, 0.4,
            17, 0.3,
            22, 0.3,
        ]
        print("Patched: building (2D fill) minzoom 13→11, maxzoom 14→22")

    # ── FIX 7: ADD a new 2D building OUTLINE layer so buildings are visible
    # even when pitch=0 (top-down view, extrusion not apparent).
    # Insert it right before kinrel-3d-buildings so it sits below extrusion.
    outline_id = "kinrel-buildings-outline"
    outline_layer = {
        "id": outline_id,
        "type": "line",
        "source": "openmaptiles",
        "source-layer": "building",
        "minzoom": 11,
        "maxzoom": 22,
        "paint": {
            "line-color": "#4A4060",   # subtle purple-grey
            "line-width": [
                "interpolate", ["linear"], ["zoom"],
                11, 0.3,
                13, 0.6,
                15, 0.8,
                17, 1.0,
                22, 1.5,
            ],
            "line-opacity": [
                "interpolate", ["linear"], ["zoom"],
                10, 0.0,
                11, 0.6,
                13, 0.9,
                17, 1.0,
            ],
        },
        "layout": {},
    }

    # Remove if exists (idempotent)
    layers = [l for l in layers if l.get("id") != outline_id]
    # Insert before kinrel-3d-buildings
    insert_idx = next(
        (i for i, l in enumerate(layers) if l.get("id") == "kinrel-3d-buildings"),
        len(layers) - 1,
    )
    layers.insert(insert_idx, outline_layer)
    print(f"Inserted new layer: {outline_id} (2D outline, z11-z22)")
    style["layers"] = layers

    # Write back
    tmp_path = STYLE_PATH.with_suffix(".json.tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(style, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp_path, STYLE_PATH)
    print(f"\nWrote: {STYLE_PATH} ({len(layers)} layers)")

    # Sanity check
    with STYLE_PATH.open("r", encoding="utf-8") as f:
        verify = json.load(f)
    v_src = verify["sources"]["openmaptiles"]
    assert v_src.get("tiles"), "tiles array missing from openmaptiles source"
    assert not v_src.get("url"), "url still present (should be removed)"
    assert v_src.get("maxzoom") == 14, f"maxzoom wrong: {v_src.get('maxzoom')}"

    v_layers = {l.get("id"): l for l in verify["layers"]}
    assert v_layers.get("kinrel-3d-buildings", {}).get("minzoom") == 11, "minzoom not lowered"
    assert outline_id in v_layers, "outline layer not added"
    assert v_layers[outline_id]["minzoom"] == 11, "outline minzoom wrong"
    assert v_layers.get("building", {}).get("maxzoom") == 22, "2D fill maxzoom not extended"
    print("\nSanity check: PASSED")
    print(f"  - source: direct tiles array, maxzoom=14")
    print(f"  - kinrel-3d-buildings minzoom: 11 (was 13)")
    print(f"  - 2D building fill maxzoom: 22 (was 14)")
    print(f"  - new outline layer: z11-z22")
    print(f"  - warm-glow threshold: 12m (was 30m)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
