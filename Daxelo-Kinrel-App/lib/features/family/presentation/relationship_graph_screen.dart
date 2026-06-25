// lib/features/family/presentation/relationship_graph_screen.dart
//
// DAXELO KINREL — Relationship Graph Screen
//
// Now powered by the V2.1 FamilyGraphWidget from lib/graph/.
// This screen wraps FamilyGraphWidget and provides it with the
// family context needed for data fetching and permission checks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/feature_flags.dart';
import '../../../graph/widgets/family_graph.dart';
import '../../../graph/widgets/family_graph_engine_view.dart';

class RelationshipGraphScreen extends ConsumerStatefulWidget {
  const RelationshipGraphScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<RelationshipGraphScreen> createState() =>
      _RelationshipGraphScreenState();
}

class _RelationshipGraphScreenState
    extends ConsumerState<RelationshipGraphScreen> {
  @override
  Widget build(BuildContext context) {
    return kUseV21Engine
        ? FamilyGraphEngineView(
            familyId: widget.familyId,
          )
        : FamilyGraphWidget(
            familyId: widget.familyId,
            familyName: 'Family Tree',
          );
  }
}
