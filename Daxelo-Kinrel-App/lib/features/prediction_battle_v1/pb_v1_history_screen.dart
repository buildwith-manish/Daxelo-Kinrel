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
import 'pb_v1_submit_question_sheet.dart';

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
  // The current user's id — fetched at the same time as user names.
  // Used by the leaderboard section to highlight the requesting user's
  // row. May be null briefly during load (before the supabase client
  // resolves); the leaderboard will render without a highlight until
  // it's populated.
  String? _currentUserId;

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
      // Capture the current user's id for the leaderboard highlight.
      _currentUserId = client.auth.currentUser?.id;
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
          // Phase 3.9 — "Suggest a question" button. Opens the
          // submit-question bottom sheet. Lets users add their own
          // questions to the rotation (admin-moderated before going
          // live; 5-coin reward when approved + used).
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Suggest a question',
            onPressed: () => PBv1SubmitQuestionSheet.show(context, ref, widget.familyId),
          ),
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
        // Phase 3.4 — Family leaderboard section. Sits above the
        // recent rounds list so the social comparison is the first
        // thing the user sees after their own streak stats. Hidden
        // if no family member has ever won (the leaderboard comes
        // from pb_v1_win_streaks which is populated on first win).
        if (history.leaderboard.isNotEmpty) ...[
          _FamilyLeaderboardSection(
            leaderboard: history.leaderboard,
            userNames: userNames,
            currentUserId: _currentUserId,
          ),
          const SizedBox(height: 20),
        ],
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

// ── Phase 3.4 — Family leaderboard section ────────────────────────────
//
// Ranks all family members by current streak (live) → best streak
// (historical) → user_id (stable tiebreaker). The requesting user's
// row is highlighted with a gold background tint so they can spot
// themselves in the list.
//
// Layout:
//   - Section header: "Family Leaderboard"
//   - Top 3 entries get medal icons (🥇🥈🥉) + their current streak
//     in a larger font, in a stacked card row.
//   - The remaining entries (rank 4+) render as a flat list below
//     the top 3. If there are ≤3 entries, the flat list is empty.
//
// Empty state: handled by the parent (the section is hidden entirely
// if the leaderboard is empty).

class _FamilyLeaderboardSection extends StatelessWidget {
  const _FamilyLeaderboardSection({
    required this.leaderboard,
    required this.userNames,
    required this.currentUserId,
  });

  final List<PBv1LeaderboardEntry> leaderboard;
  final Map<String, String> userNames;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    // Defensive: the parent only renders this section if
    // leaderboard.isNotEmpty, but guard anyway in case of stale
    // rebuilds.
    if (leaderboard.isEmpty) return const SizedBox.shrink();

    final top3 = leaderboard.take(3).toList();
    final rest = leaderboard.skip(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Family Leaderboard',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 8),
        // Top 3 podium
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < top3.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _PodiumTile(
                  entry: top3[i],
                  rank: i + 1,
                  userNames: userNames,
                  isMe: top3[i].userId == currentUserId,
                ),
              ),
            ],
          ],
        ),
        // Remaining entries (rank 4+)
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < rest.length; i++)
            _LeaderboardRow(
              entry: rest[i],
              rank: i + 4,
              userNames: userNames,
              isMe: rest[i].userId == currentUserId,
            ),
        ],
        // Phase 3.22 (item 12) — "You vs. the leader" gap line.
        // Gamifies the catch-up. Shows the gap between the user's
        // current streak and the leader's, so the user knows exactly
        // how many wins they need to overtake. Hidden if:
        //   - The user is not in the leaderboard (never won a round)
        //   - The user IS the leader (no gap to show)
        if (currentUserId != null && leaderboard.isNotEmpty) ...[
          const SizedBox(height: 8),
          _LeaderboardGapLine(
            leaderboard: leaderboard,
            userNames: userNames,
            currentUserId: currentUserId!,
          ),
        ],
      ],
    );
  }
}

/// Phase 3.22 (item 12) — "You vs. the leader" gap line.
/// Shows: "You're 2 wins behind [LeaderName] — win today to catch up!"
/// or hidden if the user is the leader or not in the leaderboard.
class _LeaderboardGapLine extends StatelessWidget {
  const _LeaderboardGapLine({
    required this.leaderboard,
    required this.userNames,
    required this.currentUserId,
  });

  final List<PBv1LeaderboardEntry> leaderboard;
  final Map<String, String> userNames;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final leader = leaderboard.first;
    final myEntry = leaderboard.where((e) => e.userId == currentUserId).firstOrNull;

    // User is not in the leaderboard (never won a round) — show
    // a different copy: "Win your first round to join the leaderboard!"
    if (myEntry == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KinrelColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.emoji_events_outlined, size: 14, color: KinrelColors.brightGold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Win your first round to join the leaderboard!',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textSilver,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // User IS the leader — show a celebratory line.
    if (myEntry.userId == leader.userId) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KinrelColors.brightGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KinrelColors.brightGold.withValues(alpha: 0.25), width: 0.5),
        ),
        child: Row(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              'You lead with a ${myEntry.currentStreak}-day streak!',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KinrelColors.brightGold,
              ),
            ),
          ],
        ),
      );
    }

    // User is behind the leader — show the gap.
    final gap = leader.currentStreak - myEntry.currentStreak;
    final leaderName = userNames[leader.userId] ?? leader.userId.substring(0, 8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.20), width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, size: 14, color: KinrelColors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              gap > 0
                  ? "You're $gap win${gap == 1 ? '' : 's'} behind $leaderName — win today to catch up!"
                  : "You're tied with $leaderName at ${myEntry.currentStreak} wins!",
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumTile extends StatelessWidget {
  const _PodiumTile({
    required this.entry,
    required this.rank,
    required this.userNames,
    required this.isMe,
  });

  final PBv1LeaderboardEntry entry;
  final int rank;
  final Map<String, String> userNames;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    const medals = ['🥇', '🥈', '🥉'];
    final medal = medals[rank - 1];
    final name = userNames[entry.userId] ?? entry.userId.substring(0, 8);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe
            ? KinrelColors.brightGold.withValues(alpha: 0.10)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe
              ? KinrelColors.brightGold.withValues(alpha: 0.40)
              : KinrelColors.border,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(medal, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isMe ? KinrelColors.textWhite : KinrelColors.textSilver,
                  ),
                ),
              ),
              if (isMe)
                Text(
                  'YOU',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: KinrelColors.brightGold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${entry.currentStreak}',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: entry.currentStreak > 0
                  ? KinrelColors.brightGold
                  : KinrelColors.textDim,
            ),
          ),
          Text(
            'current · best ${entry.bestStreak}',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.entry,
    required this.rank,
    required this.userNames,
    required this.isMe,
  });

  final PBv1LeaderboardEntry entry;
  final int rank;
  final Map<String, String> userNames;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final name = userNames[entry.userId] ?? entry.userId.substring(0, 8);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? KinrelColors.brightGold.withValues(alpha: 0.06)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe
              ? KinrelColors.brightGold.withValues(alpha: 0.30)
              : KinrelColors.border,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                color: isMe ? KinrelColors.textWhite : KinrelColors.textSilver,
              ),
            ),
          ),
          // Window stats — wins / participated
          Text(
            '${entry.totalWinsInWindow}/${entry.totalGuessesInWindow} in window',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(width: 8),
          // Current streak — the main ranking key
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (entry.currentStreak >= 3)
                const Text('🔥', style: TextStyle(fontSize: 11)),
              if (entry.currentStreak >= 3) const SizedBox(width: 2),
              Text(
                '${entry.currentStreak}',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: entry.currentStreak > 0
                      ? KinrelColors.brightGold
                      : KinrelColors.textDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
