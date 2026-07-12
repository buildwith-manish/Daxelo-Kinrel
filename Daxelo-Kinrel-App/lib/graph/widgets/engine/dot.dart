// lib/graph/widgets/engine/dot.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'package:flutter/material.dart';

/// A dot for the FAR-LOD node painter.
class Dot {
  const Dot(this.pos, this.color, {this.isEmphasised = false});
  final Offset pos;
  final Color color;
  /// v96 (Phase 3): When true, this dot is drawn larger (9px) with an
  /// accent ring — used for focused/selected/path nodes at FAR zoom
  /// so they remain discoverable.
  final bool isEmphasised;
}
