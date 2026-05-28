// lib/presentation/screens/premium/paywall_screen.dart
//
// DAXELO KINREL — Paywall Screen (P5)
//
// Premium subscription paywall showing:
//   - Monthly: ₹99/month
//   - Yearly: ₹799/year (save 33%)
// On payment success: calls PremiumService, updates provider,
// and navigates back.
//
// Uses existing Razorpay integration pattern and app colors.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/crashlytics_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isProcessing = false;
  String? _errorMessage;

  // Plan definitions
  static const _monthlyPrice = 99.0; // ₹99/month
  static const _yearlyPrice = 799.0; // ₹799/year
  static const _monthlySavings = 0.0;
  static const _yearlySavingsPercent = 33; // 33% savings

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    AnalyticsService.instance.logScreenView('paywall');
    AnalyticsService.instance.logSubscriptionStarted('viewed');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.close_rounded,
            color: KinrelColors.textWhite,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Go Premium',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),

              // ── Hero Section ────────────────────────────────────
              _buildHeroSection(),

              const SizedBox(height: 24),

              // ── Feature List ─────────────────────────────────────
              _buildFeatureList(),

              const SizedBox(height: 28),

              // ── Plan Selection ───────────────────────────────────
              _buildPlanSelection(),

              const SizedBox(height: 12),

              // ── Error Message ────────────────────────────────────
              if (_errorMessage != null) _buildErrorMessage(),

              // ── Subscribe Button ─────────────────────────────────
              _buildSubscribeButton(),

              const SizedBox(height: 12),

              // ── Terms ────────────────────────────────────────────
              _buildTermsText(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // HERO SECTION
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildHeroSection() {
    return Column(
      children: [
        // Premium badge icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [KinrelColors.orange, KinrelColors.amber],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            color: Colors.white,
            size: 36,
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .shimmer(duration: 3000.ms, color: Colors.white.withValues(alpha: 0.15)),

        const SizedBox(height: 20),

        const Text(
          'Unlock the Full\nKinrel Experience',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 10),

        Text(
          'Add unlimited members, get AI suggestions,\nand unlock premium features.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textSilver,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // FEATURE LIST
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFeatureList() {
    const features = [
      (Icons.group_add_rounded, 'Unlimited family members'),
      (Icons.auto_awesome_rounded, 'AI-powered relationship suggestions'),
      (Icons.qr_code_2_rounded, 'Custom QR codes for invites'),
      (Icons.history_rounded, 'Full family history & timeline'),
      (Icons.card_giftcard_rounded, 'Exclusive festival card templates'),
      (Icons.support_agent_rounded, 'Priority support'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: features.map((feature) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange.withValues(alpha: 0.12),
                  ),
                  child: Icon(feature.$1, color: KinrelColors.orange, size: 14),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    feature.$2,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                const Icon(
                  Icons.check_circle_rounded,
                  color: KinrelColors.success,
                  size: 18,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PLAN SELECTION
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildPlanSelection() {
    return Column(
      children: [
        // Yearly plan (recommended)
        _PlanCard(
          title: 'Yearly',
          price: '₹$_yearlyPrice',
          period: '/year',
          badge: 'Save $_yearlySavingsPercent%',
          isRecommended: true,
          isSelected: _tabController.index == 0,
          onTap: () {
            setState(() {
              _tabController.animateTo(0);
            });
          },
          pricePerMonth: '₹${(_yearlyPrice / 12).toStringAsFixed(0)}/mo',
        ),

        const SizedBox(height: 10),

        // Monthly plan
        _PlanCard(
          title: 'Monthly',
          price: '₹$_monthlyPrice',
          period: '/month',
          badge: null,
          isRecommended: false,
          isSelected: _tabController.index == 1,
          onTap: () {
            setState(() {
              _tabController.animateTo(1);
            });
          },
          pricePerMonth: null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ERROR MESSAGE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KinrelColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: KinrelColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: KinrelColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SUBSCRIBE BUTTON
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSubscribeButton() {
    final isYearly = _tabController.index == 0;
    final amount = isYearly ? _yearlyPrice : _monthlyPrice;
    final planLabel = isYearly ? 'yearly' : 'monthly';

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [KinrelColors.orange, KinrelColors.amber],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isProcessing ? null : () => _handleSubscribe(amount, planLabel),
          child: Center(
            child: _isProcessing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'Subscribe for ₹${amount.toInt()}/${isYearly ? 'year' : 'month'}',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 300.ms);
  }

  // ═══════════════════════════════════════════════════════════════════
  // TERMS TEXT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTermsText() {
    return Text(
      'Cancel anytime. Payment charged to your Google Play / Apple ID account. '
      'Subscription auto-renews unless cancelled 24 hours before the end of the period.',
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 10,
        color: KinrelColors.textDim,
        height: 1.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PAYMENT HANDLING
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _handleSubscribe(double amount, String planLabel) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Track payment attempt
      AnalyticsService.instance.logPaymentAttempted(amount);
      AnalyticsService.instance.logSubscriptionStarted(planLabel);

      // ── Razorpay Integration ────────────────────────────────────
      // In production, this would open the Razorpay payment sheet:
      //
      // import 'package:razorpay_flutter/razorpay_flutter.dart';
      //
      // final razorpay = Razorpay();
      // razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      // razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      //
      // var options = {
      //   'key': 'rzp_live_xxxxxxxx',
      //   'amount': (amount * 100).toInt(), // amount in paise
      //   'name': 'Daxelo Kinrel',
      //   'description': 'Kinrel Premium - $planLabel',
      //   'prefill': {'contact': '', 'email': ''},
      //   'theme': {'color': '#E8612A'},
      // };
      // razorpay.open(options);

      // For now, simulate a successful payment (replace with real Razorpay)
      await Future.delayed(const Duration(seconds: 2));

      // On payment success
      await PremiumService.setPremium(true);

      // Calculate expiry
      final isYearly = planLabel == 'yearly';
      final expiry = DateTime.now().add(
        isYearly ? const Duration(days: 365) : const Duration(days: 30),
      );
      await PremiumService.setPremiumExpiry(expiry);

      // Track success
      AnalyticsService.instance.logPaymentSuccess(amount);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome to Kinrel Premium! 🧡'),
            backgroundColor: KinrelColors.success,
            duration: Duration(seconds: 3),
          ),
        );
        context.pop();
      }
    } on PlatformException catch (e, st) {
      logError(e, st, reason: 'Payment failed');
      setState(() {
        _errorMessage = 'Payment failed: ${e.message ?? 'Unknown error'}';
      });
    } catch (e, st) {
      logError(e, st, reason: 'Payment failed');
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PLAN CARD
// ═══════════════════════════════════════════════════════════════════════

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.period,
    required this.badge,
    required this.isRecommended,
    required this.isSelected,
    required this.onTap,
    this.pricePerMonth,
  });

  final String title;
  final String price;
  final String period;
  final String? badge;
  final bool isRecommended;
  final bool isSelected;
  final VoidCallback onTap;
  final String? pricePerMonth;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? KinrelColors.orange.withValues(alpha: 0.6)
        : KinrelColors.darkSurface.withValues(alpha: 0.6);

    final glowColor = isSelected
        ? KinrelColors.orange.withValues(alpha: 0.08)
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: glowColor,
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? KinrelColors.orange
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? KinrelColors.orange
                      : KinrelColors.textDim,
                  width: isSelected ? 6 : 1.5,
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Plan info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? KinrelColors.orange
                              : KinrelColors.textWhite,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: KinrelColors.success.withValues(alpha: 0.12),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.success,
                            ),
                          ),
                        ),
                      ],
                      if (isRecommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: KinrelColors.orange.withValues(alpha: 0.12),
                          ),
                          child: const Text(
                            'Best Value',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (pricePerMonth != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      pricePerMonth!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Price
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: price,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? KinrelColors.orange
                          : KinrelColors.textWhite,
                    ),
                  ),
                  TextSpan(
                    text: period,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
