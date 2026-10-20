// lib/features/home/presentation/widgets/kinship_ring_row.dart
//
// DAXELO KINREL — Kinship Ring Row (Phase A — Home, the Instagram-level idea)
//
// Horizontal scrollable row. The row is ALWAYS rendered at the same
// position in every Home state (newUser, growing, active) and NEVER
// changes height between states — so the page does not jump when a
// Sparq appears or expires.
//
// Composition (final rules — replaces all earlier ring-row rules):
//
//   1. "You" is ALWAYS the first item, in every state, even with
//      zero relatives and zero Sparqs.
//        • Viewer has no current Sparq → avatar + plus badge.
//          Labels: "You" (bold) + "Add yours" (small). Tap →
//          /sparq/create.
//        • Viewer has a current Sparq → avatar with a story ring +
//          a small plus badge. Tap → own Sparq viewer
//          (/sparq/viewer/<ownUserId>). The plus badge → /sparq/create.
//
//   2. After "You", show ONLY relatives who have a current
//      (non-expired) Sparq, using the existing Sparq rules for what
//      counts as current (see SparqModel.isExpired in
//      social/data/models/sparq_model.dart).
//      Order:
//        • unseen first (gradient ring)
//        • then seen (dim ring)
//        • within each group: birthday-soon first, then closest
//          relationship (closeness heuristic on the kinship key —
//          see _closenessScoreForKey).
//
//   3. Relatives WITHOUT a current Sparq are NOT shown. If nobody
//      has a Sparq, the row contains only "You +". No empty
//      placeholders, no ghost circles, no "no stories" text.
//
//   4. With a single item (just "You +"), the row stays
//      left-aligned at the normal item size. No stretching.
//
//   5. Labels for relatives: primary = kinship term in the viewer's
//      chosen language (bold), secondary = first name (small). The
//      birthday badge (e.g. "3d") appears ONLY when that person has
//      a Sparq AND a birthday within 7 days. Names are never
//      translated.
//
// Loading: while Sparq data loads, "You" appears immediately and
// skeleton circles fill the remaining slots (no spinner).
//
// Accessibility:
//   • Minimum tap target 44dp on every item (56px visual + 4px
//     hit-padding = 60px tap target).
//   • Primary text ≥ 12sp bold; secondary text ≥ 10sp.
//   • Semantic labels: "Add your Sparq" for the You affordance;
//     "Mama's Sparq, new" for unseen relatives; "Mama's Sparq,
//     seen" for seen relatives.
//   • Works at 1.5x text scale + RTL (the Row stays horizontal
//     scrollable, no clipping).
//   • Design tokens only (KinrelColors, KinrelTypography,
//     KinrelSpacing, KinrelGradients).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/kinship/kinship_term_providers.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/utils/accessibility_utils.dart';
import '../../../family/presentation/providers/family_graph_provider.dart';
import '../../../occasions/providers/occasion_reminders_provider.dart';
import '../../../social/data/providers/sparq_provider.dart';
import '../../../social/presentation/widgets/sparq_ring_avatar.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;
const _cBirthday = KinrelColors.gold;

/// A single ring-row item after all the data has been resolved.
///
/// Pre-computed at row level so the build method is pure paint.
class _RingItem {
  const _RingItem({
    required this.personId,
    required this.firstName,
    required this.kinshipPrimary,
    this.kinshipSecondary,
    this.avatarUrl,
    this.linkedUserId,
    this.daysUntilBirthday,
    this.isSeen = false,
    this.closenessScore = 99,
  });

  final String personId;
  final String firstName;
  final String kinshipPrimary;
  final String? kinshipSecondary;
  final String? avatarUrl;
  final String? linkedUserId;
  final int? daysUntilBirthday;
  final bool isSeen;
  final int closenessScore;
}

/// The kinship ring row. Always visible, never changes height.
class KinshipRingRow extends ConsumerWidget {
  const KinshipRingRow({
    super.key,
    required this.familyId,
    required this.onAddYours,
  });

  final String familyId;

  /// Called when the viewer taps the leading "You / Add yours"
  /// affordance (avatar or plus badge) when they have no current
  /// Sparq. Opens /sparq/create.
  final VoidCallback onAddYours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch all upstream inputs so Riverpod auto-rebuilds.
    final termsAsync =
        ref.watch(kinshipTermsForFamilyProvider(familyId));
    final graphAsync = ref.watch(familyGraphProvider(familyId));
    final occasionsAsync = ref.watch(occasionRemindersProvider);
    final sparqState = ref.watch(sparqProvider);

    final graph = graphAsync.valueOrNull;
    final terms = termsAsync.valueOrNull ?? const <String, KinshipTerm>{};

    // ── Birthday badges: occasionRemindersProvider already
    // computes daysUntil for every person across all families.
    final birthdayByPersonId = <String, int>{};
    final occasions = occasionsAsync.valueOrNull;
    if (occasions != null) {
      for (final o in occasions.withinSevenDays) {
        if (o.type == OccasionType.birthday) {
          birthdayByPersonId[o.personId] = o.daysUntil;
        }
      }
    }

    // ── Identify the viewer's own Person + Sparq state ────────
    // The graph marks the viewer's person with `isViewer: true`
    // (see FlatGraphResult.fromRpc).
    Map<String, dynamic>? viewerPerson;
    if (graph != null) {
      for (final p in graph.persons) {
        if (p['isViewer'] == true) {
          viewerPerson = p;
          break;
        }
      }
    }
    // Fallback: if the graph isn't loaded yet, derive the viewer's
    // auth id from sparqState (each UserSparqGroup has a userId —
    // the viewer's own group, if it exists, gives us their id).
    final viewerLinkedUserId = viewerPerson?['linkedUserId']?.toString();
    final viewerPersonId = viewerPerson?['id']?.toString();
    final viewerFirstName = viewerPerson == null
        ? 'You'
        : kinrelFirstName(viewerPerson['name']?.toString() ?? 'You');
    final viewerAvatarUrl = viewerPerson == null
        ? null
        : (viewerPerson['photoUrl']?.toString() ??
            viewerPerson['avatarUrl']?.toString());

    // Viewer's own Sparq state — a current Sparq means the viewer's
    // linkedUserId is in sparqState.feed AND has at least one
    // non-expired Sparq AND not all are seen.
    final viewerGroup = sparqState.feed
        .where((g) => g.userId == viewerLinkedUserId)
        .firstOrNull;
    final viewerHasCurrentSparq = viewerGroup != null &&
        viewerGroup.sparqs.any((s) => !s.isExpired);
    final viewerAllSeen = viewerGroup?.allSeen ?? true;

    // ── Build the items list: ONLY relatives with current Sparqs ──
    // Skip:
    //   • the viewer (rendered as the leading You item)
    //   • relatives whose Sparq is expired (SparqModel.isExpired)
    //   • relatives with NO Sparq at all (no entry in sparqState.feed)
    final items = <_RingItem>[];

    if (graph != null) {
      // Build per-linkedUserId → hasCurrentSparq + allSeen map.
      final hasCurrentByUserId = <String, bool>{};
      final seenByUserId = <String, bool>{};
      for (final group in sparqState.feed) {
        final hasCurrent =
            group.sparqs.any((s) => !s.isExpired);
        hasCurrentByUserId[group.userId] = hasCurrent;
        seenByUserId[group.userId] = group.allSeen;
      }

      for (final p in graph.persons) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (p['isViewer'] == true) continue; // skip self

        final linkedUserId = p['linkedUserId']?.toString();
        if (linkedUserId == null || linkedUserId.isEmpty) continue;
        // Only relatives with a CURRENT Sparq.
        if (hasCurrentByUserId[linkedUserId] != true) continue;

        final name = p['name']?.toString() ?? 'Relative';
        final firstName = kinrelFirstName(name);
        final avatarUrl =
            p['photoUrl']?.toString() ?? p['avatarUrl']?.toString();
        final term = terms[id];
        final isSeen = seenByUserId[linkedUserId] ?? true;

        items.add(_RingItem(
          personId: id,
          firstName: firstName,
          kinshipPrimary: term?.primary ?? firstName,
          kinshipSecondary: term?.secondary,
          avatarUrl: avatarUrl,
          linkedUserId: linkedUserId,
          daysUntilBirthday: birthdayByPersonId[id],
          isSeen: isSeen,
          closenessScore: _closenessScoreForKey(term?.kinshipKey),
        ));
      }
    }

    // ── Sort: unseen first, then seen; within each group:
    // birthday-soon first, then closest relationship (lower score =
    // closer). Stable tie-break by firstName.
    items.sort((a, b) {
      final aSeen = a.isSeen ? 1 : 0;
      final bSeen = b.isSeen ? 1 : 0;
      if (aSeen != bSeen) return aSeen.compareTo(bSeen);
      // Within the same seen-state: birthday-soon first.
      final aBirth = a.daysUntilBirthday;
      final bBirth = b.daysUntilBirthday;
      final aHasBirth = (aBirth != null && aBirth <= 7) ? 0 : 1;
      final bHasBirth = (bBirth != null && bBirth <= 7) ? 0 : 1;
      if (aHasBirth != bHasBirth) return aHasBirth.compareTo(bHasBirth);
      // Then closest relationship (lower score = closer).
      final c = a.closenessScore.compareTo(b.closenessScore);
      if (c != 0) return c;
      return a.firstName.compareTo(b.firstName);
    });

    // ── Build the row. Always 96px tall. The leading item is
    // always "You / Add yours" — even when the row has no other
    // items. With a single item, the row stays left-aligned at the
    // normal item size (no stretching — ListView.separated keeps
    // items at their natural width).
    final showSkeletonForOthers =
        graph == null && sparqState.isLoading && sparqState.feed.isEmpty;
    final otherCount = showSkeletonForOthers
        ? 3
        : items.length; // 3 skeleton slots during initial load

    return SizedBox(
      height: 96, // avatar (52) + label (12+10) + breathing room
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        // +1 for the leading "You / Add yours" item.
        itemCount: 1 + otherCount,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            // "You" is always first.
            return _YouItem(
              hasCurrentSparq: viewerHasCurrentSparq,
              allSeen: viewerAllSeen,
              avatarUrl: viewerAvatarUrl,
              firstName: viewerFirstName,
              viewerLinkedUserId: viewerLinkedUserId,
              viewerPersonId: viewerPersonId,
              onAddYours: onAddYours,
            );
          }
          if (showSkeletonForOthers) {
            return const _SkeletonCircle();
          }
          final item = items[index - 1];
          return _KinshipRingItem(item: item);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Closeness score — drives the within-group sort (birthday-soon is
// the primary sort; this is the secondary tie-break after that).
// ═══════════════════════════════════════════════════════════════════════

/// Heuristic kinship-key → closeness score (lower = closer).
///
/// Tier 0: parent (father, mother, step_father, step_mother).
/// Tier 1: spouse (husband, wife).
/// Tier 2: sibling (brother, sister, half_*, step_* sibling).
/// Tier 3: child (son, daughter, step_son, step_daughter).
/// Tier 4: grandparent (paternal/maternal_grandfather/grandmother,
///         great_grandfather/grandmother) — prioritized as elders.
/// Tier 5: in-law (father_in_law, mother_in_law, etc.).
/// Tier 6: aunt/uncle (uncle, aunt, paternal_uncle, etc.,
///         fathers_brother, mothers_sister, etc.).
/// Tier 7: niece/nephew.
/// Tier 8: cousin.
/// Tier 9: extended/other/unknown.
int _closenessScoreForKey(String? key) {
  if (key == null || key.isEmpty) return 9;
  final k = key.toLowerCase();

  if (k == 'father' || k == 'mother' || k == 'parent' ||
      k == 'step_father' || k == 'step_mother' ||
      k == 'stepfather' || k == 'stepmother') {
    return 0;
  }
  if (k == 'husband' || k == 'wife' || k == 'spouse' || k == 'partner') {
    return 1;
  }
  if (k == 'brother' || k == 'sister' || k == 'sibling' ||
      k.contains('half_brother') || k.contains('half_sister') ||
      k.contains('step_brother') || k.contains('step_sister') ||
      k == 'elder_brother' || k == 'younger_brother' ||
      k == 'elder_sister' || k == 'younger_sister') {
    return 2;
  }
  if (k == 'son' || k == 'daughter' || k == 'child' ||
      k == 'step_son' || k == 'step_daughter') {
    return 3;
  }
  if (k.contains('grandfather') || k.contains('grandmother') ||
      k.contains('grandparent') || k.contains('great_grand')) {
    return 4;
  }
  if (k.contains('in_law')) {
    return 5;
  }
  if (k == 'uncle' || k == 'aunt' ||
      k.contains('paternal_uncle') || k.contains('paternal_aunt') ||
      k.contains('maternal_uncle') || k.contains('maternal_aunt') ||
      k.contains('fathers_brother') || k.contains('fathers_sister') ||
      k.contains('mothers_brother') || k.contains('mothers_sister') ||
      k.contains('parents_sibling')) {
    return 6;
  }
  if (k == 'nephew' || k == 'niece' ||
      k.contains('brothers_son') || k.contains('brothers_daughter') ||
      k.contains('sisters_son') || k.contains('sisters_daughter') ||
      k.contains('sibling_child')) {
    return 7;
  }
  if (k.contains('cousin')) {
    return 8;
  }
  return 9;
}

// ═══════════════════════════════════════════════════════════════════════
// "You / Add yours" — leading item, ALWAYS first
// ═══════════════════════════════════════════════════════════════════════

class _YouItem extends ConsumerWidget {
  const _YouItem({
    required this.hasCurrentSparq,
    required this.allSeen,
    required this.avatarUrl,
    required this.firstName,
    required this.viewerLinkedUserId,
    required this.viewerPersonId,
    required this.onAddYours,
  });

  /// True when the viewer has at least one current (non-expired)
  /// Sparq. Drives whether we render the story ring around the
  /// avatar.
  final bool hasCurrentSparq;

  /// Whether all of the viewer's own Sparqs have been seen. Only
  /// meaningful when [hasCurrentSparq] is true.
  final bool allSeen;

  final String? avatarUrl;
  final String firstName;
  final String? viewerLinkedUserId;
  final String? viewerPersonId;
  final VoidCallback onAddYours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The "You" item is always rendered — even with no Sparq at
    // all. The plus badge always sits at the bottom-right of the
    // avatar so the user can always create a new Sparq.
    //
    // When the viewer has a current Sparq, the avatar gets a story
    // ring (gradient when unseen, dim when seen). Tapping the
    // avatar opens the viewer's own Sparq viewer. Tapping the plus
    // badge always opens /sparq/create.
    final semanticLabel = hasCurrentSparq
        ? 'Your Sparq${allSeen ? ', seen' : ', new'}'
        : 'Add your Sparq';

    return semanticButton(
      label: semanticLabel,
      hint: hasCurrentSparq
          ? 'Double tap to view your Sparq. The plus badge opens the Sparq composer.'
          : 'Double tap to add your Sparq',
      child: _YouAvatarWithPlus(
        hasCurrentSparq: hasCurrentSparq,
        allSeen: allSeen,
        avatarUrl: avatarUrl,
        firstName: firstName,
        linkedUserId: viewerLinkedUserId,
        // When the viewer has no Sparq, the whole avatar opens the
        // composer (matches the plus badge). When they have a
        // Sparq, the avatar opens their Sparq viewer.
        onAvatarTap: () {
          HapticService.selection();
          if (hasCurrentSparq && viewerLinkedUserId != null) {
            context.push('/sparq/viewer/$viewerLinkedUserId');
          } else {
            onAddYours();
          }
        },
        onPlusTap: () {
          HapticService.tap();
          onAddYours();
        },
      ),
    );
  }
}

/// Composite widget: avatar + optional story ring + plus badge +
/// labels below. Extracted so semanticButton can wrap the whole
/// tap target (≥44dp) while we keep the avatar + plus badge as
/// distinct hit regions.
class _YouAvatarWithPlus extends StatelessWidget {
  const _YouAvatarWithPlus({
    required this.hasCurrentSparq,
    required this.allSeen,
    required this.avatarUrl,
    required this.firstName,
    required this.linkedUserId,
    required this.onAvatarTap,
    required this.onPlusTap,
  });

  final bool hasCurrentSparq;
  final bool allSeen;
  final String? avatarUrl;
  final String firstName;
  final String? linkedUserId;
  final VoidCallback onAvatarTap;
  final VoidCallback onPlusTap;

  @override
  Widget build(BuildContext context) {
    // The avatar size is 52px. Wrap in a 60px-wide Column so the
    // labels have breathing room.
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Avatar (with optional story ring) — fills the
                // 52x52 box. Tap opens the viewer's Sparq viewer
                // (when they have a Sparq) or the Sparq composer
                // (when they don't).
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onAvatarTap,
                    behavior: HitTestBehavior.opaque,
                    child: hasCurrentSparq
                        ? SparqRingAvatar(
                            // The viewer's own linkedUserId —
                            // SparqRingAvatar's internal
                            // sparqState.feed lookup finds the
                            // matching group and renders the
                            // right ring state (unseen gradient /
                            // seen dim).
                            userId: linkedUserId ?? '',
                            avatarUrl: avatarUrl,
                            radius: 22,
                            isSeen: allSeen,
                            onTap: onAvatarTap,
                          )
                        : _PlainAvatar(avatarUrl: avatarUrl),
                  ),
                ),
                // Plus badge — always present (bottom-right). Even
                // when the viewer has a current Sparq, the plus
                // badge lets them create a new one.
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: GestureDetector(
                    onTap: onPlusTap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _cOrange,
                        border: Border.all(
                          color: _cBg,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // "You" — bold. ≥ 12sp.
          SizedBox(
            width: 58,
            child: const Text(
              'You',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),
          ),
          // Sub-label: "Add yours" (no Sparq) or firstName (has
          // Sparq). ≥ 10sp.
          SizedBox(
            width: 58,
            child: Text(
              hasCurrentSparq ? firstName : 'Add yours',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _cTextDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain avatar (no ring) for the no-Sparq case. Mirrors
/// SparqRingAvatar's avatar rendering so the visual stays
/// consistent.
class _PlainAvatar extends StatelessWidget {
  const _PlainAvatar({required this.avatarUrl});
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
          ? NetworkImage(avatarUrl!)
          : null,
      backgroundColor: _cElevated,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Icon(Icons.person,
              size: 22,
              color: _cTextSecondary.withValues(alpha: 0.4))
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// One relative item — ring + kinship term + first name + optional badge
// ═══════════════════════════════════════════════════════════════════════

class _KinshipRingItem extends ConsumerWidget {
  const _KinshipRingItem({required this.item});

  final _RingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Birthday badge appears ONLY when the person has a Sparq
    // (which they do — only Sparq authors are rendered) AND a
    // birthday within 7 days.
    final hasBirthday =
        item.daysUntilBirthday != null && item.daysUntilBirthday! <= 7;

    final semanticState = item.isSeen ? 'seen' : 'new';
    final semanticLabel =
        '${item.kinshipPrimary}\'s Sparq, $semanticState';

    return semanticButton(
      label: semanticLabel,
      hint: 'Double tap to view ${item.firstName}\'s Sparq',
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          // Open the Sparq viewer for this relative. The route
          // expects the auth userId (linkedUserId), NOT the
          // Person.id.
          if (item.linkedUserId != null) {
            context.push('/sparq/viewer/${item.linkedUserId}');
          }
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 60, // 56px tap target + 4px breathing room
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: SparqRingAvatar(
                        // Pass the linkedUserId so SparqRingAvatar's
                        // internal sparqState.feed lookup finds the
                        // matching group and renders the right ring
                        // state (unseen gradient / seen dim).
                        userId: item.linkedUserId ?? item.personId,
                        avatarUrl: item.avatarUrl,
                        radius: 22,
                        isSeen: item.isSeen,
                        onTap: () {
                          HapticService.selection();
                          if (item.linkedUserId != null) {
                            context.push(
                                '/sparq/viewer/${item.linkedUserId}');
                          }
                        },
                      ),
                    ),
                    if (hasBirthday)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _cBirthday,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _cBg,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${item.daysUntilBirthday}d',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                fontFamily: KinrelTypography.monoFont,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // PRIMARY LABEL — kinship term, bold.
              SizedBox(
                width: 58,
                child: Text(
                  item.kinshipPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: item.isSeen ? _cTextSecondary : _cTextPrimary,
                  ),
                ),
              ),
              // SECONDARY LABEL — first name, small.
              SizedBox(
                width: 58,
                child: Text(
                  item.firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    fontWeight:
                        item.isSeen ? FontWeight.w400 : FontWeight.w500,
                    color: _cTextDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Skeleton circle — shimmer during initial Sparq load
// ═══════════════════════════════════════════════════════════════════════

class _SkeletonCircle extends StatefulWidget {
  const _SkeletonCircle();

  @override
  State<_SkeletonCircle> createState() => _SkeletonCircleState();
}

class _SkeletonCircleState extends State<_SkeletonCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final opacity = 0.08 + (_controller.value * 0.08);
          return Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: opacity),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 40,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
