// lib/features/prediction_battle_v1/pb_v1_coin_history_screen.dart
//
// Coin history screen — shows the user's current balance as a hero
// stat at the top, then a paginated list of coin ledger entries
// (credits + spends). Each entry shows the reason, amount, and
// timestamp. Reachable via the coin chip on the family hub and via
// a "View coins" link on the prediction card.
//
// Layout:
//   - AppBar: "Your Coins" + refresh button
//   - Balance hero: large gold number + "lifetime earned: N" subtitle
//   - Empty state if no rows: "No coins yet — win a prediction to earn your first 10!"
//   - History list: each row shows an icon (per reason), reason label,
//     amount in green (credit) or red (spend), and a relative time
//     ("2h ago", "yesterday", "Sep 22"). Sorted by createdAt DESC.
//
// Like the prediction history screen, this screen does NOT hold a
// realtime WS subscription — coin balance changes happen on the 9 PM
// reveal tick and the user refreshes by pulling-to-refresh or
// re-opening the screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import 'pb_v1_coin_models.dart';
import 'pb_v1_coin_provider.dart';

class PBv1CoinHistoryScreen extends ConsumerStatefulWidget {
  const PBv1CoinHistoryScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<PBv1CoinHistoryScreen> createState() => _PBv1CoinHistoryScreenState();
}

class _PBv1CoinHistoryScreenState extends ConsumerState<PBv1CoinHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pbV1CoinProvider(widget.familyId).notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pbV1CoinProvider(widget.familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        title: const Text('Your Coins', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(pbV1CoinProvider(widget.familyId).notifier).refresh(),
          ),
        ],
      ),
      body: state.isLoading && state.history == null
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : state.history == null
              ? _ErrorState(error: state.error)
              : _CoinHistoryBody(history: state.history!),
    );
  }
}

// ── Error state ──────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          error != null ? 'Could not load coin history: $error' : 'Could not load coin history.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: KinrelColors.textDim, fontFamily: KinrelTypography.bodyFont),
        ),
      ),
    );
  }
}

// ── Main body ────────────────────────────────────────────────────────

/// Filter chip enum for the coin history list. Phase 3.19.
enum _CoinFilter {
  all,        // all entries
  earned,     // amount > 0 (credits only)
  spent,      // amount < 0 (spends only — not currently used by the
              // prediction module but supported by the schema)
  thisWeek,   // createdAt within the last 7 days
}

class _CoinHistoryBody extends StatefulWidget {
  const _CoinHistoryBody({required this.history});
  final PBv1CoinHistory history;

  @override
  State<_CoinHistoryBody> createState() => _CoinHistoryBodyState();
}

class _CoinHistoryBodyState extends State<_CoinHistoryBody> {
  _CoinFilter _filter = _CoinFilter.all;

  List<PBv1CoinHistoryEntry> get _filteredRows {
    switch (_filter) {
      case _CoinFilter.all:
        return widget.history.rows;
      case _CoinFilter.earned:
        return widget.history.rows.where((r) => r.isCredit).toList();
      case _CoinFilter.spent:
        return widget.history.rows.where((r) => !r.isCredit).toList();
      case _CoinFilter.thisWeek:
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        return widget.history.rows.where((r) => r.createdAt.isAfter(cutoff)).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredRows = _filteredRows;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BalanceHero(balance: widget.history.balance),
        const SizedBox(height: 20),
        // ── Filter chips row (Phase 3.19) ───────────────────────
        // The chips sit between the balance hero and the list.
        // "All" is the default. The count badges per chip are
        // computed from the loaded data — no extra RPC needed.
        if (widget.history.rows.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  count: widget.history.rows.length,
                  selected: _filter == _CoinFilter.all,
                  onTap: () => setState(() => _filter = _CoinFilter.all),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Earned',
                  count: widget.history.rows.where((r) => r.isCredit).length,
                  selected: _filter == _CoinFilter.earned,
                  onTap: () => setState(() => _filter = _CoinFilter.earned),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Spent',
                  count: widget.history.rows.where((r) => !r.isCredit).length,
                  selected: _filter == _CoinFilter.spent,
                  onTap: () => setState(() => _filter = _CoinFilter.spent),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'This week',
                  count: widget.history.rows
                      .where((r) => r.createdAt.isAfter(
                        DateTime.now().subtract(const Duration(days: 7)),
                      ))
                      .length,
                  selected: _filter == _CoinFilter.thisWeek,
                  onTap: () => setState(() => _filter = _CoinFilter.thisWeek),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Recent activity',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 8),
        if (widget.history.rows.isEmpty)
          const _EmptyHistoryState()
        else if (filteredRows.isEmpty)
          // The user filtered to a category that has no entries
          // (e.g., "Spent" before any spend feature exists).
          _EmptyFilterState(filter: _filter)
        else
          for (final entry in filteredRows)
            _CoinHistoryRow(entry: entry),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? KinrelColors.orange : KinrelColors.textDim;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.orange.withValues(alpha: 0.12)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? KinrelColors.orange.withValues(alpha: 0.35)
                : KinrelColors.border,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.filter});
  final _CoinFilter filter;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _CoinFilter.earned => 'No credits yet — win a prediction to earn your first 10 coins.',
      _CoinFilter.spent => 'No spends yet — feature a Family Moment for 50 coins to see your first spend here.',
      _CoinFilter.thisWeek => 'No activity this week — submit a guess today to get started.',
      _CoinFilter.all => 'No activity yet.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: KinrelColors.textDim,
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ── Balance hero ─────────────────────────────────────────────────────

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance});
  final PBv1CoinBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.orange.withValues(alpha: 0.10),
            KinrelColors.darkCard,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🪙', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT BALANCE',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: KinrelColors.orange.withValues(alpha: 0.80),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${balance.balance}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: balance.balance > 0
                          ? KinrelColors.orange
                          : KinrelColors.textDim,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Lifetime earned: ${balance.lifetimeEarned}',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty history state ──────────────────────────────────────────────

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Text('🪙', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 12),
          const Text(
            'No coins yet',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Win today\'s Prediction Battle to earn your first 10 coins. Close guesses also earn 2 consolation coins.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-entry row ────────────────────────────────────────────────────

class _CoinHistoryRow extends StatelessWidget {
  const _CoinHistoryRow({required this.entry});
  final PBv1CoinHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.isCredit;
    final amountColor = isCredit ? KinrelColors.success : KinrelColors.amber;
    final amountSign = isCredit ? '+' : '−';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KinrelColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Icon per reason
          Text(_icon(), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          // Reason + timestamp
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.reasonLabel,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTimestamp(entry.createdAt),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          // Amount (signed, color-coded)
          Text(
            '$amountSign${entry.amount.abs()}',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  String _icon() {
    switch (entry.reason) {
      case 'prediction_winner':
        return '🏆';
      case 'prediction_streak_bonus':
        return '🔥';
      case 'prediction_close_guess':
        return '🎯';
      case 'prediction_participation':
        return '✅';
      default:
        return '🪙';
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
