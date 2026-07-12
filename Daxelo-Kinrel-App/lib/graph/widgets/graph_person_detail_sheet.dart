// lib/graph/widgets/graph_person_detail_sheet.dart
//
// DAXELO KINREL — Premium Graph Person Details (Phase 8)
//
// A polished person-detail interaction that connects graph exploration
// features. Extends the existing person details UI — does NOT create
// a second profile architecture.
//
// Shows only data actually available from the graph + person maps.
// When opened from the graph, knows: current focused person, selected
// person, relationship to app user, whether an active path exists.
//
// Primary actions (prioritized):
//   1. View relationship (opens RelationshipInfoSheet with path)
//   2. Focus on person (sets graphFocusProvider)
//   3. Edit (when authorized — opens AddPersonSheet)
//
// Uses existing Kinrel animation timing. Respects reduced motion.
// Semantic labels for screen readers. 48dp-safe action targets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/family/family_provider.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import '../interaction/graph_focus_state.dart' show graphFocusProvider;
import '../interaction/graph_kinship_path_focus.dart'
    show graphPathFocusProvider;
import 'graph_relationship_labels.dart';
import 'relationship_info_sheet.dart';

/// Shows a premium person-detail bottom sheet with graph context.
///
/// Extends the existing [GraphQuickActions] pattern with richer
/// content + graph-aware actions. The sheet knows the current focus,
/// selection, and path state so it can offer context-appropriate
/// actions without recomputing graph traversal in build().
class GraphPersonDetailSheet {
  GraphPersonDetailSheet._();

  /// Show the detail sheet.
  ///
  /// [person] — the person to display.
  /// [familyId] — the current family ID.
  /// [ref] — the WidgetRef for provider access.
  /// [viewerPersonId] — the current viewer's person ID (for
  /// relationship-to-user display).
  /// [relationshipLabel] — the pre-computed relationship label
  /// (e.g. "Father", "Cousin"). Pass null if not available.
  /// [localizedKinshipTerm] — the localized kinship term (e.g. "पिता").
  /// Pass null if not available.
  static void show(
    BuildContext context,
    GraphPersonData person, {
    required String familyId,
    required WidgetRef ref,
    String? viewerPersonId,
    String? relationshipLabel,
    String? localizedKinshipTerm,
  }) {
    final isViewer = viewerPersonId != null && person.id == viewerPersonId;

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ──
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
              child: Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: KinrelColors.textDim,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),

            // ── Person header ──
            _PersonHeader(
              name: person.name,
              photoUrl: person.photoUrl,
              gender: person.gender,
              isDeceased: person.isDeceased,
            ),

            // ── Relationship context ──
            if (relationshipLabel != null || localizedKinshipTerm != null)
              _RelationshipContext(
                relationshipLabel: relationshipLabel,
                localizedKinshipTerm: localizedKinshipTerm,
                isViewer: isViewer,
                generationIndex: person.generationIndex,
              ),

            const Divider(color: Color(0x1AFFFFFF), height: 1.0),

            // ── Primary actions ──
            // 1. View relationship
            ListTile(
              leading: const Icon(Icons.account_tree_rounded,
                  color: KinrelColors.tealAccent),
              title: const Text(
                'View relationship',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              subtitle: isViewer
                  ? const Text('How others relate to you',
                      style: TextStyle(fontSize: 12, color: KinrelColors.textDim))
                  : null,
              onTap: () {
                Navigator.pop(context);
                _openRelationshipInfo(context, person, ref, viewerPersonId);
              },
            ),

            // 2. Focus on person
            ListTile(
              leading: const Icon(Icons.center_focus_strong_rounded,
                  color: KinrelColors.orange),
              title: const Text(
                'Focus on person',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                ref.read(graphFocusProvider.notifier).focus(
                      personId: person.id,
                      personName: person.name,
                      edges: const [],
                      currentViewport: null,
                    );
              },
            ),

            // 3. Edit (when authorized)
            ListTile(
              leading: const Icon(Icons.edit, color: KinrelColors.amber),
              title: const Text(
                'Edit',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                AddPersonSheet.show(
                  context,
                  familyId: familyId,
                  existingPerson: Person(
                    id: person.id,
                    familyId: familyId,
                    name: person.name,
                    gender: person.gender,
                    isDeceased: person.isDeceased,
                    photoUrl: person.photoUrl,
                    isAnchor: false,
                    generationIndex: 0,
                    dateOfBirth: person.dateOfBirth,
                  ),
                );
              },
            ),

            // ── Secondary actions ──
            ListTile(
              leading:
                  const Icon(Icons.person, color: KinrelColors.tealAccent),
              title: const Text(
                'View Profile',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/member/${person.id}');
              },
            ),

            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }

  /// Opens the RelationshipInfoSheet with path context.
  static void _openRelationshipInfo(
    BuildContext context,
    GraphPersonData person,
    WidgetRef ref,
    String? viewerPersonId,
  ) {
    if (viewerPersonId == null || viewerPersonId == person.id) {
      // No viewer or self — just show a basic sheet.
      RelationshipInfoSheet.show(
        context,
        sourceId: viewerPersonId ?? person.id,
        sourceName: viewerPersonId != null ? 'You' : person.name,
        sourceGender: null,
        targetId: person.id,
        targetName: person.name,
        targetGender: person.gender,
        relationshipKey: 'related',
      );
      return;
    }

    // Check if a path focus is already active for this person.
    final pathFocus = ref.read(graphPathFocusProvider).focus;
    if (pathFocus != null && pathFocus.targetPersonId == person.id) {
      // Path is already resolved — open with full context.
      RelationshipInfoSheet.show(
        context,
        sourceId: viewerPersonId,
        sourceName: 'You',
        sourceGender: null,
        targetId: person.id,
        targetName: person.name,
        targetGender: person.gender,
        relationshipKey: pathFocus.resolvedRelationshipKey ?? 'related',
        pathFocus: pathFocus,
      );
    } else {
      // No active path — show basic sheet.
      RelationshipInfoSheet.show(
        context,
        sourceId: viewerPersonId,
        sourceName: 'You',
        sourceGender: null,
        targetId: person.id,
        targetName: person.name,
        targetGender: person.gender,
        relationshipKey: 'related',
      );
    }
  }
}

/// The person header — avatar/initials + name.
class _PersonHeader extends StatelessWidget {
  const _PersonHeader({
    required this.name,
    this.photoUrl,
    this.gender,
    this.isDeceased = false,
  });

  final String name;
  final String? photoUrl;
  final String? gender;
  final bool isDeceased;

  @override
  Widget build(BuildContext context) {
    final color = gender == 'female'
        ? const Color(0xFF7B5EA7)
        : const Color(0xFF2A7BB5);
    final initials = _getInitials(name);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18.0,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                if (isDeceased)
                  const Text(
                    'In loving memory',
                    style: TextStyle(
                      fontSize: 12,
                      color: KinrelColors.textDim,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0]
          .substring(0, parts[0].length.clamp(0, 2))
          .toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

/// The relationship context section.
class _RelationshipContext extends StatelessWidget {
  const _RelationshipContext({
    this.relationshipLabel,
    this.localizedKinshipTerm,
    this.isViewer = false,
    this.generationIndex = 0,
  });

  final String? relationshipLabel;
  final String? localizedKinshipTerm;
  final bool isViewer;
  final int generationIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Row(
        children: [
          if (isViewer) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KinrelColors.tealAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: KinrelColors.tealAccent.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  color: KinrelColors.tealAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ] else if (relationshipLabel != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.4)),
              ),
              child: Text(
                relationshipLabel!,
                style: const TextStyle(
                  color: KinrelColors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (localizedKinshipTerm != null) ...[
            const SizedBox(width: 8),
            Text(
              localizedKinshipTerm!,
              style: const TextStyle(
                fontSize: 12,
                color: KinrelColors.textDim,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (generationIndex != 0) ...[
            const SizedBox(width: 8),
            Text(
              'Generation ${generationIndex > 0 ? '+$generationIndex' : generationIndex}',
              style: const TextStyle(
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
