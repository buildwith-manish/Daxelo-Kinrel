// lib/features/prediction_battle_v1/pb_v1_fun_fact_card.dart
//
// "Did you know?" card — surfaces a random fun fact from the
// pb_v1_questions table on the family hub. Increases daily app-open
// value beyond just the prediction.
//
// Picks one fun fact per day per family (deterministic by date so
// all family members see the same fact on the same day — gives them
// something to chat about). The card is a small horizontal strip
// with a lightbulb icon + the fact text. Tap is a no-op (the fact
// is the value).
//
// Implementation:
//   - On first build of the day, fetch a random question with a
//     non-empty fun_fact_text. Cache the chosen question_id in
//     LocalCacheService with a date-stamped key so we don't refetch
//     on every hub rebuild.
//   - On subsequent days, the cache key (date) changes → refetch.
//
// The card is hidden if there are no questions with fun facts, or
// if the fetch fails.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/storage/local_cache.dart';

class PredictionBattleFunFactCard extends ConsumerStatefulWidget {
  const PredictionBattleFunFactCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PredictionBattleFunFactCard> createState() => _PredictionBattleFunFactCardState();
}

class _PredictionBattleFunFactCardState extends ConsumerState<PredictionBattleFunFactCard> {
  String? _factText;
  String? _questionText;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadFact());
  }

  Future<void> _loadFact() async {
    // Check cache first — the fact is daily, so we cache by date.
    final cacheKey = 'pb_v1_funfact_${_todayDateStr()}';
    final cache = ref.read(localCacheProvider);
    final cached = await cache.getPreference<Map<String, dynamic>>(cacheKey);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _factText = cached['fact'] as String?;
          _questionText = cached['question'] as String?;
          _loading = false;
        });
      }
      return; // Cache hit — don't refetch.
    }

    final client = ref.read(supabaseProvider);
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // Fetch up to 20 random questions that have non-empty fun facts.
      // We fetch 20 rather than 1 so we can pick a stable one per
      // family-per-day without a SQL "ORDER BY random()" full-table
      // scan (which would be slow on a large questions table).
      // The 20 is then narrowed client-side to one deterministic
      // pick by hash of (familyId + date).
      final rows = await client
          .from('pb_v1_questions')
          .select('id, question_text, fun_fact_text')
          .not('fun_fact_text', 'eq', '')
          .limit(20);
      if (!mounted) return;
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      // Deterministic pick: hash the familyId + date string → index.
      final hash = '${widget.familyId}|${_todayDateStr()}'.hashCode;
      final pick = list[hash.abs() % list.length];
      final fact = (pick['fun_fact_text'] as String?).toString().trim();
      final question = (pick['question_text'] as String?).toString().trim();
      setState(() {
        _factText = fact;
        _questionText = question;
        _loading = false;
      });
      // Cache for the rest of the day.
      await cache.setPreference(cacheKey, {'fact': fact, 'question': question});
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _todayDateStr() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _factText == null || _factText!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 18, color: KinrelColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DID YOU KNOW?',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: KinrelColors.amber,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _factText!,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Family Coin Pool card (Tier 3 item 12)
// ═══════════════════════════════════════════════════════════════════════
//
// Small progress card showing the family's collective coin pool
// vs. the next goal. Tap to deep-link to the coin history screen
// (where the user can see their own contributions to the pool).
//
// Hidden if the fetch fails or the pool is at 0 / goal is 0.
//
// UX pass — Endowed Progress Effect: when the pool is still empty, the
// card no longer shows a demotivating "0 / 500" bar. Instead it shows
// a "Starting bonus: +10 coins" head start — the bar is pre-filled
// toward the goal so the family feels they have already begun. People
// who feel they've made progress toward a goal are far more likely to
// complete it.

class FamilyCoinPoolCard extends ConsumerStatefulWidget {
  const FamilyCoinPoolCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyCoinPoolCard> createState() => _FamilyCoinPoolCardState();
}

class _FamilyCoinPoolCardState extends ConsumerState<FamilyCoinPoolCard> {
  int? _totalEarned;
  int? _currentGoal;
  int? _goalsHit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadPool());
  }

  Future<void> _loadPool() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final resp = await client.rpc('fn_get_family_coin_pool', params: {
        'p_family_id': widget.familyId,
      });
      if (!mounted) return;
      if (resp is Map && resp['ok'] == true) {
        setState(() {
          _totalEarned = (resp['total_earned'] ?? 0) as int;
          _currentGoal = (resp['current_goal'] ?? 500) as int;
          _goalsHit = (resp['goals_hit'] ?? 0) as int;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _totalEarned == null || _currentGoal == null || _currentGoal == 0) {
      return const SizedBox.shrink();
    }
    // Endowed Progress Effect: an empty pool starts the family at a
    // visible +10-coin head start rather than a flat zero bar.
    final isEndowed = _totalEarned! == 0;
    final shownEarned = isEndowed ? 10 : _totalEarned!;
    final progress = (shownEarned / _currentGoal!).clamp(0.0, 1.0);

    // Phase 3 (ux/family-space-refinement): downgraded from a full
    // AppCard.hero-style treatment (gradient + border + 14px padding
    // + multi-line content) to a SLIM HORIZONTAL PROGRESS STRIP —
    // a single-row card with icon + label + progress bar + count.
    // This establishes clear visual hierarchy: Prediction Battle is
    // the hero (full AppCard.hero treatment, draws the eye first),
    // Family Coin Pool is secondary/ambient status (slim strip, reads
    // as background information, not a competing call-to-action).
    //
    // The strip uses AppCard.compact styling (darkCard bg + hairline
    // border + radius 12 + horizontal 12 / vertical 10 padding) but
    // rendered as a single Row, not a Column — so it takes ~48px of
    // vertical space instead of ~120px.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          // Icon — 🪙 or 🎁 (endowed). Small, 18px.
          Text(
            isEndowed ? '🎁' : '🪙',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 8),
          // Label — "Coin Pool" (short, single line).
          Text(
            'Coin Pool',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: isEndowed ? KinrelColors.amber : KinrelColors.orange,
            ),
          ),
          const SizedBox(width: 10),
          // Progress bar — slim, takes remaining width.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: isEndowed
                    ? KinrelColors.amber.withValues(alpha: 0.12)
                    : KinrelColors.orange.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isEndowed ? KinrelColors.amber : KinrelColors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Count — "12 / 500" (short, single line, right-aligned).
          Text(
            '$shownEarned / $_currentGoal',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }
}
