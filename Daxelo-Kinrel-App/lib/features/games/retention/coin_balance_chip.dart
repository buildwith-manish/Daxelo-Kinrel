// lib/features/games/retention/coin_balance_chip.dart
//
// CoinBalanceChip — a small chip shown near the profile/home header.
// Displays the user's current Family Coins balance with a coin icon.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import 'coin_models.dart';
import 'retention_providers.dart';

class CoinBalanceChip extends ConsumerWidget {
  const CoinBalanceChip({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(coinBalanceProvider(familyId));
    return balanceAsync.when(
      loading: () => const SizedBox(
        width: 60,
        height: 28,
        child: Center(
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: KinrelColors.amber,
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (balance) => GestureDetector(
        onTap: () => context.push('/family/$familyId/gaming/rewards'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: KinrelColors.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '🪙',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 4),
              Text(
                '${balance.balance}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.amber,
                ),
              ),
            ],
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(
              duration: 2.seconds,
              color: KinrelColors.amber.withValues(alpha: 0.15),
            ),
      ),
    );
  }
}
