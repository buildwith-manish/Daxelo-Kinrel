// lib/features/games/redlight/redlight_results_screen.dart
//
// Freeze & Dash — Results screen.
// Route: /family/$familyId/freeze-dash/results/$roundId

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import 'redlight_models.dart';
import 'redlight_provider.dart';

class RedlightResultsScreen extends ConsumerWidget {
  const RedlightResultsScreen({
    super.key,
    required this.familyId,
    required this.roundId,
  });
  final String familyId;
  final String roundId;

  Future<List<RedlightResult>> _fetchResults(WidgetRef ref) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];
    try {
      final resp = await client
          .from('redlight_results')
          .select()
          .eq('roundId', roundId)
          .order('placement', ascending: true);
      return resp
          .map((r) => RedlightResult.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(redlightProvider(familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Use socket-pushed placements if available; otherwise fetch from DB.
    final liveResults = state.results;
    final isWinner = state.round?.winnerUserId == myId;

    return FutureBuilder<List<RedlightResult>>(
      future: liveResults.isEmpty ? _fetchResults(ref) : Future.value([]),
      builder: (context, snapshot) {
        final hasLive = liveResults.isNotEmpty;
        final dbResults = snapshot.data ?? [];

        final entries = <_ResultRow>[];
        if (hasLive) {
          for (final e in liveResults) {
            entries.add(_ResultRow(
              userName: e.userName,
              userId: e.userId,
              progress: e.progress,
              placement: state.results.indexOf(e) + 1,
            ));
          }
        } else {
          for (final r in dbResults) {
            entries.add(_ResultRow(
              userName: r.userName,
              userId: r.userId,
              progress: r.finalProgress,
              placement: r.placement,
            ));
          }
        }
        entries.sort((a, b) => a.placement.compareTo(b.placement));

        final winner = entries.isEmpty ? null : entries.first;

        final isWinnerView = isWinner ||
            (winner != null && winner.userId == myId);

        return DKScaffold(
          gradient: isWinnerView ? KinrelGradients.deepFireGradient : null,
          backgroundColor:
              isWinnerView ? null : KinrelColors.darkSurface,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              'Results',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: KinrelColors.textWhite,
            elevation: 0,
          ),
          body: entries.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                    color: KinrelColors.orange,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(KinrelSpacing.base),
                  children: [
                    const SizedBox(height: KinrelSpacing.lg),
                    if (winner != null)
                      _winnerCard(winner, isWinnerView)
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .scale(
                            begin: const Offset(0.92, 0.92),
                            end: const Offset(1.0, 1.0),
                            duration: 400.ms,
                            curve: Curves.easeOutBack,
                          ),
                    const SizedBox(height: KinrelSpacing.xl),
                    Text(
                      'Final Standings',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textDim,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: KinrelSpacing.sm),
                    for (int i = 0; i < entries.length; i++)
                      _placementRow(entries[i], entries[i].userId == myId)
                          .animate(delay: (i * 80).ms)
                          .fadeIn(duration: 250.ms)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: 250.ms,
                          ),
                    const SizedBox(height: KinrelSpacing.xxl),
                    DKButton(
                      label: 'Play Again',
                      variant: DKButtonVariant.gradient,
                      fullWidth: true,
                      icon: Icons.refresh_rounded,
                      onPressed: () {
                        // Re-create a round with the same settings — return to lobby.
                        ref
                            .read(redlightProvider(familyId).notifier)
                            .leaveRound();
                        if (context.mounted) {
                          context.pushReplacement(
                            '/family/$familyId/freeze-dash/lobby',
                          );
                        }
                      },
                    ),
                    const SizedBox(height: KinrelSpacing.sm),
                    DKButton(
                      label: 'Back to Hub',
                      variant: DKButtonVariant.secondary,
                      fullWidth: true,
                      onPressed: () {
                        ref
                            .read(redlightProvider(familyId).notifier)
                            .leaveRound();
                        if (context.mounted) {
                          context.go('/games?familyId=$familyId');
                        }
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _winnerCard(_ResultRow winner, bool isMe) {
    return Column(
      children: [
        const Text('🏆', style: TextStyle(fontSize: 64))
            .animate(onPlay: (c) => c.forward())
            .fadeIn(duration: 500.ms)
            .scale(
              begin: const Offset(0.5, 0.5),
              end: const Offset(1.0, 1.0),
              duration: 500.ms,
              curve: Curves.elasticOut,
            ),
        const SizedBox(height: KinrelSpacing.sm),
        Text(
          'Winner!',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isMe ? '${winner.userName} (You)' : winner.userName,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: KinrelColors.orange,
          ),
        ),
      ],
    );
  }

  Widget _placementRow(_ResultRow row, bool isMe) {
    final medal = row.placement == 1
        ? '🥇'
        : row.placement == 2
        ? '🥈'
        : row.placement == 3
        ? '🥉'
        : '${row.placement}';
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isMe ? KinrelColors.orange : KinrelColors.border,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              medal,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          Expanded(
            child: Text(
              isMe ? '${row.userName} (You)' : row.userName,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          Text(
            '${row.progress.toStringAsFixed(0)}%',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow {
  const _ResultRow({
    required this.userName,
    required this.userId,
    required this.progress,
    required this.placement,
  });
  final String userName;
  final String userId;
  final double progress;
  final int placement;
}
