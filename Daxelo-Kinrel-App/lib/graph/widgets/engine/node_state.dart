// lib/graph/widgets/engine/node_state.dart
// Extracted from graph_node.dart to break the import cycle between
// graph_node.dart and node_decoration.dart (the painter needs NodeState
// but graph_node.dart needs the painter). Matches the lod.dart precedent
// of extracting small enums into their own files under widgets/engine/.

/// All possible visual states for a graph node.
enum NodeState {
  /// Standard appearance with relationship-colored border ring.
  normal,

  /// Scale up 7%, elevated shadow, tooltip preview.
  /// Desktop: cursor enter; Mobile: long-press proximity.
  hover,

  /// Accent border glow, background tint, info sheet appears.
  selected,

  /// Pulsing glow animation, camera centers on node.
  focused,

  /// Expand indicator rotates, new nodes animate in.
  expanded,

  /// Shimmer animation, spinner on expand indicator.
  loading,

  /// Red border pulse, error icon overlay, tap to retry.
  error,
}
