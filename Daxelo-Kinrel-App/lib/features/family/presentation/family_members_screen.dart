// lib/features/family/presentation/family_members_screen.dart
//
// Extracted from FamilyDetailScreen's _MembersTab — full-screen
// member list with search, sort, and member cards.
//
// v111 — adds three enhancements to each member row:
//   1. Tap-to-open PersonDetailSheet (reuses the existing widget).
//   2. Viewer-relative relationship label (e.g. "Your brother") below
//      the gender line, computed via GraphService.findPath with
//      fromPersonId = the current user's Person in this family. This
//      is DIRECTION-AWARE by design — if a different user opens the
//      same list, fromPersonId becomes HER id and the same call
//      returns "son" instead of "brother". No per-user logic needed.
//   3. Presence dot on each avatar (green = home, blue = work,
//      red = dnd, gray = away) reusing familyPresenceProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_provider.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../presence/presence_provider.dart';
import 'add_member_options_sheet.dart';
import 'family_space_floating_nav.dart';
import 'person_detail_sheet.dart';

class FamilyMembersScreen extends ConsumerStatefulWidget {
  const FamilyMembersScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyMembersScreen> createState() =>
      _FamilyMembersScreenState();
}

class _FamilyMembersScreenState extends ConsumerState<FamilyMembersScreen> {
  String _searchQuery = '';
  String _sortBy = 'name';

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(familyDetailProvider(widget.familyId));
    final combinedMembers =
        ref.watch(combinedMembersProvider(widget.familyId));
    final membershipsAsync =
        ref.watch(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull ?? [];
    final currentUserId =
        ref.read(supabaseProvider)?.auth.currentUser?.id;

    // ── v111: relationship label data ──────────────────────────────
    // Watch relationships + graph service so we can compute the
    // viewer-relative label for each member. findPath is synchronous
    // and cheap (BFS on a small family graph), so we compute all
    // labels once per rebuild rather than per-row during scroll.
    final relsAsync =
        ref.watch(familyRelationshipsProvider(widget.familyId));
    final graphService = ref.read(graphServiceProvider);
    final kinshipService = ref.read(kinshipServiceProvider);

    // Find the current user's Person id in THIS family (the Person
    // whose linkedUserId matches the logged-in user's auth id).
    final myPersonId = combinedMembers
        .where((p) => p.linkedUserId == currentUserId)
        .firstOrNull
        ?.id;

    // Build a {personId: relationshipDescription} map for all members.
    // Skips: (a) the current user's own row (no "your self" label),
    //        (b) members with no path (unrelated/in-laws not yet linked).
    final relationshipLabels = <String, String>{};
    if (myPersonId != null) {
      final membersList = combinedMembers
          .where((p) => p.deletedAt == null)
          .toList();
      final persons = membersList.map((p) => p.toGraphPerson()).toList();
      final relsValue = relsAsync.valueOrNull ?? [];
      final edges = relsValue.map((r) => r.toGraphEdge()).toList();

      for (final p in membersList) {
        if (p.id == myPersonId) continue; // skip self
        final result = graphService.findPath(
          persons: persons,
          relationships: edges,
          fromPersonId: myPersonId,
          toPersonId: p.id,
          familyId: widget.familyId,
        );
        if (result != null && result.relationshipDescription.isNotEmpty) {
          relationshipLabels[p.id] = result.relationshipDescription;
        }
      }
    }

    // ── v111: presence data ────────────────────────────────────────
    // Map of {userId: PresenceStatus} for quick per-row lookups.
    final presenceAsync =
        ref.watch(familyPresenceProvider(widget.familyId));
    final presenceMap = <String, PresenceStatus>{};
    for (final m in (presenceAsync.valueOrNull ?? [])) {
      presenceMap[m.userId] = m.status;
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Members',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      bottomNavigationBar: FamilySpaceFloatingNav(familyId: widget.familyId),
      body: detailAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (e, _) => DKErrorState(
          message: '$e',
          onRetry: () =>
              ref.invalidate(familyDetailProvider(widget.familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Family not found'));
          }

          final family = detail.family;
          final isCreator = family.createdBy != null &&
              family.createdBy == currentUserId;
          final currentUserMembership = memberships
              .where((m) => m.userId == currentUserId)
              .firstOrNull;
          final isAdmin = isCreator ||
              (currentUserMembership?.isAdmin ?? false);

          // Only show real Kinrel users (linkedUserId is not null) —
          // manually added placeholder nodes are excluded.
          final activeMembers = combinedMembers
              .where((p) => p.deletedAt == null && p.isLinkedToKinrelUser)
              .toList();

          var filtered = activeMembers;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            filtered = filtered
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    (p.gender?.toLowerCase().contains(q) ?? false))
                .toList();
          }

          if (_sortBy == 'name') {
            filtered.sort((a, b) => a.name.compareTo(b.name));
          } else {
            filtered.sort((a, b) =>
                (a.gender ?? '').compareTo(b.gender ?? ''));
          }

          return Column(
            children: [
              // Search + sort bar
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Expanded(
                      child: DKSearchField(
                        hint: 'Search members...',
                        onChanged: (v) =>
                            setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      onSelected: (v) => setState(() => _sortBy = v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'name', child: Text('Sort by name')),
                        const PopupMenuItem(
                            value: 'gender',
                            child: Text('Sort by gender')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KinrelColors.darkElevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.sort_rounded,
                            color: KinrelColors.textSilver, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Member count
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${filtered.length} ${filtered.length == 1 ? "member" : "members"}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Member list
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No members found',
                          style: TextStyle(color: KinrelColors.textDim),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          left: KinrelSpacing.base,
                          right: KinrelSpacing.base,
                          // Account for the floating dock (96px height +
                          // 20px bottom margin + safe-area inset).
                          bottom: 140,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final person = filtered[index];
                          // ── v111: viewer-relative relationship label
                          // (null for self / no path found).
                          final relLabel = relationshipLabels[person.id];
                          // ── v111: presence status (null if no
                          // presence data for this user).
                          final presence =
                              person.linkedUserId != null
                                  ? presenceMap[person.linkedUserId!]
                                  : null;

                          return _MemberRow(
                            person: person,
                            relationshipLabel: relLabel,
                            presence: presence,
                            onTap: () {
                              // Reuse the existing PersonDetailSheet.show
                              // call signature — same as
                              // family_detail_screen.dart line 1600.
                              PersonDetailSheet.show(
                                context,
                                person: person,
                                familyId: widget.familyId,
                                kinshipService: kinshipService,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            showAddMemberOptions(context, familyId: widget.familyId),
        backgroundColor: KinrelColors.orange,
        child: const Icon(Icons.person_add_alt_1_rounded,
            color: Colors.white),
      ),
    );
  }
}

/// A single member row in the Family Members list.
///
/// v111 — extracted from the inline itemBuilder so the three new
/// enhancements (tap-to-open-sheet, relationship label, presence dot)
/// are cleanly encapsulated.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.person,
    required this.onTap,
    this.relationshipLabel,
    this.presence,
  });

  final Person person;
  final VoidCallback onTap;

  /// Viewer-relative relationship label (e.g. "Your brother"), or null
  /// if the person is the current user or no path was found.
  final String? relationshipLabel;

  /// Presence status for this member, or null if no presence data.
  final PresenceStatus? presence;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // ── Avatar with presence dot ────────────────────────────
            // Stack the avatar + a small colored dot at bottom-right
            // (green=home, blue=work, red=dnd, gray=away). Reuses the
            // same presence color values as PresenceRow.
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: KinrelColors.orange
                      .withValues(alpha: 0.15),
                  backgroundImage: person.photoUrl != null
                      ? NetworkImage(person.photoUrl!)
                      : null,
                  child: person.photoUrl == null
                      ? Text(
                          person.name.isNotEmpty
                              ? person.name[0]
                                  .toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontFamily: KinrelTypography
                                .displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        )
                      : null,
                ),
                if (presence != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(presence!.colorValue),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: KinrelColors.darkCard,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography
                          .displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  if (person.gender != null)
                    Text(
                      person.gender!,
                      style: TextStyle(
                        fontFamily: KinrelTypography
                            .bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  // ── v111: viewer-relative relationship label ──────
                  // e.g. "Your brother", "Your mother". Only shown
                  // when a path was found (skipped silently for self
                  // and unrelated/in-law members).
                  if (relationshipLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      relationshipLabel!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.orange
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (person.isAnchor)
              Icon(Icons.star_rounded,
                  color: KinrelColors.gold, size: 18),
          ],
        ),
      ),
    );
  }
}
