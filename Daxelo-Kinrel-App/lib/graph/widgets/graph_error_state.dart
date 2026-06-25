// lib/graph/widgets/graph_error_state.dart
//
// Extracted from family_graph.dart (v31 refactor).
//
// Reusable error and empty-state widgets for the graph feature.
// Used by FamilyGraphWidget when graph data fails to load or when
// the layout produces no positions.
//
// Web + mobile compatible: pure Flutter widgets, no platform code.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart';

/// Error state widget for the family graph.
///
/// Shows an error icon, the error message, and a Retry button that
/// invalidates the [familyGraphProvider] for the given [familyId].
class GraphErrorState extends ConsumerWidget {
  const GraphErrorState({
    super.key,
    required this.familyId,
    required this.error,
  });

  final String familyId;
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48.0,
            color: KinrelColors.error,
          ),
          const SizedBox(height: 16.0),
          Text(
            'Failed to load graph',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            error.toString(),
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13.0,
              color: KinrelColors.textSilver,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
          ),
          const SizedBox(height: 16.0),
          ElevatedButton(
            onPressed: () {
              ref.invalidate(familyGraphProvider(familyId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: KinrelColors.orange,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Empty-stack wrapper — a minimal Stack that hosts the [EmptyState]
/// widget without any graph canvas. Used when the layout produces no
/// positions (e.g. all persons deleted) but we still want to show
/// the empty-state UI.
class GraphEmptyStack extends StatelessWidget {
  const GraphEmptyStack({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
      ],
    );
  }
}
