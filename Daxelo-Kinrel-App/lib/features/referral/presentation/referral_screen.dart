import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/referral_provider.dart';

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerCtrl;
  late Animation<double> _f1, _f2, _f3, _f4, _f5;
  late Animation<Offset> _s1, _s2, _s3, _s4, _s5;

  // Mock user ID — in production this would come from auth
  final String _userId = 'user_demo_001';

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _f1 = _fade(0.00, 0.25);
    _s1 = _slide(0.00, 0.25);
    _f2 = _fade(0.10, 0.35);
    _s2 = _slide(0.10, 0.35);
    _f3 = _fade(0.20, 0.45);
    _s3 = _slide(0.20, 0.45);
    _f4 = _fade(0.30, 0.55);
    _s4 = _slide(0.30, 0.55);
    _f5 = _fade(0.40, 0.65);
    _s5 = _slide(0.40, 0.65);
    _staggerCtrl.forward();

    // Auto-generate referral code on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(referralProvider.notifier).generateCode(_userId);
    });
  }

  Animation<double> _fade(double a, double b) => Tween<double>(begin: 0, end: 1)
      .animate(CurvedAnimation(
          parent: _staggerCtrl, curve: Interval(a, b, curve: Curves.easeOutCubic)));

  Animation<Offset> _slide(double a, double b) =>
      Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(CurvedAnimation(
              parent: _staggerCtrl, curve: Interval(a, b, curve: Curves.easeOutCubic)));

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final referralState = ref.watch(referralProvider);
    final rewardsAsync = ref.watch(rewardsProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: KinrelColors.textWhite),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Refer & Earn',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _AnimSection(
                fade: _f1,
                slide: _s1,
                child: _buildReferralCodeCard(referralState),
              ),
              const SizedBox(height: 24),
              _AnimSection(
                fade: _f2,
                slide: _s2,
                child: _buildStatsRow(referralState),
              ),
              const SizedBox(height: 24),
              _AnimSection(
                fade: _f3,
                slide: _s3,
                child: _buildSectionHeader('Reward Tiers'),
              ),
              const SizedBox(height: 12),
              _AnimSection(
                fade: _f3,
                slide: _s3,
                child: rewardsAsync.when(
                  data: (rewards) => _buildRewardTiers(rewards, referralState),
                  loading: () => _buildShimmerCard(),
                  error: (_, __) => _buildRewardTiersFallback(referralState),
                ),
              ),
              const SizedBox(height: 24),
              _AnimSection(
                fade: _f4,
                slide: _s4,
                child: _buildSectionHeader('Recent Referrals'),
              ),
              const SizedBox(height: 12),
              _AnimSection(
                fade: _f4,
                slide: _s4,
                child: _buildRecentReferrals(referralState),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── Referral Code Card ────────────────────────────────────────────

  Widget _buildReferralCodeCard(ReferralState state) {
    final code = state.code?.code ?? 'KINREL-****';
    final shareText = state.code?.shareText ??
        'Join me on KINREL! Discover your family relationships in 15 Indian languages. Use my code: $code';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1508), KinrelColors.darkCard],
        ),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon and title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: KinrelColors.orange.withValues(alpha: 0.15),
              border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.card_giftcard_rounded,
                    color: KinrelColors.orange, size: 14),
                SizedBox(width: 6),
                Text('Your Referral Code',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.orange,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Code display
          if (state.isGenerating)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  color: KinrelColors.orange, strokeWidth: 2.5),
            )
          else
            SelectableText(
              code,
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                letterSpacing: 3,
              ),
            ),
          const SizedBox(height: 20),

          // Copy + Share buttons
          if (!state.isGenerating)
            Row(
              children: [
                Expanded(
                  child: _PressDown(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied to clipboard!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: KinrelColors.success,
                        ),
                      );
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: KinrelColors.darkElevated,
                        border: Border.all(
                            color: KinrelColors.darkSurface.withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.copy_rounded,
                              color: KinrelColors.textSilver, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Copy Code',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textSilver,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PressDown(
                    onTap: () {
                      // Share via platform share sheet
                      // In production: use share_plus package
                      Clipboard.setData(ClipboardData(text: shareText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Share text copied!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: KinrelColors.amber,
                        ),
                      );
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                            colors: [KinrelColors.orange, KinrelColors.amber]),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Share',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────

  Widget _buildStatsRow(ReferralState state) {
    final totalReferrals = state.stats?.totalReferrals ?? 0;
    final rewardsCount = state.stats?.rewards.length ?? 0;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.people_alt_rounded,
            value: '$totalReferrals',
            label: 'Total Referrals',
            color: KinrelColors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.emoji_events_rounded,
            value: '$rewardsCount',
            label: 'Rewards Earned',
            color: KinrelColors.amber,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Header ────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
      ],
    );
  }

  // ── Reward Tiers ──────────────────────────────────────────────────

  Widget _buildRewardTiers(RewardsData rewards, ReferralState state) {
    final totalReferrals = state.stats?.totalReferrals ?? 0;

    return Column(
      children: rewards.tiers.map((tier) {
        final progress = (totalReferrals / tier.referrals).clamp(0.0, 1.0);
        final isUnlocked = totalReferrals >= tier.referrals;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isUnlocked
                    ? KinrelColors.success.withValues(alpha: 0.4)
                    : KinrelColors.darkSurface.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isUnlocked
                            ? KinrelColors.success.withValues(alpha: 0.15)
                            : KinrelColors.darkSurface.withValues(alpha: 0.4),
                      ),
                      child: Center(
                        child: isUnlocked
                            ? const Icon(Icons.check_rounded,
                                color: KinrelColors.success, size: 20)
                            : Text(
                                '${tier.referrals}',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: KinrelColors.textDim,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                tier.reward,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isUnlocked
                                      ? KinrelColors.success
                                      : KinrelColors.textWhite,
                                ),
                              ),
                              if (tier.badge != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: KinrelColors.amber
                                        .withValues(alpha: 0.12),
                                  ),
                                  child: Text(
                                    tier.badge!,
                                    style: const TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: KinrelColors.amber,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tier.description,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              color: KinrelColors.textDim,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: KinrelColors.darkSurface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isUnlocked ? KinrelColors.success : KinrelColors.orange,
                    ),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$totalReferrals / ${tier.referrals} referrals',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    if (isUnlocked)
                      const Text(
                        'Unlocked!',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.success,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRewardTiersFallback(ReferralState state) {
    // Fallback with hardcoded tiers if API is unavailable
    final tiers = [
      RewardTier(
          referrals: 5,
          reward: 'Premium 1 month free',
          description: 'Unlock Premium features for 1 month'),
      RewardTier(
          referrals: 10,
          reward: 'Premium 3 months free',
          description: 'Unlock Premium features for 3 months'),
      RewardTier(
          referrals: 25,
          reward: 'Premium 1 year free',
          badge: 'Family Champion',
          description: '1 year of Premium + exclusive badge'),
      RewardTier(
          referrals: 50,
          reward: 'Lifetime Premium',
          badge: 'Kinrel Ambassador',
          description: 'Lifetime Premium + exclusive badge'),
    ];

    return _buildRewardTiers(RewardsData(tiers: tiers), state);
  }

  // ── Recent Referrals ──────────────────────────────────────────────

  Widget _buildRecentReferrals(ReferralState state) {
    final recent = state.stats?.recentReferrals ?? [];

    if (recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: KinrelColors.darkSurface.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Icon(Icons.group_add_outlined,
                color: KinrelColors.textDim, size: 32),
            const SizedBox(height: 12),
            const Text(
              'No referrals yet',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Share your code to start earning rewards!',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: recent.map((ref) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: KinrelColors.orange, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ref.name,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      Text(
                        _formatDate(ref.date),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_rounded,
                    color: KinrelColors.success, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Shimmer Card ──────────────────────────────────────────────────

  Widget _buildShimmerCard() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: KinrelColors.orange.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

// ── Animation wrapper ────────────────────────────────────────────────

class _AnimSection extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;

  const _AnimSection({
    required this.fade,
    required this.slide,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: fade, child: SlideTransition(position: slide, child: child));
}

// ── PressDown feedback ───────────────────────────────────────────────

class _PressDown extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressDown({required this.child, required this.onTap});

  @override
  State<_PressDown> createState() => _PressDownState();
}

class _PressDownState extends State<_PressDown>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _sc;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _sc = Tween<double>(begin: 1.0, end: 0.95).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) {
          _c.reverse();
          widget.onTap();
        },
        onTapCancel: () => _c.reverse(),
        child: AnimatedBuilder(
          animation: _sc,
          builder: (_, child) =>
              Transform.scale(scale: _sc.value, child: child),
          child: widget.child,
        ),
      );
}
