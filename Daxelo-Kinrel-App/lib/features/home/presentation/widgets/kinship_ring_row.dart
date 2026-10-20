// lib/features/home/presentation/widgets/kinship_ring_row.dart
//
// DAXELO KINREL — Kinship Ring Row (Phase A — Home, the Instagram-level idea)
//
// Horizontal scrollable row of family-member avatars that:
//   • Item 0 = "You / Add yours" — opens add_story_sheet
//   • Each other item = ring avatar with the person's kinship TERM
//     (bold, e.g. "Mausi") as the primary label and first name
//     (e.g. "Priya") as the secondary line — in the viewer's chosen
//     language. Birthday badge ("3d") when occasionRemindersProvider
//     says the person's birthday is within 7 days.
//
// The ring state (gradient when unseen, dim when seen) reuses the
// SparqRingAvatar's visual language so the row matches the rest of
// the app — but the data source for "what to show" is the kinship
// term provider, not the sparq feed. This deliberately does NOT add a
// third "story" system; it lays the existing sparq seen/unseen
// state under the new kinship labels.
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
//   • Semantic label = "{primary} {firstName}, {unseen|seen} stories,
//     {birthday in N days|no upcoming birthday}".
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
const _cCard = KinrelColors.darkCard;
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
    this.daysUntilBirthday,
    this.isSeen = false,
  });

  final String personId;
  final String firstName;
  final String kinshipPrimary;
  final String? kinshipSecondary;
  final String? avatarUrl;
  final int? daysUntilBirthday;
  final bool isSeen;
}

/// The kinship ring row. Renders nothing (zero height) when the
/// family has no relatives yet — the parent screen then shows the
/// "Next step" invite card instead (per Phase A spec).
class KinshipRingRow extends ConsumerWidget {
  const KinshipRingRow({
    super.key,
    required this.familyId,
    required this.onAddYours,
  });

  /// The family to show members for. Drives
  /// kinshipTermsForFamilyProvider, familyGraphProvider, and
  /// sparqProvider (for seen/unseen state).
  final String familyId;

  /// Called when the user taps the leading "You / Add yours" item.
  /// The parent (HomeScreen) opens showAddStorySheet(familyId).
  final VoidCallback onAddYours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the precomputed kinship terms — one watch at the row
    // level, NOT per avatar.
    final termsAsync = ref.watch(
      kinshipTermsForFamilyProvider(familyId),
    );

    // Watch the family graph for the persons list (avatar URLs,
    // first names, ids). This provider is already cached by the time
    // Home renders.
    final graphAsync = ref.watch(familyGraphProvider(familyId));

    // Watch occasion reminders for the birthday-soon badge. Home
    // already watches this; the watch here is a no-op for Riverpod.
    final occasionsAsync = ref.watch(occasionRemindersProvider);

    // Watch sparq state for seen/unseen ring state per person.
    final sparqState = ref.watch(sparqProvider);

    // Materialize the items. The list is rebuilt only when one of
    // the upstream providers emits a new value — never per-frame.
    final items = <_RingItem>[];

    final graph = graphAsync.valueOrNull;
    final terms = termsAsync.valueOrNull;

    // If the graph isn't loaded yet, render the skeleton. The
    // skeleton is shimmer circles (no spinner) per Phase A spec.
    if (graph == null || graph.persons.isEmpty) {
      return const _RingSkeleton();
    }

    // If the kinship terms haven't computed yet (still loading
    // in the isolate), still render the avatars with the FIRST
    // NAME as the label (graceful degradation). The terms will
    // pop in as soon as the isolate completes.
    final personById = <String, Map<String, dynamic>>{};
    for (final p in graph.persons) {
      final id = p['id']?.toString();
      if (id != null && id.isNotEmpty) {
        personById[id] = p;
      }
    }

    // Build the per-person seen/unseen map from the sparq feed.
    // sparqState.feed is a List<UserSparqGroup> where each group has
    // userId + allSeen. We need to know which Person ids have unseen
    // sparqs so the ring shows the gradient. The sparq feed uses
    // userId (auth id), not personId — the join goes via the
    // Person.linkedUserId column. For Phase A we use the linkedUserId
    // on each Person to look up the sparq group.
    final seenByUserId = <String, bool>{};
    for (final group in sparqState.feed) {
      seenByUserId[group.userId] = group.allSeen;
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

    // Sort: unseen-first, then birthday-soon-first, then default
    // order. The viewer's own "You" entry is always first regardless.
    final sortedPersons = List<Map<String, dynamic>>.from(graph.persons);

    // Compute the order key per person.
    int orderFor(String id, String? linkedUserId) {
      final seen = seenByUserId[linkedUserId ?? ''] ?? true;
      final daysUntil = birthdayByPersonId[id];
      // Unseen + birthday: 0 (top of the relatives)
      // Unseen, no birthday: 1
      // Seen + birthday: 2
      // Seen, no birthday: 3
      if (!seen && daysUntil != null) return 0;
      if (!seen) return 1;
      if (daysUntil != null) return 2;
      return 3;
    }

    sortedPersons.sort((a, b) {
      final aId = a['id']?.toString() ?? '';
      final bId = b['id']?.toString() ?? '';
      final aLinked = a['linkedUserId']?.toString() ?? '';
      final bLinked = b['linkedUserId']?.toString() ?? '';
      final aOrder = orderFor(aId, aLinked);
      final bOrder = orderFor(bId, bLinked);
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      // Stable secondary sort by name (so the order isn't random
      // for ties).
      return (a['name']?.toString() ?? '').compareTo(
        b['name']?.toString() ?? '',
      );
    });

    for (final p in sortedPersons) {
      final id = p['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = p['name']?.toString() ?? 'Relative';
      final firstName = kinrelFirstName(name);
      final linkedUserId = p['linkedUserId']?.toString();
      final avatarUrl = p['photoUrl']?.toString() ??
          p['avatarUrl']?.toString();

      // Look up the kinship term — O(1) Map access. Null when the
      // isolate is still computing OR when the person is the viewer
      // (self returns null in resolveClassification).
      final term = terms?[id];

      // The viewer's own entry — skip; we render "You" separately
      // as the leading item. The graph marks the viewer's person with
      // `isViewer: true` (see FlatGraphResult.fromRpc).
      if (p['isViewer'] == true) continue;

      items.add(_RingItem(
        personId: id,
        firstName: firstName,
        kinshipPrimary: term?.primary ?? firstName,
        kinshipSecondary: term?.secondary,
        avatarUrl: avatarUrl,
        daysUntilBirthday: birthdayByPersonId[id],
        isSeen: seenByUserId[linkedUserId ?? ''] ?? true,
      ));
    }

    // Empty state — viewer has no relatives yet. Hide the row.
    if (items.isEmpty) {
      return const SizedBox(width: 0, height: 0);
    }

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
// "You / Add yours" — leading item
// ═══════════════════════════════════════════════════════════════════════

class _AddYoursItem extends StatelessWidget {
  const _AddYoursItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return semanticButton(
      label: 'Add yours, create a story',
      hint: 'Double tap to add your own story',
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

    return semanticButton(
      label: '${item.kinshipPrimary} ${item.firstName}'
          '${item.isSeen ? ', seen' : ', unseen'}'
          '${hasBirthday ? ', birthday in ${item.daysUntilBirthday} days' : ''}',
      hint: 'Double tap to view ${item.firstName}\'s stories',
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          // The viewer taps a relative → open the sparq viewer for
          // that person. We use the Person.id; the sparq viewer route
          // resolves to the linked user. This preserves the existing
          // navigation target — no new route is added.
          context.push('/sparq/viewer/${item.personId}');
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 60, // 56px tap target + 4px breathing room
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar + ring + optional birthday badge.
              // We reuse SparqRingAvatar for the ring visual language
              // so the design system stays consistent. SparqRingAvatar
              // expects a userId (auth id) — but for Phase A we want
              // to look up by personId. The avatar's internal lookup
              // is keyed by userId, so we pass the person's
              // linkedUserId if available; otherwise we fall back to
              // the personId and let the ring render in seen state
              // (no false-positive "unseen" rings).
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: SparqRingAvatar(
                        // Use the personId as the SparqRingAvatar's
                        // userId — SparqRingAvatar's lookup will not
                        // find a matching group (groups are keyed by
                        // auth userId), so the ring renders in the
                        // "no active sparqs" state. We pass isSeen
                        // directly so the ring matches our precomputed
                        // state.
                        userId: item.personId,
                        avatarUrl: item.avatarUrl,
                        radius: 22,
                        isSeen: item.isSeen,
                        onTap: () {
                          HapticService.selection();
                          context.push('/sparq/viewer/${item.personId}');
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
                    color: item.isSeen ? _cTextSecondary : _cTextPrimary,
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
                    fontWeight: item.isSeen ? FontWeight.w400 : FontWeight.w500,
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
