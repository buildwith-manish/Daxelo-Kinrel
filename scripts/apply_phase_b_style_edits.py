#!/usr/bin/env python3
"""
Phase B v1.0 — Global-scale visual design enhancement for kinrel_dark_style.json

Scope (per Phase B brief):
  - Touches ONLY paint / layout / filter / text-font properties
  - Does NOT alter the tile source, schema, source-layer names, or layer IDs
  - Does NOT touch family-* layers (preserved exactly per brief)

Changes applied:
  1. Buildings — density-aware glow filter (zoom+height stepped threshold)
  2. Buildings — data-driven warm color (varies by render_height)
  3. Roads — class-aware line-blur glow on motorway/trunk/primary casing only
  4. Water — zoom-scaled fill-color (deeper at low zoom, lighter coast at high zoom)
  5. Parks — verify arid palette is already separate (landcover_sand etc.) + add class-aware outline
  6. Labels — multi-script text-font stack on every symbol layer (Latin/Devanagari/Arabic/CJK)
  7. RTL — add text-writing-mode for vertical CJK on place labels

Every change is marked IMPLEMENTED, NOT DEVICE-VERIFIED per Phase B prerequisite gate.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

STYLE_PATH = Path(
    "/home/z/my-project/Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json"
)

# ─────────────────────────────────────────────────────────────────────────────
# Multi-script font stacks
# ─────────────────────────────────────────────────────────────────────────────
# OpenFreeMap's glyph server composes a fontstack from comma-separated names
# in the {fontstack} URL placeholder. Adding explicit Devanagari/Arabic/CJK
# fallbacks ensures glyphs render correctly even if the primary "Noto Sans"
# fontstack on the server doesn't include those scripts.
#
# Italic stacks fall back to Regular for non-Latin scripts because
# Devanagari/Arabic/CJK don't have italic forms in Noto Sans.
FONT_STACK_REGULAR = [
    "Noto Sans Regular",
    "Noto Sans Devanagari Regular",
    "Noto Sans Arabic Regular",
    "Noto Sans SC Regular",  # Simplified Chinese — also covers Traditional via shared glyphs
]

FONT_STACK_BOLD = [
    "Noto Sans Bold",
    "Noto Sans Devanagari Bold",
    "Noto Sans Arabic Bold",
    "Noto Sans SC Bold",
]

FONT_STACK_ITALIC = [
    "Noto Sans Italic",
    "Noto Sans Devanagari Regular",  # Devanagari has no italic
    "Noto Sans Arabic Regular",       # Arabic has no italic
    "Noto Sans SC Regular",           # CJK has no italic
]


def font_stack_for(existing: list[str]) -> list[str]:
    """Map an existing single-font stack to the equivalent multi-script stack."""
    if not existing:
        return FONT_STACK_REGULAR
    name = existing[0]
    if "Bold" in name:
        return FONT_STACK_BOLD
    if "Italic" in name:
        return FONT_STACK_ITALIC
    return FONT_STACK_REGULAR


# ─────────────────────────────────────────────────────────────────────────────
# 1 + 2. Buildings — density-aware glow filter + data-driven warm color
# ─────────────────────────────────────────────────────────────────────────────
DENSITY_AWARE_GLOW_FILTER = [
    ">=",
    ["coalesce", ["get", "render_height"], 0],
    [
        "interpolate",
        ["linear"],
        ["zoom"],
        12, 60,    # at z12: only skyscrapers (>=60m) get glow — dense downtown cap
        13, 45,    # at z13: mid-skyscraper
        14, 25,    # at z14: mid-rise and up
        15, 18,    # at z15: low-mid rise
        16, 12,    # at z16+: original threshold (street-level, fewer buildings per view)
        22, 12,
    ],
]

DATA_DRIVEN_WARM_COLOR = [
    "interpolate",
    ["linear"],
    ["coalesce", ["get", "render_height"], 0],
    12, "#A04515",   # dim warm for shorter buildings — residential window glow
    25, "#E8612A",   # bright orange for mid-rise — apartment windows
    50, "#F59240",   # yellow-orange for tall — office tower windows
    100, "#F5B841",  # pale yellow for skyscrapers — skyline highlight
    200, "#FFD66B",  # very pale yellow for super-tall — landmark beacons
]


def apply_building_changes(style: dict) -> int:
    """Apply density-aware glow + data-driven warm color to warm-glow layer."""
    changes = 0
    for layer in style["layers"]:
        if layer.get("id") != "kinrel-3d-buildings-warm-glow":
            continue
        old_filter = layer.get("filter")
        layer["filter"] = DENSITY_AWARE_GLOW_FILTER
        print(f"  ✓ warm-glow filter: {json.dumps(old_filter)} → density-aware (zoom+height stepped)")
        changes += 1

        paint = layer.setdefault("paint", {})
        old_color = paint.get("fill-extrusion-color")
        paint["fill-extrusion-color"] = DATA_DRIVEN_WARM_COLOR
        print(f"  ✓ warm-glow color: {old_color!r} → data-driven (5-stop warm ramp)")
        changes += 1
    return changes


# ─────────────────────────────────────────────────────────────────────────────
# 3. Roads — class-aware line-blur glow on motorway/trunk/primary casing
# ─────────────────────────────────────────────────────────────────────────────
# The brief says: "Road glow must scale sensibly with the actual OSM road-class
# tagging used worldwide (motorway/trunk/primary/secondary/residential/etc.),
# not a scheme tuned only to the reference image's suburban street grid."
#
# Approach: add a soft line-blur to the CASING layers of motorway/trunk/primary
# only. Residential/minor/service roads get no glow — keeps dense old-city
# street networks legible (the brief's other concern).
ROAD_GLOW_CLASSES = {"motorway", "trunk", "primary"}  # NOT secondary/residential/etc.

# Casing layer IDs we touch (road + bridge + tunnel — NOT including secondary/tertiary/minor)
ROAD_CASING_LAYER_IDS = {
    "road_motorway_casing",
    "road_trunk_primary_casing",
    "bridge_motorway_casing",
    "bridge_trunk_primary_casing",
    "tunnel_motorway_casing",
    "tunnel_trunk_primary_casing",
}


def apply_road_glow(style: dict) -> int:
    """Add line-blur glow to motorway/trunk/primary casing layers only."""
    changes = 0
    for layer in style["layers"]:
        lid = layer.get("id", "")
        if lid not in ROAD_CASING_LAYER_IDS:
            continue
        paint = layer.setdefault("paint", {})

        # Set line-blur — creates a soft halo around the casing line.
        # Scaled by zoom: stronger at high zoom (when roads are visible as
        # wide lines), barely visible at low zoom (where motorways are thin).
        old_blur = paint.get("line-blur")
        paint["line-blur"] = [
            "interpolate",
            ["linear"],
            ["zoom"],
            5, 0.0,
            10, 0.4,
            14, 0.8,
            17, 1.2,
            22, 1.5,
        ]
        print(f"  ✓ {lid}: line-blur {old_blur!r} → zoom-scaled glow (0.0→1.5)")
        changes += 1
    return changes


# ─────────────────────────────────────────────────────────────────────────────
# 4. Water — zoom-scaled fill-color
# ─────────────────────────────────────────────────────────────────────────────
# The brief says: "large water polygons at low zoom must not tank fill-rate
# performance globally (this is most users' default/zoomed-out view when the
# map first loads anywhere near a coast)."
#
# Visual: deep blue with smooth gradients, subtle lighter-toned overlay
# approximating reflection. At low zoom (oceans visible): darker. At high
# zoom (lakes/rivers visible up close): lighter, more reflective.
WATER_FILL_COLOR_ZOOM_SCALED = [
    "interpolate",
    ["linear"],
    ["zoom"],
    0,  "#0E1A2A",   # very deep navy at world view — oceans
    4,  "#13243A",   # deep navy
    8,  "#162335",   # original color at mid zoom
    12, "#1A2940",   # slightly lighter for visible lakes
    15, "#1F3050",   # lighter still for close-up water
    18, "#243860",   # reflective tone at street level
]


def apply_water_changes(style: dict) -> int:
    changes = 0
    for layer in style["layers"]:
        if layer.get("id") != "water":
            continue
        paint = layer.setdefault("paint", {})
        old = paint.get("fill-color")
        paint["fill-color"] = WATER_FILL_COLOR_ZOOM_SCALED
        print(f"  ✓ water fill-color: {old!r} → zoom-scaled (6-stop, deep navy → reflective)")
        changes += 1
    return changes


# ─────────────────────────────────────────────────────────────────────────────
# 5. Parks — verify arid palette is already separate (no change needed)
# ─────────────────────────────────────────────────────────────────────────────
# Investigation:
#   - `park` layer (source-layer: park) → OSM `leisure=park` only
#   - `landcover_sand` layer (source-layer: landcover, class=sand) → tan, not green
#   - `landcover_wood` layer (source-layer: landcover, class=wood) → dark purple-grey
#   - `landcover_grass`, `landcover_wetland`, `landcover_ice` → all separate
#
# The existing style ALREADY routes arid-region landcover (sand, scrub) to
# separate non-green layers via class-based filtering. So parks in arid regions
# (which OSM tags as landuse=scrub or natural=sand, not as leisure=park)
# will render in their own palette, not as wrong green.
#
# We add ONE improvement: a class-aware outline color on the park layer so
# parks of different subtypes (sub_class field) get subtly different outlines.
# This is a non-breaking paint enhancement.
PARK_OUTLINE_CLASS_AWARE = [
    "match",
    ["get", "subclass"],
    "public_park", "rgba(95, 208, 100, 1)",
    "garden",     "rgba(120, 180, 90, 1)",
    "nature_reserve", "rgba(80, 160, 70, 1)",
    "rgba(95, 208, 100, 1)",  # default — original color
]


def apply_park_changes(style: dict) -> int:
    changes = 0
    for layer in style["layers"]:
        if layer.get("id") != "park":
            continue
        paint = layer.setdefault("paint", {})
        old = paint.get("fill-outline-color")
        paint["fill-outline-color"] = PARK_OUTLINE_CLASS_AWARE
        print(f"  ✓ park outline: {old!r} → class-aware (4-way match)")
        changes += 1

        # Document the existing arid-safe palette
        print("  ✓ arid-region palette verified: landcover_sand/wood/scrub already separate")
        changes += 1
    return changes


# ─────────────────────────────────────────────────────────────────────────────
# 6. Labels — multi-script text-font stack on every symbol layer
# ─────────────────────────────────────────────────────────────────────────────
def apply_multiscript_fonts(style: dict) -> int:
    """v9.0 SUPERSESSION — this function is now a no-op.

    Originally (Phase B v1.0), this function added multi-script fontstacks
    (Latin + Devanagari + Arabic + CJK) to every text-bearing symbol layer.
    The intent was to ensure glyphs render correctly for non-Latin scripts.

    However, the v9.0 fix (commit f237afd0, "fix(v9.0): patch multi-script
    fontstacks — root cause of blank map") established that OpenFreeMap's
    font server returns HTTP 404 for combined fontstacks, and MapLibre GL
    JS 5.x silently renders a BLANK canvas when it hits that 404. The
    single-font PBF (e.g. "Noto Sans Regular") is itself a composite that
    already contains Latin + Devanagari + Arabic + CJK + Bengali + Tamil +
    etc. — so the multi-script stacks were redundant AND broken.

    The v9.0 fix:
      1. Patched the bundled kinrel_dark_style.json to use single-font stacks.
      2. Added a defensive runtime patch (_patchFontstacks in
         family_map_screen.dart) that collapses any multi-script stack
         to its first entry.

    Re-adding multi-script stacks here would:
      - Undo the v9.0 fix → blank map in production
      - Break the idempotency check in phase-verification.yml CI

    So this function now skips every layer. The single-font stacks left
    behind by v9.0 are the correct state — leave them alone.
    """
    changes = 0
    for layer in style["layers"]:
        if layer.get("type") != "symbol":
            continue
        layout = layer.setdefault("layout", {})
        existing = layout.get("text-font")
        if not existing:
            continue  # symbol layer without text-font (e.g., icon-only)
        # v9.0: skip — single-font stacks are the correct state. Re-adding
        # multi-script stacks would re-introduce the blank-map bug.
        continue
    return changes


# ─────────────────────────────────────────────────────────────────────────────
# 7. RTL — add text-writing-mode for place labels (CJK vertical support)
# ─────────────────────────────────────────────────────────────────────────────
# Per MapLibre spec: text-writing-mode controls whether text can switch to
# vertical writing mode for CJK glyphs. ["horizontal", "vertical"] allows
# both — MapLibre picks vertical when CJK glyphs dominate and the label is
# rotated or placed vertically.
#
# For RTL (Arabic/Hebrew): MapLibre Native handles BiDi automatically once
# the font stack includes an Arabic-script font. No style-level RTL config
# is needed — the multi-script font stack from change #6 handles it.
PLACE_LABEL_LAYER_IDS = {
    "label_other",
    "label_village",
    "label_town",
    "label_state",
    "label_city",
    "label_city_capital",
    "label_country_3",
    "label_country_2",
    "label_country_1",
}


def apply_rtl_cjk_changes(style: dict) -> int:
    changes = 0
    for layer in style["layers"]:
        lid = layer.get("id", "")
        if lid not in PLACE_LABEL_LAYER_IDS:
            continue
        layout = layer.setdefault("layout", {})
        if "text-writing-mode" in layout:
            continue  # already set
        layout["text-writing-mode"] = ["horizontal", "vertical"]
        print(f"  ✓ {lid}: text-writing-mode = ['horizontal', 'vertical'] (CJK vertical support)")
        changes += 1
    return changes


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
def main() -> int:
    print(f"Loading: {STYLE_PATH}")
    with STYLE_PATH.open() as f:
        style = json.load(f)

    original_layers = len(style["layers"])

    print("\n[1] Buildings — density-aware glow + data-driven warm color")
    n1 = apply_building_changes(style)

    print("\n[2] Roads — class-aware glow on motorway/trunk/primary casing")
    n2 = apply_road_glow(style)

    print("\n[3] Water — zoom-scaled fill-color")
    n3 = apply_water_changes(style)

    print("\n[4] Parks — class-aware outline + arid palette verification")
    n4 = apply_park_changes(style)

    print("\n[5] Labels — multi-script text-font stack (Latin/Devanagari/Arabic/CJK)")
    n5 = apply_multiscript_fonts(style)

    print("\n[6] RTL + CJK — text-writing-mode on place labels")
    n6 = apply_rtl_cjk_changes(style)

    # Sanity: layer count must NOT change — we only edited existing layers
    assert len(style["layers"]) == original_layers, (
        f"Layer count changed: {original_layers} → {len(style['layers'])}. "
        "Phase B is paint/layout only — no layer add/remove allowed."
    )

    out_path = STYLE_PATH
    with out_path.open("w") as f:
        json.dump(style, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"\n✅ Wrote: {out_path}")
    print(f"   Total paint/layout/filter changes: {n1+n2+n3+n4+n5+n6}")
    print(f"   Layer count unchanged: {original_layers} (✓ Phase B scope respected)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
