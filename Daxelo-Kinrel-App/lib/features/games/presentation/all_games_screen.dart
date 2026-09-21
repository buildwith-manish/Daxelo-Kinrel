// lib/features/games/presentation/all_games_screen.dart
//
// AllGamesScreen — the secondary destination for the categorised game grid.
//
// In the 3-zone restructure, the home screen now leads with people (Play
// With row) instead of a flat game-icon grid. The full category-based
// grid (Quick Duels, Party Night, Board Classics, Indian Classics) lives
// here, reached via a "Browse all games →" link from the home surface.
//
// The categorisation IA is preserved (it's good IA) — this screen just
// moves it off the home surface so the home can lead with emotion + people.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/data/game_registry.dart';
import '../../gaming_ecosystem/data/gaming_providers.dart';
import '../services/game_asset_manager.dart';
import '../shared/icons/game_icons.dart';
import '../shared/icons/kinrel_icons.dart';

class AllGamesScreen extends ConsumerStatefulWidget {
  const AllGamesScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<AllGamesScreen> createState() => _AllGamesScreenState();
}

class _AllGamesScreenState extends ConsumerState<AllGamesScreen> {
  final Set<GameCategory> _expandedCategories = {
    GameCategory.quickDuels,
    GameCategory.partyNight,
    GameCategory.boardClassics,
    GameCategory.indianClassics,
  };

  void _toggleCategory(GameCategory category) {
    setState(() {
      if (_expandedCategories.contains(category)) {
        _expandedCategories.remove(category);
      } else {
        _expandedCategories.add(category);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Kick off download-status checks for every game (once per visit).
    for (final g in kGameCatalog) {
      Future.microtask(() =>
          ref.read(gameDownloadStatusProvider(g.gameId).notifier).checkStatus());
    }

    final dashAsync = ref.watch(gamingDashboardProvider(widget.familyId));
    final exploredCount = dashAsync.asData?.value.familyDistinctGames ?? 0;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('All Games',
            style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base, KinrelSpacing.base, KinrelSpacing.base, 120),
        children: [
          // Catalog summary header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                const KinrelIcon(KinrelIconData.controller,
                    size: 22, color: KinrelColors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${kGameCatalog.length} games · $exploredCount explored together',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 250.ms)
              .slideY(begin: -0.02, end: 0, duration: 250.ms),
          const SizedBox(height: 14),
          for (final category in GameCategory.values)
            _CategorySection(
              familyId: widget.familyId,
              category: category,
              expanded: _expandedCategories.contains(category),
              onToggle: () => _toggleCategory(category),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Category section — extracted from games_hub_screen (the original
// _CategorySection + _GameGridCard). Behaviour is identical, just moved
// here so the home surface no longer renders the grid inline.
// ─────────────────────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.familyId,
    required this.category,
    required this.expanded,
    required this.onToggle,
  });

  final String familyId;
  final GameCategory category;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final games = gamesByCategory(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                KinrelIcon(
                  kinrelIconFromEmoji(category.emoji) ?? KinrelIconData.sparkle,
                  size: 16,
                  color: KinrelColors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.label,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      Text(
                        category.tagline,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: KinrelColors.textDim,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: games.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.94,
              ),
              itemBuilder: (context, i) => _GameGridCard(
                game: games[i],
                familyId: familyId,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GameGridCard extends ConsumerWidget {
  const _GameGridCard({required this.game, required this.familyId});
  final GameCatalogEntry game;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlState = ref.watch(gameDownloadStatusProvider(game.gameId));
    final accent = Color(game.accent);
    final isDownloaded = dlState.status == GameDownloadStatus.downloaded;

    return GestureDetector(
      onTap: () {
        switch (dlState.status) {
          case GameDownloadStatus.downloaded:
            context.push(gameRoute(game, familyId));
            break;
          case GameDownloadStatus.notDownloaded:
          case GameDownloadStatus.failed:
            ref
                .read(gameDownloadStatusProvider(game.gameId).notifier)
                .download();
            break;
          default:
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: isDownloaded ? 0.14 : 0.05),
              KinrelColors.darkCard,
              KinrelColors.darkCard,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDownloaded
                ? accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
            width: isDownloaded ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accent.withValues(alpha: 0.10),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: GameIcon(gameId: game.gameId, size: 38),
                    ),
                  ),
                ),
                const Spacer(),
                if (dlState.status == GameDownloadStatus.downloading)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      value: dlState.progress > 0 ? dlState.progress : null,
                      color: KinrelColors.orange,
                    ),
                  )
                else if (isDownloaded)
                  const KinrelIcon(KinrelIconData.checkCircle,
                      size: 14, color: KinrelColors.success),
              ],
            ),
            const Spacer(),
            Text(
              game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              game.playersLabel,
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: 0.02, end: 0, duration: 200.ms);
  }
}
