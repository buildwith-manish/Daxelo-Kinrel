// lib/features/prediction_battle/prediction_battle_screen.dart
//
// Prediction Battle Details Screen — 5 sections:
// 1. Active Prediction (submit form)
// 2. Pending Predictions (waiting for reveal)
// 3. Recent Results (last 20 resolved)
// 4. Prediction Leaderboard
// 5. Personal Statistics

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
// Step 3 — shared timezone-aware time utility. The battle screen shows
// SHARED countdowns (closes in Xh Ym, reveals in Xh Ym) which must use
// `AppTime.nowServerAccurate()` instead of `DateTime.now()` so cheap
// Android devices with drifting clocks show the correct countdown.
import '../../../core/utils/app_time.dart';
import '../../../shared/widgets/dk_components.dart';
import '../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import 'prediction_models.dart';
import 'prediction_provider.dart';

class PredictionBattleScreen extends ConsumerStatefulWidget {
  const PredictionBattleScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PredictionBattleScreen> createState() => _PredictionBattleScreenState();
}

class _PredictionBattleScreenState extends ConsumerState<PredictionBattleScreen> {
  final _predictionController = TextEditingController();
  PredictionConfidence? _selectedConfidence;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(predictionProvider(widget.familyId).notifier).load());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _predictionController.dispose(); _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(predictionProvider(widget.familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: const Text('Prediction Battle', style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.purple))
          : RefreshIndicator(
              color: KinrelColors.purple, backgroundColor: KinrelColors.darkCard,
              onRefresh: () async { ref.invalidate(predictionProvider(widget.familyId)); await ref.read(predictionProvider(widget.familyId).notifier).load(); },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
                children: [
                  _Section1_ActivePrediction(state: state, controller: _predictionController, selectedConfidence: _selectedConfidence, onConfidenceChanged: (c) => setState(() => _selectedConfidence = c), onSubmit: _submitPrediction, familyId: widget.familyId),
                  const SizedBox(height: 20),
                  _Section2_Pending(state: state),
                  const SizedBox(height: 20),
                  _Section3_RecentResults(state: state),
                  const SizedBox(height: 20),
                  _Section4_Leaderboard(state: state),
                  const SizedBox(height: 20),
                  _Section5_PersonalStats(state: state),
                ],
              ),
            ),
    );
  }

  Future<void> _submitPrediction() async {
    final prediction = _predictionController.text.trim();
    if (prediction.isEmpty || _selectedConfidence == null) return;
    final success = await ref.read(predictionProvider(widget.familyId).notifier).submitPrediction(prediction, _selectedConfidence!);
    if (mounted) {
      if (success) {
        _predictionController.clear();
        setState(() => _selectedConfidence = null);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔮 Prediction submitted!'), behavior: SnackBarBehavior.floating));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit — try again'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    }
  }
}

// ─── Section 1: Active Prediction ────────────────────────────────────
class _Section1_ActivePrediction extends ConsumerWidget {
  const _Section1_ActivePrediction({required this.state, required this.controller, required this.selectedConfidence, required this.onConfidenceChanged, required this.onSubmit, required this.familyId});
  final PredictionState state;
  final TextEditingController controller;
  final PredictionConfidence? selectedConfidence;
  final void Function(PredictionConfidence) onConfidenceChanged;
  final VoidCallback onSubmit;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = state.activeRound;
    final question = state.activeQuestion;
    if (round == null || question == null) return const SizedBox.shrink();

    if (round.status == PredictionStatus.resolved) {
      return _ResolvedView(round: round, question: question, state: state);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: round.isLegendary ? [const Color(0xFF2B1A0E), const Color(0xFF1D1409)] : [KinrelColors.purple.withValues(alpha: 0.12), KinrelColors.darkCard]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: round.isLegendary ? KinrelColors.brightGold.withValues(alpha: 0.4) : KinrelColors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(round.isLegendary ? '🔮 Legendary' : '🔮', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(child: Text(question.type.label, style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.purple))),
          if (round.status == PredictionStatus.open)
            Text('Closes in ${_countdown(round.lockAt)}', style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, color: KinrelColors.orange)),
          if (round.status == PredictionStatus.locked)
            Text('Locked — reveals in ${_countdown(round.revealAt)}', style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, color: KinrelColors.amber)),
          if (round.status == PredictionStatus.pending)
            Text('Reveals in ${_countdown(round.revealAt)}', style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, color: KinrelColors.amber)),
        ]),
        const SizedBox(height: 12),
        Text(question.question, style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w800, color: KinrelColors.textWhite, height: 1.3)),
        const SizedBox(height: 8),
        if (question.type == PredictionType.closest)
          const Text('Predict a number. Closest wins!', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))
        else
          const Text('Choose an outcome. Correct wins!', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        const SizedBox(height: 16),
        if (state.hasSubmitted) ...[
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: KinrelColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: KinrelColors.success.withValues(alpha: 0.25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('✓ Your Prediction', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w700, color: KinrelColors.success)),
              const SizedBox(height: 6),
              Row(children: [
                const Text('Prediction: ', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textSilver)),
                Text(state.myPrediction ?? '—', style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.textWhite)),
                const SizedBox(width: 12),
                const Text('Confidence: ', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textSilver)),
                Text((state.myConfidence ?? PredictionConfidence.low).label, style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.amber)),
              ]),
              const SizedBox(height: 6),
              const Text('Predictions are hidden until reveal. Good luck! 🔒', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim)),
            ])),
        ] else if (round.status == PredictionStatus.open) ...[
          if (question.type == PredictionType.closest) ...[
            TextField(controller: controller, keyboardType: TextInputType.number, style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, color: KinrelColors.textWhite),
              decoration: InputDecoration(hintText: 'Enter your number...', filled: true, fillColor: KinrelColors.darkCard,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: KinrelColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: KinrelColors.purple, width: 1.4)))),
          ] else ...[
            Row(children: [
              Expanded(child: _OutcomeChip(label: question.optionA ?? 'Yes', selected: controller.text == (question.optionA ?? 'Yes'), onTap: () => controller.text = question.optionA ?? 'Yes')),
              const SizedBox(width: 8),
              Expanded(child: _OutcomeChip(label: question.optionB ?? 'No', selected: controller.text == (question.optionB ?? 'No'), onTap: () => controller.text = question.optionB ?? 'No')),
            ]),
          ],
          const SizedBox(height: 14),
          const Text('How confident are you?', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
          const SizedBox(height: 6),
          Row(children: [
            for (final c in PredictionConfidence.values) ...[
              Expanded(child: _ConfidenceChip(label: c.label, multiplier: 'x${c.multiplier}', selected: selectedConfidence == c, onTap: () => onConfidenceChanged(c))),
              if (c != PredictionConfidence.values.last) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 14),
          DKButton(label: 'Submit Prediction', variant: DKButtonVariant.primary, fullWidth: true, onPressed: selectedConfidence != null && controller.text.isNotEmpty ? onSubmit : null),
        ] else ...[
          Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(round.status == PredictionStatus.locked ? '🔒 Predictions are locked. Reveal coming soon!' : '⏳ Waiting for reveal...', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)))),
        ],
        const SizedBox(height: 8),
        Text('${state.participationCount} family members participated', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim)),
      ]),
    );
  }

  String _countdown(DateTime target) {
    // Step 3: use server-accurate now (handles device clock drift on
    // cheap Android hardware).
    final diff = target.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'soon';
    final h = diff.inHours; final m = diff.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    final s = diff.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ─── Section 2: Pending ──────────────────────────────────────────────
class _Section2_Pending extends StatelessWidget {
  const _Section2_Pending({required this.state});
  final PredictionState state;
  @override
  Widget build(BuildContext context) {
    final pending = state.recentResults.where((r) => r.status == PredictionStatus.pending).toList();
    final activePending = state.activeRound != null && state.activeRound!.status == PredictionStatus.pending ? [state.activeRound!] : <PredictionRound>[];
    final allPending = [...activePending, ...pending];
    if (allPending.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const GamingSectionHeader(title: 'Pending Reveal', icon: Icons.hourglass_top_outlined),
      for (final r in allPending.take(3)) Padding(padding: const EdgeInsets.only(bottom: 6),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.hourglass_empty, size: 16, color: KinrelColors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text('Reveals ${_timeLabel(r.revealAt)}', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver))),
            Text(r.status.label, style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 10, color: KinrelColors.amber)),
          ]))),
    ]);
  }
  String _timeLabel(DateTime t) {
    // Step 3: use server-accurate now (handles device clock drift).
    final diff = t.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'soon';
    return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
  }
}

// ─── Section 3: Recent Results (full history) ─────────────────────────
class _Section3_RecentResults extends StatelessWidget {
  const _Section3_RecentResults({required this.state});
  final PredictionState state;
  @override
  Widget build(BuildContext context) {
    final results = state.recentResults.where((r) => r.status == PredictionStatus.resolved).take(20).toList();
    if (results.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const GamingSectionHeader(title: 'Past Rounds & Results', icon: Icons.history),
      for (final r in results) Padding(padding: const EdgeInsets.only(bottom: 8),
        child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Question text (truncated if long).
            if (r.question?.question != null)
              Text(r.question!.question, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textSilver))
            else
              Text('Round ${r.id.substring(0, 6)}', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textSilver)),
            const SizedBox(height: 6),
            // Correct answer.
            Row(children: [
              const Text('Answer: ', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
              Text(r.actualAnswer ?? '—', style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
            ]),
            const SizedBox(height: 6),
            // Every member's prediction + outcome.
            if (r.results.isNotEmpty) ...[
              const Text('Family predictions:', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim)),
              const SizedBox(height: 4),
              for (final res in r.results)
                Padding(padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    Expanded(child: Text('${res.userId.substring(0, 8)} → ${res.prediction}', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver))),
                    if (res.points > 0)
                      Text('+${res.points}', style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.success))
                    else if (!res.correct)
                      const Text('—', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, color: KinrelColors.textDim)),
                  ])),
            ],
          ]))),
    ]);
  }
}

// ─── Section 4: Leaderboard ──────────────────────────────────────────
class _Section4_Leaderboard extends StatelessWidget {
  const _Section4_Leaderboard({required this.state});
  final PredictionState state;
  @override
  Widget build(BuildContext context) {
    if (state.leaderboard.isEmpty) return const SizedBox.shrink();
    final myId = state.myStats?.userId;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const GamingSectionHeader(title: 'Prediction Ranking', icon: Icons.leaderboard_outlined),
      // Full ranked list — uses PredictionLeaderboardEntry's existing
      // fields (points as primary sort, wins, accuracy %, current
      // streak, best streak per member). No artificial top-N cap —
      // shows every family member who has played at least once.
      for (var i = 0; i < state.leaderboard.length; i++)
        Padding(padding: const EdgeInsets.only(bottom: 6),
          child: _FullLeaderboardRow(
            rank: i + 1,
            entry: state.leaderboard[i],
            isMe: state.leaderboard[i].userId == myId,
          )),
    ]);
  }
}

/// A single row in the full leaderboard (battle screen). Shows all
/// the fields the user asked for: rank with medal icons, member name,
/// points (primary sort), wins, accuracy %, current streak, best streak.
class _FullLeaderboardRow extends StatelessWidget {
  const _FullLeaderboardRow({
    required this.rank,
    required this.entry,
    required this.isMe,
  });

  final int rank;
  final PredictionLeaderboardEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    // Medal icons for ranks 1-3.
    const medals = ['🥇', '🥈', '🥉'];
    final medal = rank <= 3 ? medals[rank - 1] : '#$rank';
    final accuracyPct = (entry.accuracy * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? KinrelColors.purple.withValues(alpha: 0.10)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe
              ? KinrelColors.purple.withValues(alpha: 0.30)
              : KinrelColors.border.withValues(alpha: 0.5),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          // Rank with medal icon.
          SizedBox(
            width: 32,
            child: Text(
              medal,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          // Member name + stats row beneath.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                    color: isMe ? KinrelColors.textWhite : KinrelColors.textSilver,
                  ),
                ),
                const SizedBox(height: 3),
                // Stats row: wins · accuracy · current streak · best streak.
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatChip(
                      label: '🏆 ${entry.wins}',
                      color: KinrelColors.brightGold,
                    ),
                    _StatChip(
                      label: '$accuracyPct% acc',
                      color: KinrelColors.textDim,
                    ),
                    if (entry.currentStreak > 0)
                      _StatChip(
                        label: '🔥 ${entry.currentStreak}',
                        color: KinrelColors.amber,
                      ),
                    if (entry.bestStreak > 0)
                      _StatChip(
                        label: 'best ${entry.bestStreak}',
                        color: KinrelColors.textDim,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Points (primary sort) — right-aligned.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.points}',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.purple,
                ),
              ),
              const Text(
                'pts',
                style: const TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
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

/// Tiny chip used inside _FullLeaderboardRow's stats row. Matches the
/// battle screen's existing dark theme.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: KinrelTypography.monoFont,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

// ─── Section 5: Personal Stats ───────────────────────────────────────
class _Section5_PersonalStats extends StatelessWidget {
  const _Section5_PersonalStats({required this.state});
  final PredictionState state;
  @override
  Widget build(BuildContext context) {
    final stats = state.myStats;
    if (stats == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const GamingSectionHeader(title: 'Your Statistics', icon: Icons.person_outline),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          _StatRow(label: 'Predictions Made', value: '${stats.totalPredictions}'),
          _StatRow(label: 'Wins', value: '${stats.wins}'),
          _StatRow(label: 'Accuracy', value: '${(stats.accuracy * 100).round()}%'),
          _StatRow(label: 'Best Streak', value: '${stats.bestStreak}'),
          _StatRow(label: 'Current Streak', value: '${stats.currentStreak}'),
          _StatRow(label: 'Total Points', value: '${stats.points}'),
        ])),
    ]);
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label; final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim))),
        Text(value, style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      ]));
  }
}

// ─── Resolved View ───────────────────────────────────────────────────
class _ResolvedView extends StatelessWidget {
  const _ResolvedView({required this.round, required this.question, required this.state});
  final PredictionRound round; final PredictionQuestion question; final PredictionState state;

  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: KinrelColors.brightGold.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🏆 Prediction Result', style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
        const SizedBox(height: 12),
        Text(question.question, style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textSilver)),
        const SizedBox(height: 8),
        Text('Correct Answer: ${round.actualAnswer ?? '—'}', style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
        const SizedBox(height: 12),
        if (round.results.isNotEmpty) ...[
          const Text('Family Predictions:', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
          const SizedBox(height: 6),
          for (final r in round.results)
            Padding(padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(child: Text('${r.userId.substring(0, 8)} → ${r.prediction}', style: const TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver))),
                if (r.points > 0) Text('+${r.points}', style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.success)),
              ])),
        ],
      ]));
  }
}

// ─── Helper widgets ──────────────────────────────────────────────────
class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.label, required this.selected, required this.onTap});
  final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap,
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: selected ? KinrelColors.purple.withValues(alpha: 0.2) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? KinrelColors.purple : KinrelColors.border)),
        child: Center(child: Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: selected ? KinrelColors.purple : KinrelColors.textDim)))));
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.label, required this.multiplier, required this.selected, required this.onTap});
  final String label; final String multiplier; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap,
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: selected ? KinrelColors.amber.withValues(alpha: 0.15) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: selected ? KinrelColors.amber : KinrelColors.border)),
        child: Column(children: [
          Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w700, color: selected ? KinrelColors.amber : KinrelColors.textDim)),
          Text(multiplier, style: const TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, color: KinrelColors.textDim)),
        ])));
  }
}
