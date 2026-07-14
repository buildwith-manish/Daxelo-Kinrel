// lib/graph/widgets/engine/node_role_glyph_badge.dart
// Extracted from graph_node.dart.
//
// Kinrel role glyph badge for a single GraphNode. Watches
// memberRoleGlyphProvider for the (familyId, memberId) pair and renders
// nothing if Kinrel hasn't been computed or the member has no role row
// yet — keeps the existing node visuals untouched.
//
// Extracted so graph_node.dart stays under 1,500 lines.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/kinrel_intelligence/providers/kinrel_provider.dart';
import '../../../features/kinrel_intelligence/widgets/role_glyph_badge.dart'
    show RoleGlyphBadge;

/// Kinrel role glyph badge for a single [GraphNode]. Watches
/// [memberRoleGlyphProvider] for the (familyId, memberId) pair and
/// renders nothing if Kinrel hasn't been computed or the member has no
/// role row yet — keeps the existing node visuals untouched.
class NodeRoleGlyphBadge extends ConsumerWidget {
  const NodeRoleGlyphBadge({
    required this.familyId,
    required this.memberId,
    required this.diameter,
  });

  final String familyId;
  final String memberId;
  final double diameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(
      memberRoleGlyphProvider(memberRoleKey(familyId, memberId)),
    );
    if (role == null) return const SizedBox.shrink();
    // Badge size scales with the node: 35% of the diameter, clamped to
    // 14–22px so it's visible on compact nodes without crowding large ones.
    final size = (diameter * 0.35).clamp(14.0, 22.0);
    return RoleGlyphBadge(role: role, size: size);
  }
}
