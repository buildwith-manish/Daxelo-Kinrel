// lib/features/prediction_battle_v1/pb_v1_history_screen.dart
//
// History + Streaks screen for the Prediction Battle v1. Reachable via
// the "View history" link on the v1 card (added in the same commit).
//
// Layout:
//   - AppBar: "Prediction History"
//   - Streaks header: current + best streak as two stat tiles, with
//     flame icons and gold/orange color coding.
//   - Quick stats row: "Wins: 12 of 30 · Participated: 27 of 30"
//   - Past rounds list: each round is a card with the question, the
//     correct answer, the user's guess (or "missed"), the winner
//     badges, and the reveal-at timestamp. Sorted by revealAt DESC.
//
// Like the reveal screen, this screen does NOT hold a realtime WS
// subscription — past rounds don't change. The user can pull-to-
// refresh to pick up a freshly-revealed round.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/utils/app_time.dart';
import 'pb_v1_history_models.dart';
import 'pb_v1_history_provider.dart';

class PBv1HistoryScreen extends ConsumerStatefulWidget {
  const PBv1HistoryScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PBv1HistoryScreen> createState() => _PBv1HistoryScreenState();
}

class _PBv1HistoryScreenState extends ConsumerState<PBv1HistoryScreen> {
  // Reusable userId → display name map. Filled once on screen open
  // from FamilyMember joined with User. Same pattern as the reveal
  // screen.
  Map<String, String> _userNames = const {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(pbV1HistoryProvider(widget.familyId).notifier).load();
      _loadUserNames();
    });
  }

  Future<void> _loadUserNames() async {
    // Same lookup as the reveal screen. We accept a duplicate of
    // this code rather than extracting it to a shared helper —
    // doing so would require a new shared widget provider, which is
    // a bigger refactor than the value it adds right now. If a
    // third caller needs the same lookup, we'll extract then.
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final rows = await client
          .from('FamilyMember')
          .select('userId, user:User(name)')
          .eq('familyId', widget.familyId);
      if (!mounted) return;
      final map = <String, String>{};
      for (final r in (rows as List)) {
        final row = r as Map<String, dynamic>;
        final uid = (row['userId'] ?? '') as String;
        if (uid.isEmpty) continue;
        final user = row['user'];
        String name = uid.substring(0, 8);
        if (user is Map && user['name'] is String && (user['name'] as String).isNotEmpty) {
          name = user['name'] as String;
        }
        map[uid] = name;
      }
      setState(() => _userNames = map);
    } catch (e) {
      // Best-effort — keep the UUID prefix fallback.
      debugPrint('[PBv1History] _loadUserNames: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pbV1HistoryProvider(widget.familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        title: const Text('Prediction History', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(pbV1HistoryProvider(widget.familyId).notifier).refresh(),
          ),
        ],
      ),
      body: state.isLoading && state.history == null
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : state.history == null
              ? _EmptyState(error: state.error)
              : _HistoryBody(history: state.history!, userNames: _userNames, familyId: widget.familyId),
    );
  }
}

// ── Empty / error state ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load history: $error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: KinrelColors.textDim, fontFamily: KinrelTypography.bodyFont),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            const Text(
              'No rounds revealed yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Once your family reveals its first prediction, the round will show up here along with your win streak.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main body ────────────────────────────────────────────────────────

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.history, required this.userNames, required this.familyId});
  final PBv1History history;
  final Map<String, String> userNames;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StreaksHeader(streak: history.streak),
        const SizedBox(height: 12),
        _QuickStatsRow(history: history),
        const SizedBox(height: 20),
        Text(
          'Recent rounds',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 8),
        if (history.rounds.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'No revealed rounds yet.',
              style: TextStyle(color: KinrelColors.textDim, fontFamily: KinrelTypography.bodyFont),
            ),
          )
        else
          for (final round in history.rounds)
            _HistoryRoundCard(
              round: round,
              userNames: userNames,
              familyId: familyId,
            ),
      ],
    );
  }
}

// ── Streaks header ───────────────────────────────────────────────────

class _StreaksHeader extends StatelessWidget {
  const _StreaksHeader({required this.streak});
  final PBv1Streak streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StreakTile(
            label: 'Current streak',
            value: streak.currentStreak,
            icon: streak.currentStreak >= 3 ? '🔥' : '·',
            color: streak.currentStreak >= 3 ? KinrelColors.brightGold : KinrelColors.orange,
            subtitle: streak.currentStreak == 1 ? 'win' : 'wins',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StreakTile(
            label: 'Best streak',
            value: streak.bestStreak,
            icon: '🏆',
            color: KinrelColors.amber,
            subtitle: streak.bestStreak == 1 ? 'win' : 'wins',
          ),
        ),
      ],
    );
  }
}

class _StreakTile extends StatelessWidget {
  const _StreakTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });
  final String label;
  final int value;
  final String icon;
  final Color color;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
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

// ── Quick stats ──────────────────────────────────────────────────────

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.history});
  final PBv1History history;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Wins: ${history.winsCount} of ${history.participatedCount} participated · ${history.totalRounds} rounds shown',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ── Per-round card ───────────────────────────────────────────────────

class _HistoryRoundCard extends StatelessWidget {
  const _HistoryRoundCard({
    required this.round,
    required this.userNames,
    required this.familyId,
  });
  final PBv1HistoryRound round;
  final Map<String, String> userNames;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final istReveal = AppTime.toLocalDisplay(round.revealAt);
    final dateStr = _formatDate(istReveal);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: round.won
            ? KinrelColors.brightGold.withValues(alpha: 0.06)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: round.won
              ? KinrelColors.brightGold.withValues(alpha: 0.3)
              : KinrelColors.border,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: date + outcome pill
          Row(
            children: [
              Text(
                dateStr,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textDim,
                ),
              ),
              const Spacer(),
              _OutcomePill(round: round),
            ],
          ),
          const SizedBox(height: 8),
          // Question text
          Text(
            round.questionText,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          // Correct answer
          Text(
            'Answer: ${_formatAnswer(round.correctAnswer)} ${round.unitLabel}',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: KinrelColors.brightGold,
            ),
          ),
          const SizedBox(height: 8),
          // My guess row
          if (round.myGuess == null)
            Row(
              children: [
                const Icon(Icons.visibility_off, size: 14, color: KinrelColors.textDim),
                const SizedBox(width: 6),
                Text(
                  'You missed this round',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  round.won ? Icons.emoji_events : Icons.gps_fixed,
                  size: 14,
                  color: round.won ? KinrelColors.brightGold : KinrelColors.textSilver,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    round.won
                        ? 'You won! 🎯 Guessed ${_formatAnswer(round.myGuess!.guessValue)}'
                        : 'You guessed ${_formatAnswer(round.myGuess!.guessValue)} — off by ${_formatDistance(round.myGuess!.distance, round.correctAnswer)}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: round.won ? KinrelColors.brightGold : KinrelColors.textSilver,
                    ),
                  ),
                ),
              ],
            ),
          // Winner names (if more than one)
          if (round.winnerUserIds.length > 1) ...[
            const SizedBox(height: 6),
            Text(
              'Tied winners: ${_formatWinnerNames(round.winnerUserIds)}',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime ist) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[ist.month - 1]} ${ist.day}, ${ist.year}';
  }

  String _formatAnswer(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  String _formatDistance(double distance, double correctAnswer) {
    if (correctAnswer > 1000) {
      return '${distance.toStringAsFixed(1)}%';
    }
    if (distance == distance.roundToDouble()) return distance.toInt().toString();
    return distance.toStringAsFixed(1);
  }

  String _formatWinnerNames(List<String> ids) {
    final names = ids.map((id) => userNames[id] ?? id.substring(0, 8)).toList();
    return names.join(', ');
  }
}

class _OutcomePill extends StatelessWidget {
  const _OutcomePill({required this.round});
  final PBv1HistoryRound round;

  @override
  Widget build(BuildContext context) {
    final (label, color) = round.myGuess == null
        ? ('MISSED', KinrelColors.textDim)
        : round.won
            ? ('WON', KinrelColors.brightGold)
            : ('PLAYED', KinrelColors.orange);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}
