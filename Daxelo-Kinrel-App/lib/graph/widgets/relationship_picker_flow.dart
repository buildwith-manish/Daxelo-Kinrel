// lib/graph/widgets/relationship_picker_flow.dart
//
// DAXELO KINREL — Shared Relationship Picker Flow (v5.10)
//
// Extracted from GraphQuickActions._showPersonListAndAutoCreate so it
// can be reused by both:
//   1. The "Relate to another person" action in GraphQuickActions
//   2. The "Needs Linking" sheet in unlinked_members_sheet.dart
//
// This is the SINGLE source of truth for the flexible person-picker +
// auto-relationship-creation flow. Do not duplicate this logic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/family/family_provider.dart';
import '../../core/kinship/kinship_inference_engine.dart';
import '../../features/family/presentation/fundamental_relationship_picker.dart';
import '../interaction/relationship_validation.dart'
    show RelationshipValidationException;
import 'graph_relationship_labels.dart';

/// Shows a bottom-sheet picker of ALL family members (except [sourcePerson]),
/// lets the user pick ANY of them, then either auto-derives the kinship
/// from existing edges or opens FundamentalRelationshipPicker
/// (parent/child/spouse/sibling), then persists via createRelationship().
///
/// This is the "flexible relate to any person" flow — the user can connect
/// [sourcePerson] to ANY other person in the family, including people who
/// are themselves also unlinked.
///
/// Parameters:
/// - [context] — the build context for showing the bottom sheet + snackbars
/// - [ref] — the WidgetRef for provider access
/// - [familyId] — the family ID
/// - [sourcePerson] — the person to connect FROM (pre-selected)
/// - [onComplete] — optional callback invoked after a relationship is
///   successfully created (or the user cancels). Receives `true` if a
///   relationship was created, `false` if cancelled.
///
/// Usage:
/// ```dart
/// await showRelationshipPickerFlow(
///   context: context,
///   ref: ref,
///   familyId: familyId,
///   sourcePerson: GraphPersonData(id: '...', name: '...'),
///   onComplete: (created) {
///     if (created) {
///       // Relationship was created — refresh unlinked list etc.
///     }
///   },
/// );
/// ```
Future<void> showRelationshipPickerFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String familyId,
  required GraphPersonData sourcePerson,
  void Function(bool created)? onComplete,
}) async {
  final detailAsync = ref.read(familyDetailProvider(familyId));
  final detail = detailAsync.valueOrNull;

  if (detail == null || detail.members.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other family members to relate to.'),
          backgroundColor: KinrelColors.darkCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onComplete?.call(false);
    return;
  }

  // Include ALL members (except self + deleted).
  final eligiblePersons = detail.members
      .where((p) => p.id != sourcePerson.id && p.deletedAt == null)
      .toList();

  if (eligiblePersons.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No other family members to connect to ${sourcePerson.name}. '
            'Add more members first.',
          ),
          backgroundColor: KinrelColors.darkCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onComplete?.call(false);
    return;
  }

  // Resolve kinship labels for each eligible person (relative to source)
  String kinshipLabelFor(Person other) {
    for (final rel in detail.relationships) {
      if (rel.fromPersonId == other.id && rel.toPersonId == sourcePerson.id) {
        return GraphRelationshipLabels.formatKey(rel.relationshipKey);
      }
      if (rel.fromPersonId == sourcePerson.id && rel.toPersonId == other.id) {
        return GraphRelationshipLabels.formatKey(
            GraphRelationshipLabels.getInverseKey(rel.relationshipKey));
      }
    }
    return '';
  }

  // Show bottom sheet
  if (!context.mounted) {
    onComplete?.call(false);
    return;
  }
  final selectedPerson = await showModalBottomSheet<Person>(
    context: context,
    backgroundColor: KinrelColors.darkCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect ${sourcePerson.name} to…',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18.0,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap a family member — we\'ll auto-detect the relationship.',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0x1AFFFFFF), height: 1.0),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: eligiblePersons.length,
              itemBuilder: (ctx, i) {
                final p = eligiblePersons[i];
                final label = kinshipLabelFor(p);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        KinrelColors.tealAccent.withValues(alpha: 0.15),
                    backgroundImage: p.photoUrl != null && p.photoUrl!.isNotEmpty
                        ? NetworkImage(p.photoUrl!)
                        : null,
                    child: (p.photoUrl == null || p.photoUrl!.isEmpty)
                        ? Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: KinrelColors.tealAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    p.name,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  subtitle: label.isNotEmpty
                      ? Text(
                          'Already: $label',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.amber,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, p),
                );
              },
            ),
          ),
          const SizedBox(height: 8.0),
        ],
      ),
    ),
  );

  if (selectedPerson == null) {
    onComplete?.call(false);
    return; // User cancelled
  }

  // Look up the source Person from detail.members to get the full record
  final sourcePersonRecord = detail.members.firstWhere(
    (p) => p.id == sourcePerson.id,
    orElse: () => Person(
      id: sourcePerson.id,
      familyId: familyId,
      name: sourcePerson.name,
      gender: sourcePerson.gender,
    ),
  );

  final candidates = KinshipInferenceEngine.infer(
    personA: sourcePersonRecord,
    personB: selectedPerson,
    existingRelationships: detail.relationships,
  );

  String relationshipKey;

  if (candidates.isNotEmpty &&
      candidates.first.confidence >= 0.85 &&
      candidates.first.key != 'spouse' &&
      candidates.first.key != 'husband' &&
      candidates.first.key != 'wife') {
    // Auto-detected with high confidence — use it directly
    relationshipKey = candidates.first.key;
  } else {
    // Open the FundamentalRelationshipPicker
    if (!context.mounted) {
      onComplete?.call(false);
      return;
    }
    final fundamentalKey = await FundamentalRelationshipPicker.show(
      context,
      personAName: sourcePerson.name,
      personBName: selectedPerson.name,
      personAGender: sourcePerson.gender,
      personBGender: selectedPerson.gender,
    );
    if (fundamentalKey == null) {
      onComplete?.call(false);
      return;
    }
    relationshipKey = fundamentalKey;
  }

  // Create the relationship
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await createRelationship(
      ref: ref,
      familyId: familyId,
      fromPersonId: sourcePerson.id,
      toPersonId: selectedPerson.id,
      relationshipKey: relationshipKey,
      fromPersonGender: sourcePersonRecord.gender,
      toPersonGender: selectedPerson.gender,
    );

    final label = KinshipInferenceEngine.labelFor(relationshipKey);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'Connected: ${selectedPerson.name} is the $label of ${sourcePerson.name}',
        ),
        backgroundColor: KinrelColors.darkCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
    onComplete?.call(true);
  } catch (e) {
    String friendlyError;
    if (e is RelationshipValidationException) {
      if (e.code == 'self_relationship') {
        friendlyError = 'Choose two different family members.';
      } else if (e.code == 'duplicate_relationship') {
        friendlyError =
            '${sourcePerson.name} and ${selectedPerson.name} are already connected.';
      } else if (e.code == 'duplicate_parent') {
        friendlyError = 'This person already has a parent.';
      } else if (e.code == 'circular_parentage') {
        friendlyError = 'This connection would create a family cycle.';
      } else {
        friendlyError = 'Couldn\'t create this connection. ${e.message}';
      }
    } else {
      friendlyError = 'Couldn\'t create this connection. Please try again.';
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(friendlyError),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
    onComplete?.call(false);
  }
}
