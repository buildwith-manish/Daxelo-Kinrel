// lib/graph/rendering/edge_quality.dart
//
// DAXELO KINREL — Edge Visual Quality Tier (v91, 2026-07-12)
//
// LOD-aware edge quality. Computed ONCE from the current graph LOD
// inside FamilyGraphEngineView and passed to _EngineEdgePainter.
// Painters must NOT independently derive visual quality per edge —
// they read from this enum so the entire edge layer upgrades or
// downgrades in lockstep with the node layer.

/// Visual quality tier for relationship edges.
///
/// Maps 1:1 to the node LOD tiers (`_Lod.full` / `_Lod.chip` / `_Lod.dot`)
/// but is kept as a separate type so the edge painter can be tested in
/// isolation without pulling in the private `_Lod` enum.
enum EdgeQuality {
  /// FULL LOD — premium physical thread.
  /// • contact shadow (PASS 1)
  /// • relationship body (PASS 2)
  /// • directional light ridge (PASS 3)
  /// • premium dot/heart midpoint
  /// • selected-edge sweep allowed
  full,

  /// CHIP LOD — lighter physical thread.
  /// • lighter/tighter contact shadow
  /// • relationship body
  /// • reduced ridge
  /// • smaller midpoint
  chip,

  /// DOT LOD — minimal stroke only.
  /// • simple relationship-coloured stroke
  /// • NO MaskFilter blur per normal edge
  /// • NO midpoint gradient
  /// • NO specular highlight
  /// • midpoint symbols omitted
  /// • static selected-edge focus allowed (no animated sweep)
  dot,
}

/// Extension with convenience predicates so painters can branch cleanly.
extension EdgeQualityX on EdgeQuality {
  /// True when this tier allows MaskFilter.blur on normal (non-selected)
  /// edges.
  bool get allowsBlur => this == EdgeQuality.full || this == EdgeQuality.chip;

  /// True when this tier allows the premium directional light ridge.
  bool get allowsRidge => this == EdgeQuality.full || this == EdgeQuality.chip;

  /// True when this tier allows midpoint symbols (bead / heart).
  bool get allowsMidpoint =>
      this == EdgeQuality.full || this == EdgeQuality.chip;

  /// True when this tier allows the one-shot selected-edge sweep
  /// animation. At DOT LOD the sweep is suppressed for performance
  /// unless profiling proves it safe.
  bool get allowsSweep => this == EdgeQuality.full;

  /// Shadow sigma to use at this tier (from the GraphLighting contract).
  double get shadowSigma {
    switch (this) {
      case EdgeQuality.full:
        return 2.8; // GraphLighting.fullShadowSigma
      case EdgeQuality.chip:
        return 1.6; // GraphLighting.chipShadowSigma
      case EdgeQuality.dot:
        return 0.0; // no blur at DOT LOD
    }
  }

  /// Ridge alpha to use at this tier (from the GraphLighting contract).
  double get ridgeAlpha {
    switch (this) {
      case EdgeQuality.full:
        return 0.26; // GraphLighting.fullRidgeAlpha
      case EdgeQuality.chip:
        return 0.14; // GraphLighting.chipRidgeAlpha
      case EdgeQuality.dot:
        return 0.0; // no ridge at DOT LOD
    }
  }
}
