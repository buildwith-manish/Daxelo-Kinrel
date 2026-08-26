// lib/graph/widgets/engine/lod.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// LOD (Level of Detail) tiers, chosen by camera zoom.
//
// v5.111 (SEMANTIC ZOOM OVERHAUL): Expanded from 3 tiers to 5 tiers so
// nodes degrade GRADUALLY as the user zooms out instead of collapsing
// from a 72dp premium medallion to a 10px dot in two abrupt steps.
//
// The new intermediate tiers (mini, micro) preserve node recognizability:
//   • mini  — circle + border + initial letter (screen-space clamped to 22px)
//   • micro — colored circle + accent ring (screen-space clamped to 16px)
//
// The DOT tier is now reserved for TRUE far-zoom only (entire tree visible)
// and its minimum dot size has been raised from 10px to 14px so even at
// maximum zoom-out the dots remain visible markers of branch structure.

/// LOD tiers, chosen by camera zoom.
enum Lod {
  /// Full interactive node cards (72dp premium GraphNode widgets).
  /// Rendered at NEAR zoom — full name + kinship label + 2.5D depth.
  full,

  /// Compact premium node (72dp graph-space, simplified paint).
  /// Rendered at COMPACT zoom — relation label faded, name still visible.
  /// v5.111: NEW tier between full and chip.
  compact,

  /// Mini node: circle + border + initial letter.
  /// Rendered at MINI zoom — screen-space clamped to 22px so nodes
  /// remain recognizable circles with a letter, not anonymous dots.
  /// v5.111: NEW tier.
  mini,

  /// Micro node: colored circle + accent ring (no letter).
  /// Rendered at MICRO zoom — screen-space clamped to 16px.
  /// v5.111: NEW tier — the last tier before dot.
  micro,

  /// Lightweight name-only chips (legacy MEDIUM tier).
  /// Kept for backward compatibility with focus-mode flooring.
  chip,

  /// Single painter draws every node as a dot (max scale).
  /// v5.111: Now reserved for TRUE far-zoom only (< 0.16 default).
  /// Minimum dot size raised from 10px to 14px for visibility.
  dot,
}
