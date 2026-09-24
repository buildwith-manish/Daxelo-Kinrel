// lib/features/prediction_battle_v1/pb_v1_coin_chip.dart
//
// Small inline chip widget that shows the user's coin balance for the
// family. Tap to open the coin history screen. Designed to sit in the
// family hub's hero section next to the prediction teaser.
//
// Visual: a small rounded chip with a coin icon (🪙) + the balance
// number. Color-coded:
//   - balance > 0 → gold (positive achievement state)
//   - balance == 0 → dim grey (neutral, "you haven't earned coins yet")
//
// The chip:
//   - Does NOT trigger `load()` itself — relies on whoever else has
//     loaded the provider for this family (the hero teaser screen or
//     the coin history screen). If neither has loaded yet, the chip
//     renders with a "—" placeholder.
//   - Is intentionally tiny (~24 logical px tall) so it doesn't crowd
//     the hero layout.
//   - Uses ConsumerWidget so it re-builds automatically when the
//     provider state changes (e.g., after the 9 PM reveal tick
//     updates the balance, the chip will refresh on the next screen
//     open without manual invalidation).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import 'pb_v1_coin_provider.dart';

class PredictionBattleCoinChip extends ConsumerWidget {
  const PredictionBattleCoinChip({super.key, required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pbV1CoinProvider(familyId));
    final balance = state.history?.balance.balance;
    final hasBalance = balance != null && balance > 0;

    // Color: gold for positive, dim grey for zero / loading.
    final color = hasBalance ? KinrelColors.brightGold : KinrelColors.textDim;
    final displayBalance = balance != null ? '$balance' : '—';

    return GestureDetector(
      onTap: () => context.push('/family/$familyId/prediction-battle-v1/coins'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.30),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🪙', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              displayBalance,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
