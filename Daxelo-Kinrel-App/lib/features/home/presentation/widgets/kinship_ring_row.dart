// lib/features/home/presentation/widgets/kinship_ring_row.dart
//
// DAXELO KINREL — Kinship Ring Row (Phase A — Home, the Instagram-level idea)
//
// Horizontal scrollable row of family-member avatars that:
//   • Item 0 = "You / Add yours" — opens /sparq/create (the Sparq
//     composer). Per the user's Phase A decision, we do NOT revive
//     the legacy add_story_sheet / stories system. Sparq is the
//     existing story-like surface.
//   • Each other item = ring avatar with the person's kinship TERM
//     (bold, e.g. "Mausi") as the primary label and first name
//     (e.g. "Priya") as the secondary line — in the viewer's chosen
//     language. Birthday badge ("3d") when occasionRemindersProvider
//     says the person's birthday is within 7 days.
//
// Ordering (Phase A decision 2):
//   1. People with current Sparqs first — unseen first, then seen.
//      No cap (all Sparq authors are surfaced so the viewer can
//      catch up on everyone).
//   2. Then up to 8 closest relatives + elders with a dim ring
//      (no Sparq). Closeness is a heuristic on the kinship key:
//      parent < spouse < sibling < child < grandparent < in-law
//      < aunt/uncle < niece/nephew < cousin < extended. Elders
//      (grandparents, great-grandparents) are prioritized by the
//      closeness score itself.
//
// Visibility (Phase A decision 2):
//   • Hide the row entirely if the viewer has fewer than 2 relatives
//     (i.e. terms.length < 2). The parent screen then shows the
//     "Next step" invite card.
//
// Tap behavior (Phase A decision 2):
//   • Person WITH a Sparq → /sparq/viewer/<linkedUserId> (the
//     existing Sparq viewer route expects the auth userId, which
//     we read from Person.linkedUserId).
//   • Person WITHOUT a Sparq → PersonDetailSheet.show(person,
//     familyId). Opens the existing profile sheet — no new route.
//
// The ring state (gradient when unseen, dim when seen / no-Sparq)
// reuses the SparqRingAvatar's visual language. This deliberately
// does NOT add a third "story" system; it lays the existing sparq
// seen/unseen state under the new kinship labels.
//
// Performance:
//   • Reads the precomputed Map<String, KinshipTerm> once at the
//     row level — no per-avatar provider watches.
//   • Each avatar looks up its term by id in the Map (O(1)).
//   • The Map is recomputed off-UI-thread by
//     kinshipTermsForFamilyProvider; this widget just renders.
//
// Accessibility:
//   • Minimum tap target 44dp on every avatar (52px visual + 4px
//     hit-padding = 56px tap target).
//   • Primary text ≥ 12sp bold; secondary text ≥ 10sp.
//   • Semantic label = "{primary} {firstName}, {unseen|seen|no
//     sparq}, {birthday in N days|no upcoming birthday}".
//   • Respects reduced motion (no fire-pulse on calm rings when
//     Toggler is off — handled inside SparqRingAvatar via KinrelFx).
//   • Works at 1.5x font scale (SizedBox width is 56 but text
//     expands vertically with maxLines: 1 + ellipsis; the row
//     stays horizontal-scroll so it never overflows).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/family/family_provider.dart' show Person;
import '../../../../core/kinship/kinship_term_providers.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/utils/accessibility_utils.dart';
import '../../../family/presentation/person_detail_sheet.dart';
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

/// Cap for the "no-Sparq closest relatives" section. Per Phase A
/// decision 2: "up to 8 closest relatives and elders with a dim
/// ring (no Sparq)".
const int kNoSparqRelativesCap = 8;

/// Minimum number of reachable relatives for the row to render at
/// all. Per Phase A decision 2: "Hide the row if the viewer has
/// fewer than 2 relatives."
const int kMinRelativesToRenderRow = 2;

/// A single ring-row item after all the data has been resolved.
///
/// Pre-computed at row level so the build method is pure paint.
class _RingItem {
  const _RingItem({
    required this.personId,
    required this.person,
    required this.firstName,
    required this.kinshipPrimary,
    this.kinshipSecondary,
    this.avatarUrl,
    this.linkedUserId,
    this.daysUntilBirthday,
    this.hasActiveSparq = false,
    this.isSeen = false,
    this.closenessScore = 99,
  });

  final String personId;
  final Person person;
  final String firstName;
  final String kinshipPrimary;
  final String? kinshipSecondary;
  final String? avatarUrl;
  final String? linkedUserId;
  final int? daysUntilBirthday;

  /// True when this person has at least one Sparq in sparqState.feed
  /// (i.e. they're a Sparq author). Drives the tap target: with-Sparq
  /// → opens `/sparq/viewer/<userId>`; without-Sparq → opens
  /// `PersonDetailSheet` (profile).
  final bool hasActiveSparq;

  /// Sparq-seen state from sparqState.feed. Only meaningful when
  /// [hasActiveSparq] is true; false-positive "seen" for no-Sparq
  /// items so the ring renders dim (matches decision 2's "dim ring
  /// (no Sparq)" requirement).
  final bool isSeen;

  /// Closeness score for the no-Sparq section's sort. Lower = closer.
  /// Computed from the kinship key (see _closenessScoreForKey).
  final int closenessScore;
}

/// The kinship ring row. Renders nothing (zero height) when the
/// viewer has fewer than [kMinRelativesToRenderRow] relatives —
/// per Phase A decision 2.
class KinshipRingRow extends ConsumerWidget {
  const KinshipRingRow({
    super.key,
    required this.familyId,
    required this.onAddYours,
  });

  final String familyId;
  final VoidCallback onAddYours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the precomputed kinship terms — one watch at the row
    // level, NOT per avatar.
    final termsAsync = ref.watch(
      kinshipTermsForFamilyProvider(familyId),
    );

    final graphAsync = ref.watch(familyGraphProvider(familyId));
    final occasionsAsync = ref.watch(occasionRemindersProvider);
    final sparqState = ref.watch(sparqProvider);

    final graph = graphAsync.valueOrNull;
    final terms = termsAsync.valueOrNull;

    // If the graph isn't loaded yet, render the skeleton. The
    // skeleton is shimmer circles (no spinner) per Phase A spec.
    if (graph == null || graph.persons.isEmpty) {
      return const _RingSkeleton();
    }

    // Per-person seen/unseen map from the sparq feed. sparqState.feed
    // is a List<UserSparqGroup> keyed by auth userId. We join via
    // Person.linkedUserId.
    final hasSparqByLinkedUserId = <String, bool>{};
    final seenByLinkedUserId = <String, bool>{};
    for (final group in sparqState.feed) {
      hasSparqByLinkedUserId[group.userId] = group.sparqs.isNotEmpty;
      seenByLinkedUserId[group.userId] = group.allSeen;
    }

    // Birthday badges: occasionRemindersProvider already computes
    // daysUntil for every person across all families.
    final birthdayByPersonId = <String, int>{};
    final occasions = occasionsAsync.valueOrNull;
    if (occasions != null) {
      for (final o in occasions.withinSevenDays) {
        if (o.type == OccasionType.birthday) {
          birthdayByPersonId[o.personId] = o.daysUntil;
        }
      }
    }

    // Build the candidate list (all non-viewer persons).
    final candidates = <_RingItem>[];
    for (final p in graph.persons) {
      final id = p['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (p['isViewer'] == true) continue; // skip self

      final name = p['name']?.toString() ?? 'Relative';
      final firstName = kinrelFirstName(name);
      final linkedUserId = p['linkedUserId']?.toString();
      final avatarUrl =
          p['photoUrl']?.toString() ?? p['avatarUrl']?.toString();
      final term = terms?[id];

      final hasActiveSparq =
          linkedUserId != null && (hasSparqByLinkedUserId[linkedUserId] ?? false);
      final isSeen = seenByLinkedUserId[linkedUserId ?? ''] ?? true;

      // Build the Person object for the tap-to-profile behavior.
      // The graph person Map has the keys Person.fromJson expects
      // PLUS a few extras (isViewer, photoUrl) — fromJson ignores
      // unknown keys, and we add familyId which is required.
      final personJson = Map<String, dynamic>.from(p);
      personJson['familyId'] = familyId;
      final person = Person.fromJson(personJson);

      candidates.add(_RingItem(
        personId: id,
        person: person,
        firstName: firstName,
        kinshipPrimary: term?.primary ?? firstName,
        kinshipSecondary: term?.secondary,
        avatarUrl: avatarUrl,
        linkedUserId: linkedUserId,
        daysUntilBirthday: birthdayByPersonId[id],
        hasActiveSparq: hasActiveSparq,
        isSeen: isSeen,
        closenessScore: _closenessScoreForKey(term?.kinshipKey),
      ));
    }

    // Phase A decision 2: hide if viewer has fewer than 2 relatives.
    // "Relatives" = persons with a kinship term resolved (reachable).
    final reachableCount =
        candidates.where((c) => c.kinshipPrimary != c.firstName).length;
    // Also count candidates who have an active Sparq — they're
    // "relatives" too even if the kinship isolate hasn't resolved
    // yet (graceful degradation while loading).
    final totalRelatives = candidates.length;
    if (totalRelatives < kMinRelativesToRenderRow &&
        reachableCount < kMinRelativesToRenderRow) {
      return const SizedBox(width: 0, height: 0);
    }

    // ── Sort: Section A (Sparq authors) + Section B (closest no-Sparq) ──
    final withSparq = candidates.where((c) => c.hasActiveSparq).toList();
    final withoutSparq = candidates.where((c) => !c.hasActiveSparq).toList();

    // Section A sort: unseen first, then seen. Stable tie-break by name.
    withSparq.sort((a, b) {
      final aSeen = a.isSeen ? 1 : 0;
      final bSeen = b.isSeen ? 1 : 0;
      if (aSeen != bSeen) return aSeen.compareTo(bSeen);
      return a.firstName.compareTo(b.firstName);
    });

    // Section B sort: by closeness score (lower = closer), then by
    // name. Cap at kNoSparqRelativesCap.
    withoutSparq.sort((a, b) {
      final c = a.closenessScore.compareTo(b.closenessScore);
      if (c != 0) return c;
      return a.firstName.compareTo(b.firstName);
    });
    final noSparqCapped = withoutSparq.length > kNoSparqRelativesCap
        ? withoutSparq.sublist(0, kNoSparqRelativesCap)
        : withoutSparq;

    final items = [...withSparq, ...noSparqCapped];

    return SizedBox(
      height: 96, // avatar (52) + label (12+10) + breathing room
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        // +1 for the leading "You / Add yours" item.
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _AddYoursItem(onTap: onAddYours);
          }
          final item = items[index - 1];
          return _KinshipRingItem(item: item, familyId: familyId);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Closeness score — drives the no-Sparq section's "8 closest" cap
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
///
/// The exact tier boundaries aren't critical — the goal is just to
/// surface the viewer's nearest kin first when capping at 8.
int _closenessScoreForKey(String? key) {
  if (key == null || key.isEmpty) return 9;
  final k = key.toLowerCase();

  // Parents
  if (k == 'father' || k == 'mother' || k == 'parent' ||
      k == 'step_father' || k == 'step_mother' ||
      k == 'stepfather' || k == 'stepmother') {
    return 0;
  }
  // Spouses
  if (k == 'husband' || k == 'wife' || k == 'spouse' ||
      k == 'partner') {
    return 1;
  }
  // Siblings
  if (k == 'brother' || k == 'sister' || k == 'sibling' ||
      k.contains('half_brother') || k.contains('half_sister') ||
      k.contains('step_brother') || k.contains('step_sister') ||
      k == 'elder_brother' || k == 'younger_brother' ||
      k == 'elder_sister' || k == 'younger_sister') {
    return 2;
  }
  // Children
  if (k == 'son' || k == 'daughter' || k == 'child' ||
      k == 'step_son' || k == 'step_daughter') {
    return 3;
  }
  // Grandparents (elders — prioritized by the score itself)
  if (k.contains('grandfather') || k.contains('grandmother') ||
      k.contains('grandparent') || k.contains('great_grand')) {
    return 4;
  }
  // In-laws
  if (k.contains('in_law')) {
    return 5;
  }
  // Aunts / uncles
  if (k == 'uncle' || k == 'aunt' ||
      k.contains('paternal_uncle') || k.contains('paternal_aunt') ||
      k.contains('maternal_uncle') || k.contains('maternal_aunt') ||
      k.contains('fathers_brother') || k.contains('fathers_sister') ||
      k.contains('mothers_brother') || k.contains('mothers_sister') ||
      k.contains('parents_sibling')) {
    return 6;
  }
  // Nieces / nephews
  if (k == 'nephew' || k == 'niece' ||
      k.contains('brothers_son') || k.contains('brothers_daughter') ||
      k.contains('sisters_son') || k.contains('sisters_daughter') ||
      k.contains('sibling_child')) {
    return 7;
  }
  // Cousins
  if (k.contains('cousin')) {
    return 8;
  }
  // Extended / unknown / compound we couldn't classify
  return 9;
}

// ═══════════════════════════════════════════════════════════════════════
// "You / Add yours" — leading item
// ═══════════════════════════════════════════════════════════════════════

class _AddYoursItem extends StatelessWidget {
  const _AddYoursItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return semanticButton(
      label: 'Add yours, create a Sparq',
      hint: 'Double tap to open the Sparq composer',
      child: GestureDetector(
        onTap: () {
          HapticService.tap();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          // 56px tap target (≥ 44dp minimum) — wide enough for
          // elder-friendly tapping.
          width: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Dashed-orange circle with a "+" — matches the existing
              // _AddFamilyCircle visual language on the legacy family
              // switcher so users recognize "add" affordance.
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cElevated,
                  border: Border.all(
                    color: _cOrange.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: _cOrange,
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'You',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _cTextSecondary,
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
// One relative item — ring + kinship term + first name + optional badge
// ═══════════════════════════════════════════════════════════════════════

class _KinshipRingItem extends ConsumerWidget {
  const _KinshipRingItem({required this.item, required this.familyId});

  final _RingItem item;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasBirthday =
        item.daysUntilBirthday != null && item.daysUntilBirthday! <= 7;

    final semanticState = item.hasActiveSparq
        ? (item.isSeen ? 'seen Sparqs' : 'unseen Sparqs')
        : 'no Sparqs yet';

    return semanticButton(
      label: '${item.kinshipPrimary} ${item.firstName}, $semanticState'
          '${hasBirthday ? ', birthday in ${item.daysUntilBirthday} days' : ''}',
      hint: item.hasActiveSparq
          ? 'Double tap to view ${item.firstName}\'s Sparqs'
          : 'Double tap to open ${item.firstName}\'s profile',
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          if (item.hasActiveSparq && item.linkedUserId != null) {
            // With-Sparq → open the Sparq viewer route. The route
            // expects the auth userId (linkedUserId), NOT the
            // Person.id — see sparq_feed_row.dart's usage.
            context.push('/sparq/viewer/${item.linkedUserId}');
          } else {
            // Without-Sparq → open the person's profile sheet.
            // Phase A decision 2: tapping a relative without a
            // Sparq opens their profile, not the sparq viewer.
            PersonDetailSheet.show(
              context,
              person: item.person,
              familyId: familyId,
            );
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 60, // 56px tap target + 4px breathing room
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
                        // state (unseen gradient, seen dim, or no
                        // active sparqs = no ring).
                        userId: item.linkedUserId ?? item.personId,
                        avatarUrl: item.avatarUrl,
                        radius: 22,
                        isSeen: item.isSeen,
                        onTap: () {
                          HapticService.selection();
                          if (item.hasActiveSparq &&
              item.linkedUserId != null) {
                            context.push(
                                '/sparq/viewer/${item.linkedUserId}');
                          } else {
                            PersonDetailSheet.show(
                              context,
                              person: item.person,
                              familyId: familyId,
                            );
                          }
                        },
                      ),
                    ),
                    // Birthday badge ("3d") — gold pill, top-right.
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
              // PRIMARY LABEL — kinship term, bold. ≥ 12sp per
              // accessibility rules. Single-line with ellipsis; the
              // row is horizontally scrollable so clipping is fine.
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
                    // Unseen Sparqs get the bright primary color.
                    // Seen / no-Sparq → secondary (dim) per decision 2.
                    color: (item.hasActiveSparq && !item.isSeen)
                        ? _cTextPrimary
                        : _cTextSecondary,
                  ),
                ),
              ),
              // SECONDARY LABEL — first name, smaller. ≥ 10sp.
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
                    fontWeight: (item.hasActiveSparq && !item.isSeen)
                        ? FontWeight.w500
                        : FontWeight.w400,
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
// Skeleton — shimmer circles, no spinner (per Phase A spec)
// ═══════════════════════════════════════════════════════════════════════

class _RingSkeleton extends StatefulWidget {
  const _RingSkeleton();

  @override
  State<_RingSkeleton> createState() => _RingSkeletonState();
}

class _RingSkeletonState extends State<_RingSkeleton>
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
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, index) {
          // The first skeleton slot represents the "You / Add yours"
          // item — render it as a dashed circle to communicate the
          // "add" affordance even during loading.
          if (index == 0) {
            return Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _cElevated,
                      border: Border.all(
                        color: _cOrange.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: _cOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: _cTextSecondary,
                    ),
                  ),
                ],
              ),
            );
          }
          return AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              final opacity = 0.08 + (_controller.value * 0.08);
              return Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}
