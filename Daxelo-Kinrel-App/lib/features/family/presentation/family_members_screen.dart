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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_provider.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../presence/presence_provider.dart';
import '../presentation/providers/family_graph_provider.dart' show familyGraphProvider;
import 'family_space_floating_nav.dart';
import 'find_on_kinrel_flow.dart' show openFindOnKinrelFlow;
import 'person_detail_sheet.dart';

/// v5.212 — Entry context for the Members screen.
///
/// The Members screen is reached from two distinct entry points that
/// imply DIFFERENT semantics about what the user expects to see:
///
///   • [navTab] — the bottom-nav "Members" tab in Family Space. The
///     user is scanning for real people to interact with (chat, invite,
///     presence). Manually-added placeholder relatives cannot do any
///     of those things, so they must NOT appear in this mode. Only
///     Linked-status (real Kinrel account) members are shown.
///
///   • [graphViewAll] — the "View all 5" button inside the Graph
///     screen's stats panel. The user is explicitly viewing the
///     complete family tree, so the full list (Linked + Manual) is
///     shown, with the existing per-row Linked/Manual badges
///     preserved.
///
/// Default behavior when no context is provided (e.g., a direct deep
/// link or an unhandled navigation path): [navTab] (Linked-only), per
/// the safer-default rule — showing fewer real-feeling members is
/// less confusing than showing placeholder relatives in an unexpected
/// context.
enum MembersScreenSource {
  /// Reached via the bottom-nav "Members" tab in Family Space.
  /// Shows Linked-status members only.
  navTab,

  /// Reached via the Graph screen's "View all" button. Shows the
  /// full family tree (Linked + Manual) with per-row badges.
  graphViewAll,
  ;

  /// Parses the `source` query param from the route URL. Returns
  /// [navTab] (the safe default) for unknown/null values.
  static MembersScreenSource fromQueryParam(String? value) {
    if (value == 'graphViewAll') return MembersScreenSource.graphViewAll;
    // Anything else (including 'navTab' and null/empty) maps to
    // navTab — the safer default per the spec.
    return MembersScreenSource.navTab;
  }

  /// The query-param value to use when building URLs.
  String toQueryParam() => switch (this) {
        MembersScreenSource.navTab => 'navTab',
        MembersScreenSource.graphViewAll => 'graphViewAll',
      };

  /// Whether this entry context shows the full family tree (Linked +
  /// Manual) or only Linked-status members.
  bool get showsFullTree => this == MembersScreenSource.graphViewAll;
}

class FamilyMembersScreen extends ConsumerStatefulWidget {
  const FamilyMembersScreen({
    super.key,
    required this.familyId,
    this.source = MembersScreenSource.navTab,
  });
  final String familyId;

  /// Entry context — controls whether the list shows Linked-only
  /// members ([MembersScreenSource.navTab]) or the full tree
  /// ([MembersScreenSource.graphViewAll]). See the enum docs for the
  /// full rationale.
  final MembersScreenSource source;

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
        title: const Text(
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
      // v5.213 (graphViewAll chrome): the persistent Family Space
      // bottom nav (Games / Family Chat / Members / Calendar) is
      // rendered ONLY when this screen is reached via the bottom-nav
      // "Members" tab (navTab context). When reached via the Graph
      // screen's "View all" button (graphViewAll context), the screen
      // is a focused modal/sub-view launched from inside the Graph —
      // showing the bottom nav there makes the screen feel like a
      // lateral move into a different app section rather than a
      // focused "here's the full list" view, so it is omitted
      // entirely. The back arrow (top-left) remains the single way
      // out of the graphViewAll view, returning directly to the
      // Graph screen the user came from.
      bottomNavigationBar: widget.source == MembersScreenSource.navTab
          ? FamilySpaceFloatingNav(familyId: widget.familyId)
          : null,
      body: detailAsync.when(
        loading: () => const Center(
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

          // v5.204: Show ALL members (both Linked and Manual).
          // Previously filtered with `p.isLinkedToKinrelUser` which
          // excluded manually-added members — causing the member list
          // to show fewer members than the true count. Now shows every
          // non-deleted member, with a Linked/Manual badge distinguishing
          // how they were added.
          //
          // v5.212 (entry-context-aware list): the `activeMembers` set
          // is now narrowed based on entry context — when reached via
          // the bottom-nav Members tab, only Linked-status members
          // are shown. When reached via the Graph screen's "View all"
          // button, the full list (Linked + Manual) is shown. The
          // narrowing happens AFTER computing `trulyLinkedIds` below
          // (which still needs the full active set to correctly
          // classify the anchor Person's Linked status via fallbacks).
          final allActiveMembers = combinedMembers
              .where((p) => p.deletedAt == null)
              .toList();

          // v5.209: Determine which Person IDs are "truly linked" to a
          // real Kinrel account. The anchor Person's linkedUserId may be
          // NULL (because the unique constraint (familyId, linkedUserId)
          // prevents the creator from having linked Persons in multiple
          // families). But the anchor WAS created by a real user
          // (Family.createdBy). So for the anchor person, if the family
          // has a createdBy, treat it as "Linked" even without linkedUserId.
          //
          // v5.210 (BADGE ROBUSTNESS): add 3 additional fallback checks
          // to ensure NO real linked account is misclassified as Manual:
          //   2. family.anchorPersonId == p.id (the Person is the family's
          //      designated anchor, even if the isAnchor flag wasn't set
          //      in the Person row — defensive against trigger drift).
          //   3. p.id == currentUserId-derived anchor lookup (when the
          //      current viewer IS the family creator and their auth id
          //      matches family.createdBy, the anchor Person is theirs).
          //   4. Cross-check against memberships — if a FamilyMember row
          //      has userId matching the Person's linkedUserId OR if the
          //      Person is the anchor and family.createdBy matches a
          //      membership's userId, treat as Linked.
          final Set<String> membershipUserIds = memberships
              .where((m) => m.userId.isNotEmpty)
              .map((m) => m.userId)
              .toSet();
          final Set<String> trulyLinkedIds = {};
          for (final p in allActiveMembers) {
            // Primary check: explicit linkedUserId on the Person row.
            if (p.linkedUserId != null && p.linkedUserId!.isNotEmpty) {
              trulyLinkedIds.add(p.id);
              continue;
            }
            // v5.209 fallback: anchor Person with family.createdBy set
            // (the unique constraint prevented linkedUserId from being
            // stored on the Person row, but it IS a real account).
            if (p.isAnchor && family.createdBy != null &&
                family.createdBy!.isNotEmpty) {
              trulyLinkedIds.add(p.id);
              continue;
            }
            // v5.210 fallback 2: Person is the family's designated
            // anchor (by anchorPersonId pointer) and family has a
            // creator. Defensive against isAnchor flag drift.
            if (family.anchorPersonId != null &&
                family.anchorPersonId == p.id &&
                family.createdBy != null &&
                family.createdBy!.isNotEmpty) {
              trulyLinkedIds.add(p.id);
              continue;
            }
            // v5.210 fallback 3: Person is the anchor AND family's
            // createdBy matches a real FamilyMember's userId (proves
            // the creator is a registered Kinrel user with a
            // FamilyMember row, even if the Person's linkedUserId is
            // null).
            if (p.isAnchor && family.createdBy != null &&
                membershipUserIds.contains(family.createdBy)) {
              trulyLinkedIds.add(p.id);
              continue;
            }
          }

          // v5.212 (entry-context-aware list): narrow the displayed
          // list based on entry context. `navTab` shows only Linked
          // members; `graphViewAll` shows the full tree. Default is
          // `navTab` (Linked-only) per the safer-default rule — see
          // [MembersScreenSource].
          final activeMembers = widget.source.showsFullTree
              ? allActiveMembers
              : allActiveMembers
                  .where((p) => trulyLinkedIds.contains(p.id))
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
                        child: const Icon(Icons.sort_rounded,
                            color: KinrelColors.textSilver, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Member count + Linked/Manual split subtitle.
              //
              // v5.211 (member-count de-conflation): the primary count
              // here remains the FULL family-tree count (Linked +
              // Manual) — this screen IS the family-tree management
              // view, so showing the total tree size is correct.
              // However, we now ALSO show a clarifying subtitle that
              // surfaces the Linked/Manual split at the summary level
              // (not just per-row via the existing badges), so a user
              // scanning the header understands the composition at a
              // glance — e.g. "5 members · 2 on Kinrel".
              //
              // The Linked count uses `trulyLinkedIds` (computed
              // above with the same anchor-fallback logic the
              // [linkedMemberCountProvider] uses), so the subtitle's
              // "N on Kinrel" number always matches the count of
              // "Linked" badges visible in the list below.
              //
              // v5.212 (entry-context-aware list): the subtitle now
              // varies by entry context:
              //   • navTab mode — the displayed list is already
              //     Linked-only, so the subtitle clarifies that the
              //     visible rows are real accounts only ("Linked
              //     members only · N in your tree"), NOT the blended
              //     count. This anchors the user's mental model: "I'm
              //     seeing the real people, and my tree has N more
              //     placeholder relatives I can see via the Graph."
              //   • graphViewAll mode — the displayed list is the
              //     full tree, so the subtitle surfaces the
              //     Linked/Manual split at the summary level (e.g.
              //     "5 in your tree · 2 on Kinrel"), exactly as
              //     before. This is the mode where the clarifying
              //     subtitle is most meaningful because both kinds
              //     of rows are visible.
              //
              // When the user is searching, the per-row filtered
              // count is what's most actionable, so we hide the
              // subtitle in both modes (it would imply a different
              // denominator than the visible rows).
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${filtered.length} ${filtered.length == 1 ? "member" : "members"}',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: KinrelColors.textDim,
                        ),
                      ),
                      // v5.211 + v5.212: clarifying subtitle. Hidden
                      // during search (the primary count is the
                      // filtered subset, so a global subtitle would
                      // be misleading). Otherwise, the subtitle
                      // adapts to entry context per the v5.212 note
                      // above.
                      if (_searchQuery.isEmpty) ...[
                        const SizedBox(height: 2),
                        Builder(builder: (context) {
                          final linkedCount = trulyLinkedIds.length;
                          final treeTotal = allActiveMembers.length;
                          if (treeTotal == 0) {
                            return const SizedBox.shrink();
                          }
                          // v5.212: navTab mode subtitle tells the
                          // user the visible rows are real accounts
                          // + how many more placeholder relatives
                          // exist in their tree (so they know where
                          // to find them — the Graph view).
                          //
                          // graphViewAll mode subtitle surfaces the
                          // Linked/Manual split at the summary level
                          // (the original v5.211 behavior).
                          final subtitle = widget.source.showsFullTree
                              ? (linkedCount == 0
                                  ? '$treeTotal in your tree'
                                  : '$treeTotal in your tree · $linkedCount on Kinrel')
                              // navTab mode: every visible row is
                              // Linked. If treeTotal > linkedCount,
                              // there ARE placeholder relatives the
                              // user could see via the Graph view —
                              // surface that count.
                              : (treeTotal > linkedCount
                                  ? 'Linked members only · ${treeTotal - linkedCount} more in your tree'
                                  : 'Linked members only');
                          return Text(
                            subtitle,
                            style: const TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              color: KinrelColors.textDim,
                              height: 1.3,
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Member list
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No members found',
                          style: TextStyle(color: KinrelColors.textDim),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          left: KinrelSpacing.base,
                          right: KinrelSpacing.base,
                          // Account for the floating dock (96px height +
                          // 20px bottom margin + safe-area inset) ONLY
                          // when the dock is actually present (navTab
                          // context). When the dock is omitted
                          // (graphViewAll context), use a smaller
                          // bottom padding so the list doesn't have a
                          // giant empty gap at the bottom of the
                          // focused modal view — but still reserve
                          // enough space (~80px) to clear the FAB
                          // (which still floats at the bottom-right
                          // via Scaffold.floatingActionButton).
                          //
                          // v5.213 (graphViewAll chrome): the dock
                          // height was 140px when present; when absent
                          // we still need a small amount of bottom
                          // padding so the last row isn't flush against
                          // the FAB or the bottom safe-area.
                          bottom: widget.source ==
                                  MembersScreenSource.navTab
                              ? 140
                              : 80,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final person = filtered[index];
                          final relLabel = relationshipLabels[person.id];
                          final presence =
                              person.linkedUserId != null
                                  ? presenceMap[person.linkedUserId!]
                                  : null;

                          return Dismissible(
                            key: ValueKey(person.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 24),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: KinrelColors.darkCard,
                                  title: Text(
                                    'Delete ${person.name}?',
                                    style: const TextStyle(
                                      color: KinrelColors.textWhite,
                                      fontFamily: KinrelTypography.displayFont,
                                    ),
                                  ),
                                  content: Text(
                                    'This will permanently remove ${person.name} from the family. '
                                    'This action cannot be undone.',
                                    style: const TextStyle(
                                      color: KinrelColors.textDim,
                                      fontFamily: KinrelTypography.bodyFont,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Cancel',
                                          style: TextStyle(
                                              color: KinrelColors.textDim)),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      style: TextButton.styleFrom(
                                          foregroundColor: Colors.redAccent),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ) ?? false;
                            },
                            onDismissed: (direction) async {
                              try {
                                final client =
                                    ref.read(supabaseProvider);
                                if (client != null) {
                                  await client
                                      .from('Person')
                                      .update({
                                        'deletedAt': DateTime.now()
                                            .toIso8601String(),
                                      })
                                      .eq('id', person.id);
                                }
                                if (mounted) {
                                  ref.invalidate(familyDetailProvider(
                                      widget.familyId));
                                  ref.invalidate(familyMembersProvider(
                                      widget.familyId));
                                  ref.invalidate(familyGraphProvider(
                                      widget.familyId));
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${person.name} deleted'),
                                      backgroundColor:
                                          KinrelColors.darkElevated,
                                      behavior:
                                          SnackBarBehavior.floating,
                                      duration: const Duration(
                                          seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Failed to delete: $e'),
                                      backgroundColor: Colors.redAccent,
                                      behavior:
                                          SnackBarBehavior.floating,
                                    ),
                                  );
                                  ref.invalidate(familyDetailProvider(
                                      widget.familyId));
                                }
                              }
                            },
                            child: _MemberRow(
                              person: person,
                              relationshipLabel: relLabel,
                              presence: presence,
                              isTrulyLinked: trulyLinkedIds.contains(person.id),
                              onTap: () {
                                PersonDetailSheet.show(
                                  context,
                                  person: person,
                                  familyId: widget.familyId,
                                  kinshipService: kinshipService,
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        // v5.215 (unified add-member entry-point fix): the Members
        // screen FAB previously called `showAddMemberOptions` — the
        // 2-option (Add Manually / Find on Kinrel) bottom sheet.
        // Now it skips straight to the Find on Kinrel search flow,
        // matching the Family Space "Invite family member" button
        // and the Family Profile "Add member" button. "Add Manually"
        // remains reachable only from the Family Graph screen's own
        // Add Member button (which keeps `showAddMemberOptions` with
        // `fromGraph: true`).
        //
        // Applies in BOTH entry-context modes (navTab and
        // graphViewAll): the Members screen is NOT the Graph screen,
        // even when launched from inside it via "View all" — so Add
        // Manually is not appropriate here. The Graph screen's own
        // Add Member button is the single place where Add Manually
        // remains reachable.
        onPressed: () => openFindOnKinrelFlow(
          context,
          familyId: widget.familyId,
        ),
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
    this.isTrulyLinked = false,
  });

  final Person person;
  final VoidCallback onTap;

  /// Viewer-relative relationship label (e.g. "Your brother"), or null
  /// if the person is the current user or no path was found.
  final String? relationshipLabel;

  /// Presence status for this member, or null if no presence data.
  final PresenceStatus? presence;

  /// v5.209: Whether this member is truly linked to a real Kinrel
  /// account. Checks both `linkedUserId` AND the anchor/createdBy
  /// fallback (the anchor Person's linkedUserId may be NULL due to
  /// the unique constraint, but it IS a real account).
  final bool isTrulyLinked;

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
                  // perf pass — family member avatars render at 44×44
                  // logical px. Cap decode to 44 × dpr physical px and
                  // use disk-cached provider so a 1024×1024 upload
                  // doesn't decode to a 4MB bitmap per member. Wrap in
                  // ResizeImage because CachedNetworkImageProvider
                  // doesn't accept cacheWidth/cacheHeight directly.
                  backgroundImage: person.photoUrl != null
                      ? ResizeImage(
                          CachedNetworkImageProvider(person.photoUrl!),
                          width: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                          height: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                        )
                      : null,
                  child: person.photoUrl == null
                      ? Text(
                          person.name.isNotEmpty
                              ? person.name[0]
                                  .toUpperCase()
                              : '?',
                          style: const TextStyle(
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
                    style: const TextStyle(
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
                      style: const TextStyle(
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
              const Icon(Icons.star_rounded,
                  color: KinrelColors.gold, size: 18),
            // v5.204: Linked/Manual badge — distinguishes members
            // added via "Find on Kinrel" (real registered accounts,
            // connected via invite/acceptance) from members added
            // via "Add Manually" (not a real linked account).
            // v5.209: Uses `isTrulyLinked` which checks BOTH
            // `linkedUserId` AND the anchor/createdBy fallback —
            // the anchor Person's linkedUserId may be NULL due to
            // the unique constraint, but it IS a real account.
            //   - isTrulyLinked → "Linked" (chain-link icon)
            //   - !isTrulyLinked → "Manual" (pencil icon)
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isTrulyLinked
                    ? KinrelColors.tealAccent
                    : KinrelColors.textDim).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (isTrulyLinked
                      ? KinrelColors.tealAccent
                      : KinrelColors.textDim).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isTrulyLinked
                        ? Icons.link
                        : Icons.edit_outlined,
                    size: 10,
                    color: isTrulyLinked
                        ? KinrelColors.tealAccent
                        : KinrelColors.textDim,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    isTrulyLinked ? 'Linked' : 'Manual',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isTrulyLinked
                          ? KinrelColors.tealAccent
                          : KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
