// lib/graph/widgets/engine/dot.dart
// P0.4: Extracted from family_graph_engine_view.dart.
//
// v5.111: Extended to support the MINI and MICRO tiers. The Dot class
// now carries an optional [initial] and [borderColor] so the mini
// painter can render a circle + border + initial letter, and the micro
// painter can render a colored circle + accent ring — all from the
// same data class. This avoids creating parallel data classes for each
// tier and keeps the single-painter performance optimization intact.

import 'package:flutter/material.dart';

/// A dot for the FAR-LOD node painter.
///
/// v5.111: Now also used by NodeMiniPainter and NodeMicroPainter.
/// The new fields [initial] and [borderColor] are optional — they are
/// only populated when the consuming painter needs them (MINI tier).
class Dot {
  const Dot(
    this.pos,
    this.color, {
    this.isEmphasised = false,
    this.initial,
    this.borderColor,
  });

  final Offset pos;
  final Color color;

  /// v96 (Phase 3): When true, this dot is drawn larger with an
  /// accent ring — used for focused/selected/path nodes at FAR zoom
  /// so they remain discoverable.
  final bool isEmphasised;

  /// v5.111: The first letter of the person's name (uppercased). Used
  /// by the MINI painter to render an initial inside the circle. When
  /// null, the MINI painter renders an empty circle.
  final String? initial;

  /// v5.111: The border color for the MINI painter. When null, the
  /// MINI painter derives the border from [color] (a darker shade).
  final Color? borderColor;
}
