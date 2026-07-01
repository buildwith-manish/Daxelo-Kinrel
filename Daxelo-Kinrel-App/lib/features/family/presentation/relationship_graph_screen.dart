// lib/features/family/presentation/relationship_graph_screen.dart
//
// DAXELO KINREL — Relationship Graph Screen
//
// Powered by FamilyGraphEngineView (the V2.1 engine).
// The old FamilyGraphWidget (v40) has been removed —
// FamilyGraphEngineView is the sole graph renderer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return FamilyGraphEngineView(
      familyId: widget.familyId,
    );
  }
}
