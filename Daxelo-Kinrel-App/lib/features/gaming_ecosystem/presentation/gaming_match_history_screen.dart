// lib/features/gaming_ecosystem/presentation/gaming_match_history_screen.dart
//
// Match History — every completed game with result, opponents, timestamps,
// durations and statistics. Tapping a match opponent opens their gaming
// profile (recognition + connection loop).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/gaming_models.dart';
import '../data/gaming_providers.dart';
import 'widgets/gaming_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

class GamingMatchHistoryScreen extends ConsumerWidget {
  const GamingMatchHistoryScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(gamingMatchHistoryProvider(MatchHistoryKey(familyId: familyId)));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('Match History',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: historyAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load your match history',
            message: 'Pull down to try again.',
          ),
        ),
        data: (matches) => RefreshIndicator(
          color: KinrelColors.orange,
          backgroundColor: KinrelColors.darkCard,
          onRefresh: () async {
            ref.invalidate(gamingMatchHistoryProvider(
                MatchHistoryKey(familyId: familyId)));
            await ref.read(gamingMatchHistoryProvider(
                    MatchHistoryKey(familyId: familyId)).future);
          },
          child: matches.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  GamingEmptyCard(
                    emoji: '📜',
                    title: 'No matches yet',
                    message:
                        'Your family\'s gaming story starts with the first game. '
                        'Every match — win, draw or just-for-fun — lands here.',
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  itemCount: matches.length,
                  itemBuilder: (context, i) =>
                      _MatchHistoryTile(match: matches[i], familyId: familyId),
                ),
        ),
      ),
    );
  }
}

class _MatchHistoryTile extends StatelessWidget {
  const _MatchHistoryTile({required this.match, required this.familyId});
  final MatchHistoryEntry match;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final resultColor = _resultColor(match.result);
    final resultLabel = _resultLabel(match.result);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: match.isWin
              ? KinrelColors.success.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          // Game icon
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: resultColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(match.gameIcon, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.gameName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: resultColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: resultColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        resultLabel,
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: resultColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _opponentsLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _metaLine(),
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.02, end: 0, duration: 250.ms);
  }

  Color _resultColor(String result) {
    switch (result) {
      case 'win':
        return KinrelColors.success;
      case 'loss':
        return KinrelColors.error;
      case 'draw':
        return KinrelColors.warning;
      default:
        return KinrelColors.orange; // played
    }
  }

  String _resultLabel(String result) {
    switch (result) {
      case 'win':
        return 'WIN';
      case 'loss':
        return 'LOSS';
      case 'draw':
        return 'DRAW';
      default:
        return 'PLAYED';
    }
  }

  String _opponentsLabel() {
    if (match.opponents.isEmpty) return 'Solo / family session';
    final names = match.opponents.map((o) => o.userName).take(3).join(', ');
    final extra =
        match.opponents.length > 3 ? ' +${match.opponents.length - 3}' : '';
    return 'vs $names$extra';
  }

  String _metaLine() {
    final parts = <String>[
      gamingTimeAgo(match.finishedAt),
      if (match.durationLabel.isNotEmpty) match.durationLabel,
      '${match.playerCount} players',
    ];
    return parts.join(' · ');
  }
}
