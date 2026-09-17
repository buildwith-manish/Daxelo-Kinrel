// lib/features/gaming_ecosystem/presentation/gaming_player_profile_screen.dart
//
// Player Gaming Profile — favorite game, win rate, total matches, badges,
// per-game stats, recent activity, level progression, days-active tracker,
// rank and sportsmanship. A recognition page for every family gamer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/game_registry.dart';
import '../data/gaming_models.dart';
import '../data/gaming_providers.dart';
import '../../games/shared/icons/kinrel_icons.dart';
import 'widgets/gaming_kit.dart';

class GamingPlayerProfileScreen extends ConsumerWidget {
  const GamingPlayerProfileScreen({
    super.key,
    required this.familyId,
    required this.userId,
  });

  final String familyId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(
        gamingPlayerProfileProvider(PlayerProfileKey(familyId: familyId, userId: userId)));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('Player Profile',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load this profile',
            message: 'Pull down to try again.',
          ),
        ),
        data: (p) => RefreshIndicator(
          color: KinrelColors.orange,
          backgroundColor: KinrelColors.darkCard,
          onRefresh: () async {
            ref.invalidate(gamingPlayerProfileProvider(
                PlayerProfileKey(familyId: familyId, userId: userId)));
            await ref.read(gamingPlayerProfileProvider(
                    PlayerProfileKey(familyId: familyId, userId: userId))
                .future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _ProfileHero(profile: p),
              const SizedBox(height: 16),
              _StatGrid(profile: p),
              const SizedBox(height: 16),
              if (p.favoriteGame != null) ...[
                _FavoriteGameCard(favorite: p.favoriteGame!, familyId: familyId),
                const SizedBox(height: 16),
              ],
              if (p.perGame.isNotEmpty) ...[
                GamingSectionHeader(
                  title: 'Game by Game',
                  subtitle: 'Where their hours of joy went',
                  icon: Icons.insights_outlined,
                ),
                _PerGameList(profile: p, familyId: familyId),
                const SizedBox(height: 16),
              ],
              if (p.badges.isNotEmpty) ...[
                GamingSectionHeader(
                  title: 'Badges · ${p.badges.length}',
                  actionLabel: 'View all',
                  onAction: () =>
                      context.push('/family/$familyId/gaming/achievements'),
                  icon: Icons.emoji_events_outlined,
                ),
                SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: p.badges.take(10).length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => SizedBox(
                      width: 82,
                      child: GamingBadgeChip(
                        icon: p.badges[i].icon,
                        name: p.badges[i].name,
                        tier: p.badges[i].tier,
                        earned: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (p.recentMatches.isNotEmpty) ...[
                GamingSectionHeader(
                  title: 'Recent Matches',
                  icon: Icons.history,
                ),
                ...p.recentMatches.take(5).map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text(m.gameIcon,
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              m.gameName,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                          ),
                          Text(
                            m.result.toUpperCase(),
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: m.result == 'win'
                                  ? KinrelColors.success
                                  : KinrelColors.textDim,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            gamingTimeAgo(m.finishedAt),
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 10,
                              color: KinrelColors.textDim,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});
  final PlayerGamingProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF241610), Color(0xFF151219)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(profile: profile, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    if (profile.username != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${profile.username}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          color: KinrelColors.amber,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (profile.rank > 0)
                          _HeroChip(
                              emoji: '🥇', label: 'Family rank #${profile.rank}'),
                        const SizedBox(width: 6),
                        if (profile.streakCurrent > 0)
                          _HeroChip(
                              emoji: '🔥',
                              label: '${profile.streakCurrent} streak'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Level progression
          Row(
            children: [
              Text(
                'LVL ${profile.level}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.brightGold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GamingProgressBar(
                  progress: profile.pointsIntoLevel / 100,
                  height: 7,
                  color: KinrelColors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${100 - profile.pointsIntoLevel} to L${profile.level + 1}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.emoji, required this.label});
  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KinrelIcon(
            kinrelIconFromEmoji(emoji) ?? KinrelIconData.sparkle,
            size: 11,
            color: KinrelColors.amber,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, required this.size});
  final PlayerGamingProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = profile.avatarUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: KinrelGradients.achievementGradient,
      ),
      padding: const EdgeInsets.all(2.5),
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: KinrelColors.darkElevated,
        foregroundImage:
            url != null && url.isNotEmpty ? NetworkImage(url) : null,
        child: Text(
          profile.userName.isEmpty
              ? '?'
              : profile.userName.substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: size * 0.34,
            fontWeight: FontWeight.w800,
            color: KinrelColors.orange,
          ),
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.profile});
  final PlayerGamingProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GamingStatChip(
              emoji: '🎮', value: '${profile.matches}', label: 'MATCHES'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GamingStatChip(
              emoji: '🏆',
              value: '${profile.wins}',
              label: 'WINS · ${profile.winRateLabel}'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GamingStatChip(
              emoji: '🏅',
              value: '${profile.badges.length}',
              label: 'BADGES'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GamingStatChip(
              emoji: '💚',
              value: '${profile.sportsmanship}',
              label: 'CHEERS'),
        ),
      ],
    );
  }
}

class _FavoriteGameCard extends StatelessWidget {
  const _FavoriteGameCard({required this.favorite, required this.familyId});
  final GameStat favorite;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final game = gameByTable(favorite.gameTable);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: game != null
              ? Color(game.accent).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Text(favorite.icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FAVORITE GAME',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: KinrelColors.amber,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  favorite.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                Text(
                  '${favorite.matches} matches · ${favorite.wins} wins',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          if (game != null)
            GestureDetector(
              onTap: () => context.push(gameRoute(game, familyId)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: KinrelGradients.ignite,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Play',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PerGameList extends StatelessWidget {
  const _PerGameList({required this.profile, required this.familyId});
  final PlayerGamingProfile profile;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final g in profile.perGame.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(g.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                        const SizedBox(height: 3),
                        GamingProgressBar(
                          progress: g.matches == 0
                              ? 0
                              : (g.wins / g.matches).clamp(0.0, 1.0),
                          height: 5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${g.wins}W / ${g.matches}M',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
