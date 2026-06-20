// lib/graph/widgets/graph_node_state.dart
//
// Extracted from family_graph.dart (v31 refactor).
//
// Pure-logic helpers for resolving node visual state (selected,
// focused, anonymous) and responsive node sizing based on viewport
// width + zoom level.
//
// Web + mobile compatible: uses only Flutter foundation APIs.

import 'graph_node.dart' show NodeState;

/// Resolves the visual state of a graph node.
class GraphNodeStateResolver {
  GraphNodeStateResolver._();

  /// Returns the [NodeState] for a node given its selection / focus /
  /// anonymity flags. Anonymous nodes always render as 'normal'
  /// regardless of selection (they have no identity to highlight).
  static NodeState resolve({
    required bool isSelected,
    required bool isFocused,
    required bool isAnonymous,
  }) {
    if (isAnonymous) return NodeState.normal;
    if (isFocused) return NodeState.focused;
    if (isSelected) return NodeState.selected;
    return NodeState.normal;
  }

  /// Resolves responsive node size based on screen-width breakpoints
  /// (per V2.1 Blueprint §20), combined with zoom level.
  ///
  /// Breakpoints:
  ///   < 400px  → 48.0  (iPhone SE, small Android)
  ///   < 720px  → 56.0  (iPhone 15, Pixel 8)
  ///   < 1024px → 60.0  (large phones, small tablets)
  ///   ≥ 1024px → 64.0  (iPad Air, desktop web browser)
  ///
  /// Zoom-level scaling:
  ///   < 0.5    → ×0.85 (compact at zoom-out)
  ///   < 0.8    → ×0.95
  ///   < 1.5    → ×1.0  (default)
  ///   ≥ 1.5    → ×1.05 (slight bump at zoom-in)
  static double resolveSize({
    required double viewportWidth,
    required double zoomLevel,
  }) {
    double baseSize;
    if (viewportWidth < 400) {
      baseSize = 48.0;
    } else if (viewportWidth < 720) {
      baseSize = 56.0;
    } else if (viewportWidth < 1024) {
      baseSize = 60.0;
    } else {
      baseSize = 64.0;
    }

    if (zoomLevel < 0.5) return baseSize * 0.85;
    if (zoomLevel < 0.8) return baseSize * 0.95;
    if (zoomLevel < 1.5) return baseSize;
    return baseSize * 1.05;
  }
}
