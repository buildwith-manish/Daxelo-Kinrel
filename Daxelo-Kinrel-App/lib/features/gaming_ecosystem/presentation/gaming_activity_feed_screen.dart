// lib/features/gaming_ecosystem/presentation/gaming_activity_feed_screen.dart
//
// Family Activity Feed — the gaming heartbeat of the family:
// game starts, victories, badges, challenge completions, milestones,
// sportsmanship cheers and Family Cup wins, in one warm timeline.
//
// REFACTOR: now uses the same FamilyMomentCard widget as the home preview,
// wrapped in MomentDateGroupWidget so entries are grouped by date with
// "Today" / "Yesterday" / "Sep 15" headers — no more per-row "1d ago"
// repetition. Reactions (❤️ 👏) are available on every entry here too,
// matching the home preview exactly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../games/presentation/widgets/family_moment_card.dart';
import 'widgets/gaming_kit.dart';

class GamingActivityFeedScreen extends ConsumerWidget {
  const GamingActivityFeedScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the v2 activity provider (with reaction counts) — same provider
    // the home preview uses, so the card style + reactions are identical
    // everywhere.
    final momentsAsync = ref.watch(familyMomentsProvider(familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('Family Moments',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: momentsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load the activity feed',
            message: 'Pull down to try again.',
          ),
        ),
        data: (moments) {
          // v114 — Step 4 perf: precompute the date-grouped list once
          // per build, then use ListView.builder so date-group widgets
          // are built lazily as they scroll into view.
          final groups = groupMomentsByDate(moments);
          return RefreshIndicator(
            color: KinrelColors.orange,
            backgroundColor: KinrelColors.darkCard,
            onRefresh: () async {
              ref.invalidate(familyMomentsProvider(familyId));
              await ref.read(familyMomentsProvider(familyId).future);
            },
            child: moments.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    GamingEmptyCard(
                      emoji: '✨',
                      title: 'No family moments yet',
                      message:
                          'Wins, badges, milestones and cheers from your family\'s '
                          'games will appear here.',
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    itemCount: groups.length,
                    itemBuilder: (context, index) => MomentDateGroupWidget(
                      group: groups[index],
                      familyId: familyId,
                    ),
                  ),
          );
        },
      ),
    );
  }
}
