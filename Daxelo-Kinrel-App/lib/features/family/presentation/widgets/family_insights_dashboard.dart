// lib/features/family/presentation/widgets/family_insights_dashboard.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  FAMILY INSIGHTS DASHBOARD — "Your family spans 3 generations"       │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Users build a family tree but never get a summary of what they've
// accomplished. This card surfaces pride-worthy stats:
//   - Generations, members, relationships (headline)
//   - Age range (oldest to youngest)
//   - Completeness bar (Zeigarnik Effect)
//   - A share button (organic growth)
//
// Gated behind premium (soft paywall) — free users see a preview with
// a "Premium" badge, tapping opens the paywall.
//
// PSYCHOLOGICAL PRINCIPLE: PROGRESS VISUALIZATION + SOCIAL CURRENCY
// ─────────────────────────────────────────────────────────────────────
//   • Progress Visualization: seeing "47 members, 3 generations" makes
//     the user's effort tangible — drives continued engagement.
//   • Social Currency: sharing "My family spans 3 generations" makes
//     the sharer look proud + drives app installs (organic growth).
//   • Zeigarnik Effect: the completeness bar creates a pull to finish
//     the missing profile fields.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/family/family_insights_service.dart';
import '../../../../core/family/family_provider.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/services/premium_service.dart';
import '../../../../shared/widgets/paywall_sheet.dart';
import '../../../../features/kinrel_intelligence/widgets/share_download_stub.dart'
    if (dart.library.html) '../../../../features/kinrel_intelligence/widgets/share_download_web.dart'
    as web_download;

/// A card showing aggregated family insights with a share button.
///
/// Gated behind premium — free users see a locked preview.
class FamilyInsightsDashboard extends StatefulWidget {
  const FamilyInsightsDashboard({
    super.key,
    required this.familyDetail,
  });

  final FamilyDetail familyDetail;

  @override
  State<FamilyInsightsDashboard> createState() =>
      _FamilyInsightsDashboardState();
}

class _FamilyInsightsDashboardState extends State<FamilyInsightsDashboard> {
  final GlobalKey _shareCardKey = GlobalKey();
  bool _isPremium = false;
  bool _checkedPremium = false;

  @override
  void initState() {
    super.initState();
    _checkPremium();
  }

  Future<void> _checkPremium() async {
    final canView = await PremiumService.canViewInsights();
    if (mounted) {
      setState(() {
        _isPremium = canView;
        _checkedPremium = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedPremium) return const SizedBox.shrink();

    final insights = FamilyInsightsService.compute(widget.familyDetail);

    // Free users see a locked preview — the card is visible but blurred
    // with a "Premium" badge overlay. Tapping opens the paywall.
    if (!_isPremium) {
      return _buildLockedPreview(insights);
    }

    return _buildUnlockedCard(insights);
  }

  /// The locked preview — shows the card blurred with a Premium badge.
  Widget _buildLockedPreview(FamilyInsights insights) {
    return GestureDetector(
      onTap: () {
        HapticService.tap();
        PaywallSheet.show(
          context: context,
          trigger: PaywallTrigger.featureLocked,
          featureName: 'Family Insights',
        );
      },
      child: Stack(
        children: [
          // Blurred card preview
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Opacity(
              opacity: 0.5,
              child: _buildCardContent(insights),
            ),
          ),
          // Premium badge overlay
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'PREMIUM',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Centered "Unlock" prompt
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, color: KinrelColors.orange, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    'Unlock Family Insights',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to upgrade',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The full unlocked card with share button.
  Widget _buildUnlockedCard(FamilyInsights insights) {
    return RepaintBoundary(
      key: _shareCardKey,
      child: _buildCardContent(insights, showShareButton: true),
    );
  }

  Widget _buildCardContent(FamilyInsights insights, {bool showShareButton = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF13141E), Color(0xFF1A1B2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.insights_rounded, color: KinrelColors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Family Insights',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const Spacer(),
              if (showShareButton)
                GestureDetector(
                  onTap: _captureAndShare,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.ios_share_rounded,
                      color: KinrelColors.orange,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Pride summary ──────────────────────────────────────────
          Text(
            insights.prideSummary,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // ── Stat grid ──────────────────────────────────────────────
          Row(
            children: [
              _StatChip(
                icon: Icons.people_outline,
                label: 'Members',
                value: '${insights.memberCount}',
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.account_tree_outlined,
                label: 'Generations',
                value: '${insights.generationCount}',
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.link_rounded,
                label: 'Links',
                value: '${insights.relationshipCount}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Completeness bar (Zeigarnik Effect) ────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Tree completeness',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${insights.completenessPercent}%',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: insights.completenessPercent / 100,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(KinrelColors.orange),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
  }

  Future<void> _captureAndShare() async {
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      HapticService.tap();
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final filename =
          'kinrel-insights-${DateTime.now().millisecondsSinceEpoch}.png';

      HapticService.success();
      if (Theme.of(context).platform == TargetPlatform.android ||
          Theme.of(context).platform == TargetPlatform.iOS) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: filename, mimeType: 'image/png')],
          text: 'My family on Kinrel: ${FamilyInsightsService.compute(widget.familyDetail).headline}',
        );
      } else {
        web_download.downloadPngOnWeb(bytes, filename);
      }
    } catch (e) {
      HapticService.error();
    }
  }
}

/// A small stat chip: icon + label + value.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: KinrelColors.orange, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                color: KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
