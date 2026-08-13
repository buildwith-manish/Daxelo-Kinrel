// lib/graph/widgets/graph_quick_actions.dart
//
// Extracted from family_graph.dart (v31 refactor).
//
// The bottom sheet that appears when a user taps-holds a graph node.
// Shows the person's name + quick actions (View Profile, Edit, Remove Member).
//
// Web + mobile compatible: uses standard Material showModalBottomSheet,
// which renders as a modal dialog on web (no platform-specific code).
//
// v95 (Phase 1): Added "Focus on person" action that sets
// [graphFocusProvider] — the person-centric focus mode. This is
// SEPARATE from transient selection: focusing a person centers the
// camera, dims unrelated branches, and pushes the current viewport
// onto the focus history stack so the user can go back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/family/family_provider.dart';
import '../../core/relationship/relationship_engine.dart';
import '../../core/services/graph_layout_service.dart' show GraphPerson;
import '../../core/services/supabase_service.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import '../../features/family/presentation/relationship_picker_sheet.dart';
import '../interaction/graph_focus_state.dart';
import '../interaction/relationship_linking_state.dart';
import '../interaction/relationship_validation.dart' show RelationshipValidationException;
import 'graph_relationship_labels.dart';

/// Shows a modal bottom sheet with quick actions for a graph node.
///
/// Extracted from the FamilyGraphWidget's `_showQuickActions` method
/// so the sheet can be reused by other entry points (e.g. the info
/// card, the 3D tree view) without duplicating ~80 lines of UI code.
class GraphQuickActions {
  GraphQuickActions._();

  /// Shows the quick-actions sheet for [person].
  ///
  /// Callers should pass the person's [GraphPersonData] — the sheet
  /// displays the name and provides 'View Profile', 'Edit',
  /// 'Focus on person', and 'Remove Member' actions.
  ///
  /// [familyId] is required for the Remove Member action.
  /// [isOwner] controls whether the Remove Member option is shown.
  /// [isSelf] prevents the owner from removing themselves.
  /// [ref] is required for the Focus action (sets graphFocusProvider).
  static void show(
    BuildContext context,
    GraphPersonData person, {
    String? familyId,
    bool isOwner = false,
    bool isSelf = false,
    WidgetRef? ref,
    void Function(String personId, String personName)? onFocusPerson,
    void Function(String personId)? onViewRelationship,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
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
            // Person name
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
              child: Text(
                person.name,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1.0),
            // View Profile
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
                Navigator.pop(sheetContext);
                if (familyId != null) {
                  context.push('/member/${person.id}');
                }
              },
            ),
            // v98 (Phase 2): "How are we related?" — resolves the
            // relationship path from the viewer to this person.
            if (onViewRelationship != null)
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
                onTap: () {
                  Navigator.pop(sheetContext);
                  onViewRelationship(person.id);
                },
              ),
            // v98 (Phase 1): Focus on person — uses engine-owned callback
            // that has access to real edges + camera viewport.
            // Falls back to direct provider call if no callback (legacy).
            if (onFocusPerson != null || ref != null)
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
                  Navigator.pop(sheetContext);
                  if (onFocusPerson != null) {
                    onFocusPerson(person.id, person.name);
                  } else if (ref != null) {
                    ref.read(graphFocusProvider.notifier).focus(
                          personId: person.id,
                          personName: person.name,
                          edges: const [],
                          currentViewport: null,
                        );
                  }
                },
              ),
            // P3.4: "Light a candle" action for deceased persons.
            // Visual only — places a brief brighter candle that fades
            // over 3 seconds. Local-only interaction (no backend record);
            // it's a moment, not a metric.
            if (person.isDeceased)
              ListTile(
                leading: const Icon(Icons.local_fire_department_outlined,
                    color: KinrelColors.amber),
                title: const Text(
                  'Light a candle',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showLightACandleToast(context, person.name);
                },
              ),
            // P3.4: "View memorial" action for deceased persons.
            // Opens the Pitru memorials screen (existing module).
            if (person.isDeceased && familyId != null)
              ListTile(
                leading: const Icon(Icons.favorite_outline,
                    color: KinrelColors.extendedPurple),
                title: const Text(
                  'View memorial',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/memorials?familyId=$familyId');
                },
              ),
            // Edit
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
                Navigator.pop(sheetContext);
                if (familyId != null) {
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
                }
              },
            ),
            // v141: "Relate to another person" — opens a person picker,
            // then the existing RelationshipPickerSheet, then calls
            // createRelationship() to add an edge between the two
            // existing nodes. Reuses the app's entire kinship system.
            if (familyId != null && ref != null)
              ListTile(
                leading: const Icon(Icons.link_rounded,
                    color: KinrelColors.tealAccent),
                title: const Text(
                  'Relate to another person',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  // v150: Simple list picker + automatic kinship detection.
                  // No graph linking mode, no multi-step selection.
                  // Show a bottom sheet → user picks one person →
                  // system auto-determines kinship → creates relationship.
                  _showPersonListAndAutoCreate(
                    context,
                    ref!,
                    familyId!,
                    person,
                  );
                },
              ),
            // Remove Member — shown for all non-self nodes (not just non-anchor)
            if (!isSelf && familyId != null) ...[
              const Divider(color: Color(0x1AFFFFFF), height: 1.0),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove Member',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRemoveConfirmation(
                    context,
                    person,
                    familyId,
                  );
                },
              ),
            ],
            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }

  /// P3.4: Shows a brief "a candle has been lit" toast for [personName].
  ///
  /// This is a local-only moment (no backend record) — it's a moment,
  /// not a metric. The toast auto-dismisses after 3 seconds, matching
  /// the spec's "brief brighter candle that fades over 3 seconds."
  static void _showLightACandleToast(BuildContext context, String personName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A candle has been lit for $personName',
          style: const TextStyle(
            color: KinrelColors.textWhite,
            fontFamily: KinrelTypography.bodyFont,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// v150: Shows a bottom sheet of eligible family members, then
  /// automatically determines + creates the relationship when one is
  /// selected. No graph linking mode, no multi-step selection.
  ///
  /// Flow:
  /// 1. Show bottom sheet with eligible persons (excludes self +
  ///    already-related)
  /// 2. User taps one person → sheet closes
  /// 3. RelationshipEngine auto-determines kinship
  /// 4. createRelationship() creates the edge + refreshes graph
  /// 5. Success/error SnackBar
  static void _showPersonListAndAutoCreate(
    BuildContext context,
    WidgetRef ref,
    String familyId,
    GraphPersonData sourcePerson,
  ) async {
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
      return;
    }

    // Build set of directly-related IDs to exclude
    final directlyRelatedIds = <String>{};
    for (final rel in detail.relationships) {
      if (rel.fromPersonId == sourcePerson.id) {
        directlyRelatedIds.add(rel.toPersonId);
      } else if (rel.toPersonId == sourcePerson.id) {
        directlyRelatedIds.add(rel.fromPersonId);
      }
    }

    // Filter: exclude source person + already-related persons
    final eligiblePersons = detail.members
        .where((p) => p.id != sourcePerson.id && !directlyRelatedIds.contains(p.id))
        .toList();

    if (eligiblePersons.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Everyone in this family is already connected to ${sourcePerson.name}.'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
    if (!context.mounted) return;
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
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
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
                    'Select a family member — we\'ll determine the relationship automatically.',
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
                      backgroundColor: KinrelColors.tealAccent.withValues(alpha: 0.15),
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
                            label,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: KinrelColors.tealAccent,
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

    if (selectedPerson == null) return; // User cancelled

    // Auto-detect kinship + create relationship
    debugPrint('[RelateToPerson] ${sourcePerson.name} → ${selectedPerson.name}');

    // Build GraphPerson list for RelationshipEngine
    final graphPersons = detail.members.map((p) => GraphPerson(
      id: p.id,
      name: p.name,
      gender: p.gender,
      generationIndex: p.generationIndex,
      isAnchor: p.isAnchor,
      photoUrl: p.photoUrl,
      isDeceased: p.isDeceased,
    )).toList();

    final relTuples = detail.relationships.map((r) =>
      (fromId: r.fromPersonId, toId: r.toPersonId, type: r.relationshipKey)
    ).toList();

    // Resolve kinship from sourcePerson's perspective
    final classification = RelationshipEngine.instance.resolveClassification(
      viewerPersonId: sourcePerson.id,
      targetPersonId: selectedPerson.id,
      persons: graphPersons,
      relationships: relTuples,
    );

    String relationshipKey;

    if (classification != null && classification.key.isNotEmpty) {
      // Auto-detected!
      relationshipKey = classification.key;
      debugPrint('[RelateToPerson] Auto-detected: $relationshipKey');
    } else {
      // Couldn't auto-detect — fall back to manual picker
      debugPrint('[RelateToPerson] Auto-detect failed — manual picker');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('We couldn\'t determine the relationship automatically. Please choose.'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!context.mounted) return;
      final manualKey = await RelationshipPickerSheet.show(
        context,
        personAName: sourcePerson.name,
        personBName: selectedPerson.name,
      );
      if (manualKey == null) return;
      relationshipKey = manualKey;
    }

    // Create the relationship
    debugPrint('[RelateToPerson] Creating: ${sourcePerson.id} → ${selectedPerson.id} as $relationshipKey');
    try {
      await createRelationship(
        ref: ref,
        familyId: familyId,
        fromPersonId: sourcePerson.id,
        toPersonId: selectedPerson.id,
        relationshipKey: relationshipKey,
      );
      debugPrint('[RelateToPerson] Relationship created successfully');

      if (context.mounted) {
        final label = relationshipKey.replaceAll('_', ' ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Relationship Added\n${selectedPerson.name} → $label → ${sourcePerson.name}',
            ),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[RelateToPerson] ERROR: $e');
      String friendlyError;
      if (e is RelationshipValidationException) {
        if (e.code == 'self_relationship') {
          friendlyError = 'Choose two different family members.';
        } else if (e.code == 'duplicate_relationship') {
          friendlyError = 'Already connected — ${sourcePerson.name} and ${selectedPerson.name} already have a family relationship.';
        } else if (e.code == 'duplicate_parent') {
          friendlyError = 'This person already has a parent. Remove the existing one first.';
        } else if (e.code == 'circular_parentage') {
          friendlyError = 'This connection would create a family cycle.';
        } else {
          friendlyError = 'Couldn\'t create this connection. ${e.message}';
        }
      } else {
        friendlyError = 'Couldn\'t create this connection. Please try again.';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Shows the confirmation dialog before removing a member.
  static void _showRemoveConfirmation(
    BuildContext context,
    GraphPersonData person,
    String familyId,
  ) {
    showDialog(
      context: context,
      builder: (context) => _RemoveMemberDialog(
        personName: person.name,
        personId: person.id,
        familyId: familyId,
      ),
    );
  }
}

/// Confirmation dialog for removing a member.
/// Shows the member name, a warning message, and Cancel/Remove buttons.
class _RemoveMemberDialog extends ConsumerStatefulWidget {
  const _RemoveMemberDialog({
    required this.personName,
    required this.personId,
    required this.familyId,
  });

  final String personName;
  final String personId;
  final String familyId;

  @override
  ConsumerState<_RemoveMemberDialog> createState() => _RemoveMemberDialogState();
}

class _RemoveMemberDialogState extends ConsumerState<_RemoveMemberDialog> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      title: const Text(
        'Remove Member',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 18.0,
          fontWeight: FontWeight.w700,
          color: KinrelColors.textWhite,
        ),
      ),
      content: Text(
        'Are you sure you want to remove ${widget.personName} from this family?\n\n'
        'This action will permanently remove the member and all relationship connections associated with them.',
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14.0,
          color: KinrelColors.textSilver,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: KinrelColors.textDim),
          ),
        ),
        TextButton(
          onPressed: _isDeleting ? null : () => _performDeletion(),
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.red,
                  ),
                )
              : const Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _performDeletion() async {
    // v88 FIX: Capture the navigator BEFORE the async call so we
    // can close the dialog even if the widget tree rebuilds during
    // the deletion (which happens because deletePerson invalidates
    // Riverpod providers, causing parent widgets to rebuild).
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    setState(() => _isDeleting = true);

    try {
      await deletePerson(
        ref: ref,
        personId: widget.personId,
        familyId: widget.familyId,
      );

      // Close the dialog FIRST, then show the success message.
      // Using the captured navigator avoids context issues after
      // provider invalidation.
      if (mounted) {
        navigator.pop();
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${widget.personName} removed from family'),
          backgroundColor: KinrelColors.tealAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Failed to remove member: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
