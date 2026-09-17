// lib/features/gaming_ecosystem/presentation/gaming_activity_feed_screen.dart
//
// Family Activity Feed — the gaming heartbeat of the family:
// game starts, victories, badges, challenge completions, milestones,
// sportsmanship cheers and Family Cup wins, in one warm timeline.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/gaming_providers.dart';
import 'widgets/gaming_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

class GamingActivityFeedScreen extends ConsumerWidget {
  const GamingActivityFeedScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync =
        ref.watch(gamingActivityProvider(ActivityKey(familyId: familyId)));

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
      body: activityAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load the activity feed',
            message: 'Pull down to try again.',
          ),
        ),
        data: (entries) => RefreshIndicator(
          color: KinrelColors.orange,
          backgroundColor: KinrelColors.darkCard,
          onRefresh: () async {
            ref.invalidate(
                gamingActivityProvider(ActivityKey(familyId: familyId)));
            await ref.read(
                gamingActivityProvider(ActivityKey(familyId: familyId)).future);
          },
          child: entries.isEmpty
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
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final a = entries[i];
                    return GamingActivityTile(
                      icon: a.icon,
                      description: a.description,
                      timeLabel: gamingTimeAgo(a.createdAt),
                      accent: _accentFor(a.action),
                    )
                        .animate()
                        .fadeIn(delay: (25 * i).ms, duration: 250.ms);
                  },
                ),
        ),
      ),
    );
  }

  Color _accentFor(String action) {
    switch (action) {
      case 'game_badge_earned':
        return KinrelColors.brightGold;
      case 'game_challenge_completed':
        return const Color(0xFF8B5CF6);
      case 'game_milestone_reached':
        return KinrelColors.gold;
      case 'game_cup_won':
        return KinrelColors.brightGold;
      case 'game_sportsmanship':
        return KinrelColors.success;
      default:
        return KinrelColors.orange;
    }
  }
}
