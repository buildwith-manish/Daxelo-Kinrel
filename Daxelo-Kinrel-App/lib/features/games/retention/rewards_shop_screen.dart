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
  /// Local optimistic adjustment to the displayed coin balance. Set
  /// immediately to `-reward.cost` when the user taps Redeem, so the
  /// balance display drops instantly without waiting for the RPC +
  /// server re-fetch round-trip. Cleared to 0 on success (after which
  /// `coinBalanceProvider` is invalidated and the authoritative value
  /// takes over) or on failure (rolling the display back).
  int _optimisticDelta = 0;

  @override
  Widget build(BuildContext context) {
    final rewardsAsync = ref.watch(rewardsProvider(widget.familyId));
    final balanceAsync = ref.watch(coinBalanceProvider(widget.familyId));
    final serverBalance = balanceAsync.asData?.value ?? const CoinBalance();
    // Apply optimistic delta so the displayed balance reflects any
    // in-flight redemption instantly. Clamped at 0 so we never display
    // a negative balance.
    final displayBalance = (serverBalance.balance + _optimisticDelta).clamp(0, 1 << 30);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Rewards Shop',
            style: const TextStyle(
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
                      '$displayBalance',
                      style: const TextStyle(
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
        error: (e, _) => const Center(
          child: const GamingEmptyCard(
            emoji: '🔌',
            title: 'Couldn\'t load rewards',
            message: 'Pull down to try again.',
          ),
        ),
        data: (rewards) {
          if (rewards.isEmpty) {
            return const Center(
              child: const GamingEmptyCard(
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
            // v114 — Step 4 perf: build a flat list of rows then use
            // ListView.builder so reward cards are built lazily.
            child: Builder(builder: (context) {
              final rows = <Widget>[
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
                            const Text(
                              'Family Treasury',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                            Text(
                              '${balance.familyTreasury} coins combined',
                              style: const TextStyle(
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
                          const Text(
                            'Your balance',
                            style: const TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 10,
                              color: KinrelColors.textDim,
                            ),
                          ),
                          Text(
                            '🪙 ${balance.balance}',
                            style: const TextStyle(
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
              ];
              for (final entry in categories.entries) {
                rows.add(GamingSectionHeader(
                  title: categoryLabels[entry.key] ?? entry.key,
                  icon: _iconForCategory(entry.key),
                ));
                for (final reward in entry.value) {
                  rows.add(_RewardCard(
                    reward: reward,
                    // Pass the optimistic display balance so the
                    // canAfford check disables the redeem button while
                    // an in-flight redemption is consuming coins.
                    balance: displayBalance,
                    isRedeeming: _redeemingId == reward.id,
                    onRedeem: () => _handleRedeem(reward),
                  ));
                }
                rows.add(const SizedBox(height: 12));
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                itemCount: rows.length,
                itemBuilder: (context, index) => rows[index],
              );
            }),
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
    // ── Optimistic update ─────────────────────────────────────
    // Drop the displayed balance by reward.cost immediately so the
    // user sees the spend reflected without waiting for the RPC +
    // server re-fetch round-trip. Mark the card as redeeming (spinner).
    setState(() {
      _redeemingId = reward.id;
      _optimisticDelta = -reward.cost;
    });
    final success = await redeemReward(
      ref: ref,
      familyId: widget.familyId,
      rewardId: reward.id,
    );
    if (mounted) {
      if (success) {
        // ── Success: reconcile ────────────────────────────────
        // Invalidate the coin balance provider so the authoritative
        // server value re-fetches. Keep _optimisticDelta = -cost until
        // the fresh coinBalanceProvider value arrives (which will
        // already reflect the deduction), then clear it in a
        // post-frame callback so the display cleanly transitions.
        ref.invalidate(rewardsProvider(widget.familyId));
        ref.invalidate(coinBalanceProvider(widget.familyId));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _optimisticDelta = 0);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${reward.name} unlocked!'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // ── Failure: roll back ────────────────────────────────
        // Restore the optimistic delta to 0 so the displayed balance
        // reverts to the server-confirmed value (no spend happened).
        setState(() {
          _optimisticDelta = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Not enough coins — need ${reward.cost} 🪙'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _redeemingId = null);
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
                  style: const TextStyle(
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
                    style: const TextStyle(
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
              child: const Text(
                'Owned',
                style: const TextStyle(
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
