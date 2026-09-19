// lib/features/games/retention/rewards_shop_screen.dart
//
// RewardsShopScreen — lists unlockable rewards by category with cost
// and lock/unlock state. Users can redeem rewards with Family Coins.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import 'coin_models.dart';
import 'retention_providers.dart';

class RewardsShopScreen extends ConsumerStatefulWidget {
  const RewardsShopScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<RewardsShopScreen> createState() =>
      _RewardsShopScreenState();
}

class _RewardsShopScreenState extends ConsumerState<RewardsShopScreen> {
  String? _redeemingId;

  @override
  Widget build(BuildContext context) {
    final rewardsAsync = ref.watch(rewardsProvider(widget.familyId));
    final balanceAsync = ref.watch(coinBalanceProvider(widget.familyId));
    final balance = balanceAsync.asData?.value ?? const CoinBalance();

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text('Rewards Shop',
            style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontWeight: FontWeight.w700)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: KinrelColors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: KinrelColors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🪙', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      '${balance.balance}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: rewardsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (e, _) => Center(
          child: GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load rewards',
            message: 'Pull down to try again.',
          ),
        ),
        data: (rewards) {
          if (rewards.isEmpty) {
            return Center(
              child: GamingEmptyCard(
                emoji: '🪙',
                title: 'No rewards available yet',
                message: 'Play games to earn Family Coins, then check back!',
              ),
            );
          }

          // Group by category
          final categories = <String, List<UnlockableReward>>{};
          for (final r in rewards) {
            categories.putIfAbsent(r.category, () => []).add(r);
          }

          final categoryLabels = {
            'board_skins': 'Board Skins',
            'reaction_packs': 'Reaction Packs',
            'trophy_frames': 'Trophy Frames',
            'naming_rights': 'Naming Rights',
            'general': 'Rewards',
          };

          return RefreshIndicator(
            color: KinrelColors.orange,
            backgroundColor: KinrelColors.darkCard,
            onRefresh: () async {
              ref.invalidate(rewardsProvider(widget.familyId));
              ref.invalidate(coinBalanceProvider(widget.familyId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // Family treasury summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        KinrelColors.amber.withValues(alpha: 0.12),
                        KinrelColors.darkCard,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: KinrelColors.amber.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Text('🏦', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Family Treasury',
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                            Text(
                              '${balance.familyTreasury} coins combined',
                              style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 12,
                                color: KinrelColors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Your balance',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 10,
                              color: KinrelColors.textDim,
                            ),
                          ),
                          Text(
                            '🪙 ${balance.balance}',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: KinrelColors.amber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                for (final entry in categories.entries) ...[
                  GamingSectionHeader(
                    title: categoryLabels[entry.key] ?? entry.key,
                    icon: _iconForCategory(entry.key),
                  ),
                  for (final reward in entry.value)
                    _RewardCard(
                      reward: reward,
                      balance: balance.balance,
                      isRedeeming: _redeemingId == reward.id,
                      onRedeem: () => _handleRedeem(reward),
                    ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'board_skins':
        return Icons.palette_outlined;
      case 'reaction_packs':
        return Icons.emoji_emotions_outlined;
      case 'trophy_frames':
        return Icons.workspace_premium_outlined;
      case 'naming_rights':
        return Icons.edit_outlined;
      default:
        return Icons.card_giftcard_outlined;
    }
  }

  Future<void> _handleRedeem(UnlockableReward reward) async {
    if (reward.isUnlocked) return;
    setState(() {
      _redeemingId = reward.id;
    });
    final success = await redeemReward(
      ref: ref,
      familyId: widget.familyId,
      rewardId: reward.id,
    );
    if (mounted) {
      setState(() => _redeemingId = null);
      if (success) {
        ref.invalidate(rewardsProvider(widget.familyId));
        ref.invalidate(coinBalanceProvider(widget.familyId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${reward.name} unlocked!'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Not enough coins — need ${reward.cost} 🪙'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.balance,
    required this.isRedeeming,
    required this.onRedeem,
  });

  final UnlockableReward reward;
  final int balance;
  final bool isRedeeming;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final canAfford = balance >= reward.cost;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reward.isUnlocked
              ? KinrelColors.success.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (reward.isUnlocked
                      ? KinrelColors.success
                      : KinrelColors.amber)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(reward.iconEmoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reward.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                if (reward.description.isNotEmpty)
                  Text(
                    reward.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (reward.isUnlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: KinrelColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: KinrelColors.success.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Owned',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.success,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: isRedeeming ? null : (canAfford ? onRedeem : null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: canAfford
                      ? KinrelColors.amber
                      : KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isRedeeming
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '🪙 ${reward.cost}',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color:
                                  canAfford ? Colors.white : KinrelColors.textDim,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: 0.02, end: 0, duration: 200.ms);
  }
}
