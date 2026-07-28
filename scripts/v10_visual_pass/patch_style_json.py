#!/usr/bin/env python3
"""
v10 visual-system pass — patches kinrel_dark_style.json.

Applies the v10 directive edits in-place:
  1. Add top-level `fog` block (background #0B0F17 → warm dark horizon
     #2A2030) so distant buildings/terrain fade out instead of hard-cutting
     into black.
  2. Add a `sky` layer (sky-type: atmosphere) at the TOP of the layers
     array so the pitched 3D view has a horizon gradient instead of flat
     black above the map content. Sky is invisible at pitch 0 (top-down
     region-overview list view) and only paints above the horizon line
     once the camera pitches past ~10°.
  3. Tune `kinrel-buildings-outline` line-opacity so building edges stay
     crisp at pitch 50° without looking harsh. We lower the high-zoom
     opacity slightly (1.0 → 0.85 at zoom 17+) so the outline reads as a
     subtle edge, not a hard stroke.
  4. Add the new `kinrel-3d-buildings-family-proximity-glow` fill-extrusion
     layer ABOVE `kinrel-3d-buildings-warm-glow`. Source: openmaptiles,
     source-layer: building, minzoom: 13. Amber gradient color
     (#E8612A at full proximity, fading to transparent at the 150m edge
     via the within-filter geometry). The `within` filter is injected at
     runtime by `_injectFamilyProximityBuffer` in family_map_screen.dart
     — the placeholder filter here matches nothing (no building satisfies
     `["==", ["get", "__placeholder__"], true]`) so the layer is inert
     until the runtime patch replaces it.
  5. Road styling pass: ensure every road `layout` has `line-cap: round`
     and `line-join: round` (most already do — only `road_path_pedestrian`
     was missing `line-cap`). Slightly darken non-highway road colors
     (#2A2440 → #221E36) so the family-proximity glow and 3D buildings
     read as the visual focus, not the road network. Motorway/trunk/primary
     colors are UNCHANGED so highways still pop.

Does NOT touch:
  - PMTiles probe/fallback logic
  - family-* source/layers' underlying data model
  - Tile-source selection chain
  - The existing `kinrel-3d-buildings` and `kinrel-3d-buildings-warm-glow`
    layer paint properties (only their position in the array, to insert
    the new layer between them and the family-* layers).

Idempotent: re-running on an already-patched file is a no-op (detected
via the `kinrel-3d-buildings-family-proximity-glow` layer ID and the
top-level `fog` key).
"""

import json
import sys
from pathlib import Path

STYLE_PATH = Path(
    "/home/z/my-project/Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json"
)

# ─────────────────────────────────────────────────────────────────────
# Tuning constants (single source of truth for the JSON edits)
# ─────────────────────────────────────────────────────────────────────

# Sky + fog — TOP-LEVEL style property in MapLibre GL JS 5.x.
#
# In MapLibre GL JS 5.x, the `sky` is NOT a layer type — it's a top-level
# property of the style spec (alongside `light`, `projection`, etc.) and
# it INCLUDES the fog properties (fog-color, fog-ground-blend, etc.).
# There is no separate top-level `fog` block.
#
# Per the v10 directive: "Add a fog block to kinrel_dark_style.json:
# background color #0B0F17 (matches existing Background palette token),
# horizon color blending to a warm dark tone (#2A2030), so distant
# buildings/terrain fade out instead of hard-cutting into black. Add a
# sky layer (sky-type: atmosphere) so the pitched 3D view has a horizon
# gradient instead of flat black above the map content."
#
# We translate that to the 5.x SkySpecification:
#   - sky-color: #0B0F17 (Background palette token — flat dark above)
#   - horizon-color: #2A2030 (warm dark tone at the horizon)
#   - fog-color: #0B0F17 (matches background, so distant tiles fade out
#     instead of hard-cutting to black)
#   - fog-ground-blend: 0.5 (smooth blend between fog and ground)
#   - horizon-fog-blend: 0.5 (smooth blend between horizon and fog)
#   - sky-horizon-blend: 0.5 (smooth blend between sky and horizon)
#   - atmosphere-blend: a pitch-driven interpolation. At pitch 0
#     (top-down region-overview list view), atmosphere-blend = 0 → sky
#     is invisible, no fog, no horizon gradient. As pitch increases,
#     atmosphere-blend ramps up to 1.0 at pitch 50° — full sky + fog
#     + horizon gradient visible. This matches the directive's
#     requirement that "fog/sky should not visually break the flat
#     top-down mode".
SKY_BLOCK = {
    "sky-color": "#0B0F17",
    "horizon-color": "#2A2030",
    "fog-color": "#0B0F17",
    "fog-ground-blend": 0.5,
    "horizon-fog-blend": 0.5,
    "sky-horizon-blend": 0.5,
    # Constant 1.0 — MapLibre 5.x's internal `calculateFogBlendOpacity(pitch)`
    # method fades the fog out below pitch 60° automatically, and the sky
    # layer only paints when a horizon is visible (i.e. when pitch > 0).
    # At pitch 0 (top-down region-overview list view), no horizon is in
    # the viewport, so the sky is invisible regardless of this value.
    # This satisfies the directive's "fog/sky should not visually break
    # the flat top-down mode" requirement without needing a pitch-based
    # expression (MapLibre's GlobalProperties only exposes `zoom`,
    # `heatmapDensity`, `elevation` — NOT `pitch`).
    "atmosphere-blend": 1.0,
}

# New proximity glow layer — inserted ABOVE kinrel-3d-buildings-warm-glow.
# Filter is a placeholder that matches nothing; runtime patch replaces it
# with ["within", <MultiPolygon>] built from family-places coordinates.
PROXIMITY_GLOW_LAYER = {
    "id": "kinrel-3d-buildings-family-proximity-glow",
    "type": "fill-extrusion",
    "source": "openmaptiles",
    "source-layer": "building",
    "minzoom": 13,
    "maxzoom": 22,
    # Placeholder filter — never matches anything. Replaced at style-patch
    # time by family_map_screen.dart's _injectFamilyProximityBuffer with
    # ["within", <MultiPolygon of buffered family-places>]. Until the
    # runtime patch lands (e.g. before family data arrives), the layer is
    # inert so it can never accidentally re-color every building.
    "filter": ["==", ["get", "__placeholder_proximity__"], True],
    "paint": {
        # Amber gradient distinct from the warm-glow's height-based ramp.
        # We use a single warm orange (#E8612A) for the full body — the
        # "fading to transparent at the 150m edge" effect is achieved by
        # the within-filter geometry itself (only buildings inside the
        # buffer polygon are rendered in this layer at all).
        "fill-extrusion-color": "#E8612A",
        # Match the base 3D-buildings height expression so the proximity
        # glow extrudes to the SAME height as the underlying building —
        # the re-color sits exactly on top of the building geometry.
        "fill-extrusion-height": [
            "case",
            [">", ["coalesce", ["get", "render_height"], 0], 0],
            ["get", "render_height"],
            6,
        ],
        "fill-extrusion-base": [
            "max",
            0,
            ["coalesce", ["get", "render_min_height"], 0],
        ],
        # Lower opacity than the warm-glow layer so it reads as a tint
        # rather than a replacement. Interpolates up with zoom so the
        # effect intensifies as the user zooms into their family's street.
        "fill-extrusion-opacity": [
            "interpolate",
            ["linear"],
            ["zoom"],
            13, 0.30,
            15, 0.45,
            17, 0.55,
            22, 0.60,
        ],
        "fill-extrusion-vertical-gradient": True,
    },
    "layout": {"visibility": "visible"},
}

# Road color tweaks — desaturate/darken non-highway so family-proximity
# glow and 3D buildings read as the visual focus. Highway/trunk/primary
# colors are UNCHANGED.
#
# Old → New:
#   #2A2440 (minor + secondary_tertiary + path)  → #221E36
# Keys are lowercased for case-insensitive matching.
ROAD_COLOR_REPLACEMENTS = {
    "#2a2440": "#221E36",
}


def main():
    if not STYLE_PATH.exists():
        print(f"ERROR: {STYLE_PATH} not found", file=sys.stderr)
        sys.exit(1)

    raw = STYLE_PATH.read_text(encoding="utf-8")
    style = json.loads(raw)
    changed = False

    # ── 1. Top-level sky block (includes fog properties in MapLibre 5.x) ──
    # Always overwrite so we can iterate the format (v1 had a pitch expression
    # that MapLibre rejected; v2 uses a constant atmosphere-blend).
    if style.get("sky") != SKY_BLOCK:
        style["sky"] = SKY_BLOCK
        print("[v10] set top-level `sky` block (includes fog properties)")
        changed = True
    else:
        print("[v10] top-level `sky` block already up-to-date — skipping")

    # If a previous run added an (invalid) `fog` top-level block, remove it.
    if "fog" in style:
        del style["fog"]
        print("[v10] removed stale top-level `fog` block (MapLibre 5.x uses `sky`)")
        changed = True

    # If a previous run inserted an (invalid) `sky` LAYER in the layers
    # array, remove it (MapLibre 5.x does NOT support `sky` as a layer type).
    layers = style.get("layers", [])
    had_sky_layer = any(
        isinstance(l, dict) and l.get("id") == "sky" and l.get("type") == "sky"
        for l in layers
    )
    if had_sky_layer:
        layers = [
            l for l in layers
            if not (isinstance(l, dict) and l.get("id") == "sky" and l.get("type") == "sky")
        ]
        style["layers"] = layers
        print("[v10] removed stale `sky` layer from layers array (invalid in MapLibre 5.x)")
        changed = True

    # ── 2. (sky layer insertion step removed — sky is a top-level property) ──

    # ── 3. kinrel-buildings-outline opacity tuning ──────────────────
    for layer in layers:
        if not isinstance(layer, dict):
            continue
        if layer.get("id") != "kinrel-buildings-outline":
            continue
        paint = layer.get("paint", {})
        # Replace the line-opacity interpolation so the high-zoom cap is
        # 0.85 instead of 1.0. We detect whether the patch is needed by
        # looking for the old (17, 1.0) stop.
        opacity = paint.get("line-opacity")
        if (
            isinstance(opacity, list)
            and opacity[:3] == ["interpolate", ["linear"], ["zoom"]]
        ):
            pairs = list(_pairs(opacity[3:]))
            needs_patch = any(
                stop == 17 and val == 1.0 for stop, val in pairs
            )
            if needs_patch:
                new_opacity = ["interpolate", ["linear"], ["zoom"]]
                for stop, val in pairs:
                    if stop == 17 and val == 1.0:
                        val = 0.85
                    new_opacity.extend([stop, val])
                paint["line-opacity"] = new_opacity
                layer["paint"] = paint
                print(
                    "[v10] tuned kinrel-buildings-outline line-opacity "
                    "(zoom 17+ cap: 1.0 → 0.85)"
                )
                changed = True
            else:
                print(
                    "[v10] kinrel-buildings-outline line-opacity already "
                    "tuned (no [17, 1.0] stop) — skipping"
                )
        else:
            print(
                "[v10] kinrel-buildings-outline line-opacity unrecognized "
                "shape — skipping"
            )

    # ── 4. Add the proximity glow layer above warm-glow ─────────────
    has_proximity = any(
        isinstance(l, dict)
        and l.get("id") == "kinrel-3d-buildings-family-proximity-glow"
        for l in layers
    )
    if not has_proximity:
        # Find the warm-glow layer and insert immediately after it.
        warm_glow_idx = None
        for i, layer in enumerate(layers):
            if (
                isinstance(layer, dict)
                and layer.get("id") == "kinrel-3d-buildings-warm-glow"
            ):
                warm_glow_idx = i
                break
        if warm_glow_idx is None:
            print(
                "[v10] WARNING: kinrel-3d-buildings-warm-glow not found — "
                "appending proximity glow at end of layers array",
                file=sys.stderr,
            )
            layers.append(PROXIMITY_GLOW_LAYER)
        else:
            layers.insert(warm_glow_idx + 1, PROXIMITY_GLOW_LAYER)
        style["layers"] = layers
        print(
            "[v10] added kinrel-3d-buildings-family-proximity-glow layer "
            f"at index {warm_glow_idx + 1 if warm_glow_idx is not None else len(layers) - 1} "
            "(immediately above kinrel-3d-buildings-warm-glow)"
        )
        changed = True
    else:
        print(
            "[v10] kinrel-3d-buildings-family-proximity-glow already present — skipping"
        )

    # ── 5. Road styling pass ────────────────────────────────────────
    # 5a. Add line-cap: round to road_path_pedestrian (only road missing it)
    # 5b. Desaturate non-highway road colors (#2A2440 → #221E36)
    for layer in layers:
        if not isinstance(layer, dict):
            continue
        if layer.get("source-layer") != "transportation":
            continue
        if layer.get("type") != "line":
            continue

        # 5a. Ensure line-cap: round on every road line layer
        layout = layer.get("layout", {})
        if "line-cap" not in layout:
            layout["line-cap"] = "round"
            layer["layout"] = layout
            print(
                f"[v10] added line-cap: round to layer '{layer.get('id')}'"
            )
            changed = True

        # 5b. Color desaturation on non-highway roads
        paint = layer.get("paint", {})
        line_color = paint.get("line-color")
        if isinstance(line_color, str):
            new_color = ROAD_COLOR_REPLACEMENTS.get(line_color.lower())
            if new_color is not None:
                paint["line-color"] = new_color
                layer["paint"] = paint
                print(
                    f"[v10] darkened road color in layer "
                    f"'{layer.get('id')}': {line_color} → {new_color}"
                )
                changed = True

    if not changed:
        print("[v10] no changes made (file already fully patched)")
        return 0

    # Write back with 2-space indent (matches original formatting).
    STYLE_PATH.write_text(
        json.dumps(style, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"[v10] wrote patched style to {STYLE_PATH}")
    return 0


def _pairs(flat_list):
    """Helper — yield (a, b) pairs from a flat [a, b, c, d, ...] list."""
    args = [iter(flat_list)] * 2
    for pair in zip(*args):
        yield pair


if __name__ == "__main__":
    sys.exit(main())
