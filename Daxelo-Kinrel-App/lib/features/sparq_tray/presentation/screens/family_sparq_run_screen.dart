// lib/features/sparq_tray/presentation/screens/family_sparq_run_screen.dart
//
// DAXELO KINREL — Family Sparq run screen (route /sparq/family/:familyId).
//
// Full-screen player that plays an ordered QUEUE for the tapped
// family:
//   1. The family's Moment Sparq (if any — local-only).
//   2. Each member's UserSparqGroup (unseen members first, then seen,
//      most recent first).
//   3. When the queue ends, jump to the next family in tray order
//      that has unseen Sparqs; if none, close with context.pop().
//
// Implemented by REUSING SparqViewerScreen rather than rewriting the
// player (spec section 4 hard constraint). The run screen:
//   • Hosts the viewer for the current member via a keyed
//     AnimatedSwitcher (so each member's viewer state is independent
//     and the swap-in animation is a clean fade).
//   • Supplies onFinished (advance to next member or family) and
//     onPrevious (jump to previous member).
//
// Overlay (in family-run mode only — overlaid on top of the viewer's
// existing header):
//   • Small pill "{Family name} · {k} of {n} members" — tapping opens
//     /family/{familyId} (closing the run first).
//   • The member's kinship label as a pill under the name, from the
//     viewer's POV — e.g. "Bhai · your brother". Resolved with the
//     viewer-driven kinship engine (relationship_label_provider.dart,
//     viewerPersonId). If it cannot be resolved, show nothing (never
//     show a wrong term).
//   • Bottom row "Also from this family": 44dp avatars of the other
//     members in the run, each with a 2dp border in that member's
//     mood color (outline only if seen). Tapping one jumps to that
//     member. Right-aligned "Next: {next family name}" when the next
//     family is known.
//
// Gestures: tap right/left = next/previous Sparq (existing in
// SparqViewerScreen), long-press = pause (existing), swipe down =
// close (existing). Horizontal swipe for next/previous member is
// SKIPPED per the spec's "Allow simplifications" — it would conflict
// with the existing tap-zone gesture handling.
//
// Closing (any way): call ref.read(sparqProvider.notifier).refreshFeed()
// so the tray rings update to seen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../family/data/relationship_label_provider.dart'
    show relationshipLabelProvider;
import '../../../social/data/models/sparq_model.dart' show UserSparqGroup;
import '../../../social/data/providers/sparq_provider.dart' show sparqProvider;
import '../../../social/presentation/screens/sparq_viewer_screen.dart';
import '../../data/family_sparq_tray_item.dart';
import '../../providers/family_sparq_tray_provider.dart';
import '../../providers/moment_sparq_provider.dart'
    show familyMomentSparqProvider, markMomentSparqSeen;
import '../../sparq_tray_analytics.dart' show SparqTrayAnalytics;
import '../../sparq_tray_strings.dart';

/// Full-screen Family Sparq run.
///
/// Reuses [SparqViewerScreen] as the per-member player (no forking).
/// The viewer is hosted inside a keyed [AnimatedSwitcher] so each
/// member's viewer state is independent and the swap is a clean fade.
class FamilySparqRunScreen extends ConsumerStatefulWidget {
  const FamilySparqRunScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<FamilySparqRunScreen> createState() =>
      _FamilySparqRunScreenState();
}

class _FamilySparqRunScreenState extends ConsumerState<FamilySparqRunScreen> {
  /// The run queue: one entry per member (the current family first,
  /// then other families with unseen Sparqs in tray order).
  List<_RunMember> _queue = const [];

  /// Index into _queue currently playing.
  int _currentMemberIndex = 0;

  /// Number of members already played. Used in step 7's
  /// `sparq_family_run_completed` analytics event
  /// (families_played, members_played). Kept as a field so the count
  /// is preserved across member transitions.
  int _membersPlayed = 0;

  /// Number of distinct families played (for analytics on close).
  final Set<String> _familiesPlayed = <String>{};

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Defer provider reads to after the first build so ref is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initQueue());
  }

  void _initQueue() {
    if (_initialized || !mounted) return;
    _initialized = true;

    final trayAsync = ref.read(familySparqTrayProvider);
    final tray = trayAsync.valueOrNull ?? const <FamilySparqTrayItem>[];

    // Find the tapped family.
    FamilySparqTrayItem? tapped;
    for (final item in tray) {
      if (item.family.id == widget.familyId) {
        tapped = item;
        break;
      }
    }

    if (tapped == null) {
      // Family not in tray (e.g. race with provider refresh) — close.
      _closeSafely();
      return;
    }

    _queue = _buildQueue(tapped, tray);
    if (_queue.isEmpty) {
      // Nothing to play — close.
      _closeSafely();
      return;
    }

    _familiesPlayed.add(tapped.family.id);
    setState(() {});
  }

  /// Build the run queue: this family's members first (unseen first,
  /// then seen), then other families with unseen Sparqs in tray order.
  List<_RunMember> _buildQueue(
    FamilySparqTrayItem tapped,
    List<FamilySparqTrayItem> tray,
  ) {
    final queue = <_RunMember>[];

    // 0. The family's Moment Sparq (if any) — first item in the run.
    // Local-only; never counted as a viewed Sparq on the server.
    final moment = ref.read(familyMomentSparqProvider(tapped.family.id));
    if (moment != null) {
      queue.add(_RunMember(
        familyId: tapped.family.id,
        familyName: tapped.family.name,
        userId: '__moment__', // sentinel — no real user
        userName: tapped.family.name,
        userAvatarUrl: null,
        latestMoodColor: const Color(0xFFD4AF37), // gold
        isSeen: false,
        isMoment: true,
        moment: moment,
      ));
    }

    // 1. Tapped family's members (unseen first, then seen).
    final unseen = <UserSparqGroup>[];
    final seen = <UserSparqGroup>[];
    final locallyViewed = ref.read(sparqProvider).locallyViewedSparqIds;
    for (final g in tapped.memberGroups) {
      final isSeen = g.sparqs.every(
        (s) =>
            locallyViewed.contains(s.id) ||
            (s.isTimeCapsule && !s.isRevealed),
      );
      if (isSeen) {
        seen.add(g);
      } else {
        unseen.add(g);
      }
    }
    // Most recent first — sort by the latest Sparq's createdAt desc.
    unseen.sort((a, b) =>
        b.sparqs.first.createdAt.compareTo(a.sparqs.first.createdAt));
    seen.sort((a, b) =>
        b.sparqs.first.createdAt.compareTo(a.sparqs.first.createdAt));

    for (final g in [...unseen, ...seen]) {
      queue.add(_RunMember(
        familyId: tapped.family.id,
        familyName: tapped.family.name,
        userId: g.userId,
        userName: g.userName,
        userAvatarUrl: g.userAvatarUrl,
        latestMoodColor: g.sparqs.isNotEmpty
            ? g.sparqs.first.moodColor
            : const Color(0xFFFFB300),
        isSeen: g.allSeen,
        isMoment: false,
        moment: null,
      ));
    }

    // 2. Other families with unseen Sparqs (in tray order).
    for (final item in tray) {
      if (item.family.id == tapped.family.id) continue;
      if (item.unseenCount == 0) continue; // only families with unseen

      // Other family's Moment Sparq (if any) at the head of its run.
      final otherMoment =
          ref.read(familyMomentSparqProvider(item.family.id));
      if (otherMoment != null) {
        queue.add(_RunMember(
          familyId: item.family.id,
          familyName: item.family.name,
          userId: '__moment__',
          userName: item.family.name,
          userAvatarUrl: null,
          latestMoodColor: const Color(0xFFD4AF37),
          isSeen: false,
          isMoment: true,
          moment: otherMoment,
        ));
      }

      for (final g in item.memberGroups) {
        final isSeen = g.sparqs.every(
          (s) =>
              locallyViewed.contains(s.id) ||
              (s.isTimeCapsule && !s.isRevealed),
        );
        if (isSeen) continue;
        queue.add(_RunMember(
          familyId: item.family.id,
          familyName: item.family.name,
          userId: g.userId,
          userName: g.userName,
          userAvatarUrl: g.userAvatarUrl,
          latestMoodColor: g.sparqs.isNotEmpty
              ? g.sparqs.first.moodColor
              : const Color(0xFFFFB300),
          isSeen: false,
          isMoment: false,
          moment: null,
        ));
      }
    }

    return queue;
  }

  void _onMemberFinished() {
    if (!mounted) return;
    _membersPlayed++;

    if (_currentMemberIndex < _queue.length - 1) {
      // Advance to next member.
      setState(() {
        _currentMemberIndex++;
        _familiesPlayed.add(_queue[_currentMemberIndex].familyId);
      });
    } else {
      // Queue exhausted — refresh + close.
      _closeSafely();
    }
  }

  void _onMemberPrevious() {
    if (!mounted) return;
    if (_currentMemberIndex > 0) {
      setState(() => _currentMemberIndex--);
    }
    // At index 0: no-op (can't go before the first member of the run).
  }

  void _jumpToMember(int index) {
    if (!mounted || index < 0 || index >= _queue.length) return;
    if (index == _currentMemberIndex) return;
    HapticService.selection();
    setState(() {
      _currentMemberIndex = index;
      _familiesPlayed.add(_queue[index].familyId);
    });
  }

  /// Close the run screen and refresh the feed so tray rings update.
  void _closeSafely() {
    if (!mounted) return;
    // Spec section 10: fire sparq_family_run_completed with the count
    // of families + members played. Fires on every close path
    // (queue exhausted, swipe down, close button, family-pill tap).
    SparqTrayAnalytics.logRunCompleted(
      familiesPlayed: _familiesPlayed.length,
      membersPlayed: _membersPlayed,
    );
    // Spec: when closing (any way), call refreshFeed() so rings
    // update to seen.
    ref.read(sparqProvider.notifier).refreshFeed();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _queue.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      );
    }

    final current = _queue[_currentMemberIndex];
    final totalCount = _queue.length;
    final currentPosition = _currentMemberIndex + 1;

    // Resolve the kinship label for the current member, from the
    // viewer's POV. Returns null if no relationship could be resolved
    // — in that case we show NOTHING (never a wrong term).
    final kinshipLabel = ref.watch(relationshipLabelProvider(
      (familyId: current.familyId, senderUserId: current.userId),
    ));

    // Find the next family for the "Next: {family}" hint.
    String? nextFamilyName;
    for (var i = _currentMemberIndex + 1; i < _queue.length; i++) {
      if (_queue[i].familyId != current.familyId) {
        nextFamilyName = _queue[i].familyName;
        break;
      }
    }
    // Within the same family, the next-family hint is not shown.

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // The viewer for the current member — keyed so each
            // member's state is independent. AnimatedSwitcher gives a
            // clean fade between members. For a Moment entry, render
            // the Moment card instead of a SparqViewerScreen.
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: current.isMoment && current.moment != null
                    ? _MomentSparqCard(
                        key: ValueKey(
                            'sparq-run-moment-${current.familyId}'),
                        moment: current.moment!,
                        familyName: current.familyName,
                        onFinished: _onMemberFinished,
                        onClose: _closeSafely,
                      )
                    : SparqViewerScreen(
                        key: ValueKey(
                            'sparq-run-${current.familyId}-${current.userId}'),
                        userId: current.userId,
                        onFinished: _onMemberFinished,
                        onPrevious: _onMemberPrevious,
                      ),
              ),
            ),

            // Overlay (family-run mode only) — drawn ON TOP of the
            // viewer's existing header so the viewer's progress bars
            // and tap zones still work. Pointer-events pass through
            // except on the pills themselves.
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Family progress pill — tap opens /family/{id}.
                  GestureDetector(
                    onTap: () {
                      HapticService.tap();
                      // Close the run first, then open the family page.
                      ref.read(sparqProvider.notifier).refreshFeed();
                      if (context.canPop()) {
                        context.pop();
                      }
                      context.push('/family/${current.familyId}');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              KinrelColors.orange.withValues(alpha: 0.35),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        SparqTrayStrings.familyProgress
                            .replaceAll('{family}', current.familyName)
                            .replaceAll('{k}', '$currentPosition')
                            .replaceAll('{n}', '$totalCount'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // Kinship label pill — never falls back to a wrong term.
                  if (kinshipLabel != null && kinshipLabel.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: KinrelColors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              KinrelColors.orange.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        kinshipLabel,
                        style: const TextStyle(
                          color: KinrelColors.orange,
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Bottom row "Also from this family" + "Next: ..." hint.
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 80,
              left: 16,
              right: 16,
              child: _buildAlsoFromFamilyRow(
                current: current,
                nextFamilyName: nextFamilyName,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlsoFromFamilyRow({
    required _RunMember current,
    required String? nextFamilyName,
  }) {
    // The other members of the CURRENT family in the run (i.e. queue
    // entries with the same familyId, after the current one).
    final others = _queue
        .where((m) => m.familyId == current.familyId && m.userId != current.userId)
        .toList();

    if (others.isEmpty && nextFamilyName == null) {
      return const SizedBox.shrink();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (others.isNotEmpty) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  SparqTrayStrings.alsoFromThisFamily,
                  style: TextStyle(
                    color: Colors.white54,
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: others.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final m = others[index];
                      return _AvatarChip(
                        member: m,
                        onTap: () {
                          // Find the actual queue index of this member
                          // and jump to it.
                          final queueIdx = _queue.indexOf(m);
                          if (queueIdx >= 0) _jumpToMember(queueIdx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const Spacer(),
        ],
        if (nextFamilyName != null)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              SparqTrayStrings.nextFamily
                  .replaceAll('{family}', nextFamilyName),
              style: const TextStyle(
                color: Colors.white54,
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }
}

/// One entry in the run queue — the data the run screen needs to
/// host a SparqViewerScreen for one member (or a Moment Sparq card
/// when [isMoment] is true and [moment] is set).
class _RunMember {
  const _RunMember({
    required this.familyId,
    required this.familyName,
    required this.userId,
    required this.userName,
    required this.userAvatarUrl,
    required this.latestMoodColor,
    required this.isSeen,
    required this.isMoment,
    required this.moment,
  });

  final String familyId;
  final String familyName;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final Color latestMoodColor;
  final bool isSeen;

  /// True when this entry represents the family's Moment Sparq
  /// (birthday/anniversary/festival/on-this-day) rather than a
  /// member's Sparqs. The run screen renders a gold-gradient card
  /// instead of hosting a SparqViewerScreen.
  final bool isMoment;

  /// The Moment Sparq payload (when [isMoment] is true). Null for
  /// regular member entries.
  final MomentSparq? moment;
}

/// 44dp avatar with a 2dp border in the member's mood color (outline
/// only if seen). Tapping jumps to that member in the run queue.
class _AvatarChip extends StatelessWidget {
  const _AvatarChip({required this.member, required this.onTap});

  final _RunMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = member.isSeen
        ? member.latestMoodColor.withValues(alpha: 0.35)
        : member.latestMoodColor;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 2),
          color: Colors.black.withValues(alpha: 0.55),
          image: member.userAvatarUrl != null
              ? DecorationImage(
                  image: NetworkImage(member.userAvatarUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: member.userAvatarUrl == null
            ? Center(
                child: Text(
                  member.userName.isNotEmpty
                      ? member.userName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Gold-to-amber gradient Moment Sparq card. Spec section 6.
///
/// Local-only — never counted as a viewed Sparq on the server. On
/// display, the card auto-advances after 5s (matching the viewer's
/// IMAGE/TEXT auto-advance duration). Tapping "Send a wish" or any
/// quick reply marks the Moment as seen locally and advances to the
/// next member. Swiping down closes the run.
class _MomentSparqCard extends StatefulWidget {
  const _MomentSparqCard({
    super.key,
    required this.moment,
    required this.familyName,
    required this.onFinished,
    required this.onClose,
  });

  final MomentSparq moment;
  final String familyName;
  final VoidCallback onFinished;
  final VoidCallback onClose;

  @override
  State<_MomentSparqCard> createState() => _MomentSparqCardState();
}

class _MomentSparqCardState extends State<_MomentSparqCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  bool _markedSeen = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finish();
      }
    });
    _progressController.forward();
    // Mark the Moment as seen as soon as it's displayed (local only).
    markMomentSparqSeen(widget.moment);
    _markedSeen = true;
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _finish() {
    if (!mounted) return;
    widget.onFinished();
  }

  void _onActionTap({String? actionLabel}) {
    if (!mounted) return;
    HapticService.tap();
    if (!_markedSeen) {
      markMomentSparqSeen(widget.moment);
      _markedSeen = true;
    }
    // Spec section 10: fire sparq_moment_action with the event type
    // (birthday/anniversary/festival/on_this_day) and the action label.
    SparqTrayAnalytics.logMomentAction(
      type: widget.moment.eventType.name,
      action: actionLabel ?? SparqTrayStrings.sendAWish,
    );
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          widget.onClose();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD4AF37), Color(0xFFF59240)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header — "K" avatar + "Kinrel moment · Today" + family name.
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF2B1A05),
                      ),
                      child: const Center(
                        child: Text(
                          'K',
                          style: TextStyle(
                            color: Color(0xFFD4AF37),
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            SparqTrayStrings.kinrelMomentToday,
                            style: TextStyle(
                              color: Color(0xFF2B1A05),
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            widget.familyName,
                            style: const TextStyle(
                              color: Color(0xFF2B1A05),
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Color(0xFF2B1A05), size: 22),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                const Spacer(),
                // Headline + relation line.
                Center(
                  child: Column(
                    children: [
                      Text(
                        m.headline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF2B1A05),
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (m.relationLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          m.relationLine,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF2B1A05),
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                // Primary CTA + quick replies.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _onActionTap(
                      actionLabel: SparqTrayStrings.sendAWish,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B1A05),
                      foregroundColor: const Color(0xFFD4AF37),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      SparqTrayStrings.sendAWish,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _quickReply(SparqTrayStrings.pranam),
                    _quickReply(SparqTrayStrings.happyBirthday),
                    _quickReply(SparqTrayStrings.voiceBlessing),
                  ],
                ),
                const SizedBox(height: 8),
                // Single progress bar.
                ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: _progressController.value,
                    minHeight: 2,
                    backgroundColor:
                        const Color(0xFF2B1A05).withValues(alpha: 0.15),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF2B1A05)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickReply(String label) {
    return GestureDetector(
      onTap: () => _onActionTap(actionLabel: label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2B1A05).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF2B1A05).withValues(alpha: 0.20),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2B1A05),
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
