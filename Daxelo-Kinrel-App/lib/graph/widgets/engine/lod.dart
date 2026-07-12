// lib/graph/widgets/engine/lod.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// LOD (Level of Detail) tiers, chosen by camera zoom.

/// LOD tiers, chosen by camera zoom.
enum Lod {
  /// Full interactive node cards.
  full,

  /// Lightweight name-only chips.
  chip,

  /// Single painter draws every node as a dot (max scale).
  dot,
}
