// lib/core/features/with_gaps.dart
//
// DAXELO KINREL — withGaps helper (Phase 2)
//
// Filters a list of (Widget, AppFeature) pairs by feature-state and
// inserts a gap widget between each surviving pair. Used to render a
// row of children where some children are hidden by feature flags
// without leaving dangling gaps or empty spacers.
//
// Example (HighlightsRow-style strip):
//
//   Row(children: withGaps(
//     ref,
//     gap: const SizedBox(width: 18),
//     items: [
//       _Tile(...).gatedBy(AppFeature.memories),
//       _Tile(...).gatedBy(AppFeature.oralHistory),
//       _Tile(...).gatedBy(AppFeature.achievements),
//     ],
//   ));
//
// If `memories` is OFF, only Oral History + Achievements tiles render
// with a single 18px gap between them (no leading/trailing gaps, no
// double gaps).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feature_registry.dart';

/// A pair of (Widget, AppFeature) used by [withGaps] to filter a list
/// of children by their feature gates.
class GatedWidget {
  const GatedWidget({required this.child, required this.feature});

  final Widget child;
  final AppFeature feature;
}

/// Filters [items] by their feature state (using [featureProvider]) and
/// returns a new list with [gap] inserted between each surviving item.
///
/// - Items whose feature is OFF are removed entirely.
/// - [gap] is inserted ONLY between visible items — never leading or
///   trailing, and never doubled up when adjacent items are hidden.
/// - When fewer than 2 items survive, no gap is inserted.
///
/// The [ref] is required to read [featureProvider]; the helper is
/// intended to be called from inside a `ConsumerWidget.build` or
/// `ConsumerStatefulWidget.build`.
List<Widget> withGaps(
  WidgetRef ref, {
  required Widget gap,
  required List<GatedWidget> items,
}) {
  final visible = items.where((i) => ref.watch(featureProvider(i.feature)));
  final result = <Widget>[];
  var first = true;
  for (final item in visible) {
    if (!first) result.add(gap);
    result.add(item.child);
    first = false;
  }
  return result;
}

/// Extension helper to make the call site read more declaratively:
///
///   withGaps(ref, gap: ..., items: [
///     _Tile(...).gatedBy(AppFeature.memories),
///     _Tile(...).gatedBy(AppFeature.oralHistory),
///   ])
extension GatedWidgetExtension on Widget {
  GatedWidget gatedBy(AppFeature feature) =>
      GatedWidget(child: this, feature: feature);
}
