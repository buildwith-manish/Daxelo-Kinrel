// lib/graph/widgets/unlinked_members_sheet.dart
//
// DAXELO KINREL — Unlinked Members Bottom Sheet (v5.9)
//
// Shows a list of family members who have zero relationship edges
// (unlinked). Tapping a member focuses the graph on them and/or kicks
// off Relationship Creation Mode with that person pre-selected.
//
// Visual pattern: reuses the bottom-sheet style from GraphQuickActions
// (darkCard background, rounded top corners, list of ListTiles with
// avatar + name + subtitle).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart';

/// Shows a bottom sheet listing all unlinked family members.
///
/// [familyId] — the family whose graph to check.
/// [onPersonSelected] — callback invoked when the user taps a person.
///   Receives the person's ID and name. The caller can choose to focus
///   the graph on them and/or start Relationship Creation Mode.
Future<void> showUnlinkedMembersSheet(
  BuildContext context,
  WidgetRef ref,
  String familyId, {
  required void Function(String personId, String personName) onPersonSelected,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KinrelColors.darkCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
    ),
    builder: (ctx) => _UnlinkedMembersSheet(
      familyId: familyId,
      onPersonSelected: onPersonSelected,
    ),
  );
}

class _UnlinkedMembersSheet extends ConsumerWidget {
  const _UnlinkedMembersSheet({
    required this.familyId,
    required this.onPersonSelected,
  });

  final String familyId;
  final void Function(String personId, String personName) onPersonSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlinkedIds = ref.watch(unlinkedPersonIdsProvider(familyId));
    final graphAsync = ref.watch(familyGraphProvider(familyId));
    final graph = graphAsync.valueOrNull;

    // Build the list of unlinked persons (with name + avatar)
    final unlinkedPersons = <Map<String, dynamic>>[];
    if (graph != null) {
      for (final p in graph.persons) {
        final id = p['id']?.toString();
        if (id != null && unlinkedIds.contains(id)) {
          unlinkedPersons.add(p);
        }
      }
    }

    return SafeArea(
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
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link_off, size: 18, color: KinrelColors.amber),
                    const SizedBox(width: 8),
                    Text(
                      'Needs Linking',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18.0,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: KinrelColors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${unlinkedPersons.length}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'These members aren\'t connected to the family tree yet. Tap one to link them.',
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
          // List
          if (unlinkedPersons.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Everyone is connected!',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textDim,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: unlinkedPersons.length,
                itemBuilder: (ctx, i) {
                  final p = unlinkedPersons[i];
                  final id = p['id']?.toString() ?? '';
                  final name = p['name']?.toString() ?? 'Unknown';
                  final photoUrl = p['photoUrl']?.toString();
                  final gender = p['gender']?.toString();

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KinrelColors.amber.withValues(alpha: 0.15),
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                      child: (photoUrl == null || photoUrl.isEmpty)
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: KinrelColors.amber,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    subtitle: Text(
                      'No relationships yet',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.amber,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Icon(
                      Icons.link_rounded,
                      color: KinrelColors.amber,
                      size: 20,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      onPersonSelected(id, name);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 8.0),
        ],
      ),
    );
  }
}
