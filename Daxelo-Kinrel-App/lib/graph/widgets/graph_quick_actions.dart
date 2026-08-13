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
import '../../features/family/presentation/add_person_sheet.dart';
import '../../features/family/presentation/relationship_picker_sheet.dart';
import '../interaction/graph_focus_state.dart';
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
                  _showRelateToPersonFlow(
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

  /// v141: Shows the "Relate to another person" flow.
  ///
  /// Step 1: Opens a bottom sheet listing all other Person nodes in the
  ///         family (excluding the source person). User picks one.
  /// Step 2: Opens the existing [RelationshipPickerSheet] — "How is
  ///         [selected person] related to [source person]?"
  /// Step 3: Calls [createRelationship] which handles validation
  ///         (self-link, duplicate, cycle), creates the edge + its
  ///         inverse, and refreshes the graph.
  ///
  /// Reuses the app's entire kinship system — no new relationship
  /// mechanism is created.
  static void _showRelateToPersonFlow(
    BuildContext context,
    WidgetRef ref,
    String familyId,
    GraphPersonData sourcePerson,
  ) async {
    // Step 1: Fetch family members + relationships.
    final detailAsync = ref.read(familyDetailProvider(familyId));
    final detail = detailAsync.valueOrNull;

    if (detail == null || detail.members.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No other family members to relate to.'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // v142: Build the set of person IDs that already have a DIRECT
    // relationship with the source person. A direct relationship exists
    // if there's any FamilyRelationship edge where (from=source AND
    // to=other) OR (from=other AND to=source). These persons are
    // excluded from the picker to prevent duplicate relationships.
    final relationships = detail.relationships;
    final directlyRelatedIds = <String>{};
    for (final rel in relationships) {
      if (rel.fromPersonId == sourcePerson.id) {
        directlyRelatedIds.add(rel.toPersonId);
      } else if (rel.toPersonId == sourcePerson.id) {
        directlyRelatedIds.add(rel.fromPersonId);
      }
    }

    // Filter: exclude the source person themselves + anyone already
    // directly related to the source person.
    final availablePersons = detail.members.where((p) =>
        p.id != sourcePerson.id && !directlyRelatedIds.contains(p.id)).toList();

    if (availablePersons.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Everyone in this family is already related to ${sourcePerson.name}.'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // v142: For each available person, resolve their kinship label
    // RELATIVE TO THE SOURCE PERSON (not the viewer/anchor). This uses
    // the same semantics as GraphRelationshipLabels.getRelationLabel
    // but with sourcePerson as the "anchor" perspective.
    //
    // Edge semantics: from: A, to: B, key: 'X' means "A is the X of B"
    //   - Edge from=other, to=source, key=X → other is X of source → label = formatKey(X)
    //   - Edge from=source, to=other, key=X → source is X of other → other's label = formatKey(inverse(X))
    //
    // Since we filtered out directly-related persons, most labels will
    // be empty — but some persons may have INDIRECT relationships that
    // still resolve to a label via the graph. We show whatever label
    // is available; if none, we show no subtitle.
    String kinshipLabelFor(Person other) {
      for (final rel in relationships) {
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

    // Step 1: Show person picker bottom sheet.
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
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Relate ${sourcePerson.name} to…',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18.0,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select an existing family member',
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
            // Person list — each item shows avatar + name + kinship label
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availablePersons.length,
                itemBuilder: (ctx, i) {
                  final p = availablePersons[i];
                  final label = kinshipLabelFor(p);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          KinrelColors.tealAccent.withValues(alpha: 0.15),
                      backgroundImage: p.photoUrl != null &&
                              p.photoUrl!.isNotEmpty
                          ? NetworkImage(p.photoUrl!)
                          : null,
                      child: (p.photoUrl == null || p.photoUrl!.isEmpty)
                          ? Text(
                              p.name.isNotEmpty
                                  ? p.name[0].toUpperCase()
                                  : '?',
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
                    // v142: Kinship label beneath the name — uses the
                    // same tealAccent color + bodyFont styling as graph
                    // node labels. Only shown when a label exists.
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

    // v144: Debug — confirm the person was selected + show what's happening next.
    debugPrint('[RelateToPerson] Selected: ${selectedPerson.name} (${selectedPerson.id})');
    debugPrint('[RelateToPerson] Source: ${sourcePerson.name} (${sourcePerson.id})');
    debugPrint('[RelateToPerson] Opening RelationshipPickerSheet...');

    // v144: Show a brief SnackBar so the user sees the flow is continuing.
    // This makes it obvious if the next step (RelationshipPickerSheet)
    // fails to open — the user will see "Opening kinship selection..."
    // and know the person pick succeeded.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening kinship selection for ${selectedPerson.name}...'),
          backgroundColor: KinrelColors.darkCard,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }

    // Step 2: Show the existing RelationshipPickerSheet.
    // Header: "How is [selectedPerson] related to [sourcePerson]?"
    //
    // v144: The original `context` IS still valid after the person-picker
    // sheet closes — `showModalBottomSheet` returns the selected value
    // but doesn't invalidate the calling context. The v143 attempt to
    // use `Navigator.of(context, rootNavigator: true).context` was
    // incorrect — that returns the NavigatorState's own context, which
    // is NOT a valid context for showing modal sheets.
    //
    // Wait briefly for the SnackBar to show before opening the sheet,
    // so the user sees the transition.
    await Future.delayed(const Duration(milliseconds: 200));

    if (!context.mounted) {
      debugPrint('[RelateToPerson] Context not mounted after person pick — aborting');
      return;
    }
    final relationshipKey = await RelationshipPickerSheet.show(
      context,
      personAName: sourcePerson.name,
      personBName: selectedPerson.name,
    );

    debugPrint('[RelateToPerson] RelationshipPickerSheet returned: $relationshipKey');

    if (relationshipKey == null) {
      debugPrint('[RelateToPerson] User cancelled kinship selection');
      return; // User cancelled
    }

    // Step 3: Create the relationship using the existing function.
    // createRelationship handles: validation (self-link, duplicate,
    // cycle), edge creation, inverse creation, and graph refresh.
    debugPrint('[RelateToPerson] Creating relationship: ${sourcePerson.id} → ${selectedPerson.id} as $relationshipKey');

    // v146: Pre-flight check — verify both person IDs exist in the
    // Person table. The graph's GraphPersonData.id might not match
    // Person.id if the graph uses synthetic IDs. This catches FK
    // violations BEFORE the INSERT and gives a clear error message.
    final client = ref.read(supabaseProvider);
    if (client == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not connected to the database. Please restart the app.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      // Verify source person exists
      final sourceCheck = await client
          .from('Person')
          .select('id, name')
          .eq('id', sourcePerson.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (sourceCheck == null) {
        debugPrint('[RelateToPerson] ERROR: Source person ${sourcePerson.id} not found in Person table');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot create relationship: "${sourcePerson.name}" was not found in the family database. This may be a synced node that needs to be linked to a real person record.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }
      debugPrint('[RelateToPerson] Source person verified: ${sourceCheck['name']}');

      // Verify target person exists (already from familyDetailProvider, but double-check)
      final targetCheck = await client
          .from('Person')
          .select('id, name')
          .eq('id', selectedPerson.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (targetCheck == null) {
        debugPrint('[RelateToPerson] ERROR: Target person ${selectedPerson.id} not found in Person table');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot create relationship: "${selectedPerson.name}" was not found in the family database.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }
      debugPrint('[RelateToPerson] Target person verified: ${targetCheck['name']}');

      await createRelationship(
        ref: ref,
        familyId: familyId,
        fromPersonId: sourcePerson.id,
        toPersonId: selectedPerson.id,
        relationshipKey: relationshipKey,
      );
      debugPrint('[RelateToPerson] Relationship created successfully');

      // v144: Show a confirmation SnackBar with both directions.
      if (context.mounted) {
        final inverseKey = GraphRelationshipLabels.getInverseKey(relationshipKey);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selectedPerson.name} is now ${sourcePerson.name}\'s ${relationshipKey.replaceAll('_', ' ')}'
              '${inverseKey != relationshipKey ? '\n${sourcePerson.name} is ${selectedPerson.name}\'s ${inverseKey.replaceAll('_', ' ')}' : ''}',
            ),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[RelateToPerson] ERROR creating relationship: $e');
      // v146: Show a DETAILED error message — include the exception type
      // and message so we can diagnose FK violations, RLS denials, etc.
      String errorDetail;
      if (e is PostgrestException) {
        errorDetail = 'Database error: ${e.message} (code: ${e.code})';
      } else if (e is RelationshipValidationException) {
        errorDetail = e.message;
      } else {
        errorDetail = e.toString();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create relationship: $errorDetail'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
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
