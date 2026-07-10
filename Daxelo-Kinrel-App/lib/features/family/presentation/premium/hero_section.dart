// lib/features/family/presentation/premium/hero_section.dart
//
// DAXELO KINREL — Hero Section (Family Hub)
//
// Replaces the old _FeedHeader + _GraphPreviewCard with a single hero:
//   • Faint animated mandala/yantra background derived from the
//     family's own Kinrel symbol parameters — every family's hero is
//     uniquely theirs.
//   • Kinrel symbol large and centered (or family initial fallback when
//     Kinrel hasn't been computed yet).
//   • Family name in Display type (32px) below the symbol.
//   • Member + relationship count as a single Caption line — this
//     folds the old "Family Graph" card's data into the hero. The
//     graph itself is one tap away (the whole hero is tappable),
//     not a preview teaser competing for scroll space.
//   • Parallax collapse: as the user scrolls down, the hero shrinks
//     and fades into a pinned header (iOS large-title collapse feel).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/family/family_provider.dart';
import '../../../kinrel_intelligence/data/kinrel_model.dart';
import '../../../kinrel_intelligence/providers/kinrel_provider.dart';
import '../../../kinrel_intelligence/widgets/kinrel_symbol_widget.dart';
import 'design_system.dart';
import 'mandala_painter.dart';

/// The hero section. Place inside a SliverToBoxAdapter in the main
/// CustomScrollView. The [scrollOffset] parameter drives the parallax
/// collapse — pass the scroll controller's offset clamped to [0, 200].
class HeroSection extends ConsumerWidget {
  const HeroSection({
    super.key,
    required this.familyId,
    required this.familyName,
    required this.memberCount,
    required this.relationshipCount,
    this.scrollOffset = 0,
  });

  final String familyId;
  final String familyName;
  final int memberCount;
  final int relationshipCount;

  /// Current scroll offset (0–200) for the parallax collapse effect.
  /// 0 = fully expanded hero. 200 = fully collapsed into a pinned bar.
  final double scrollOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kinrelState = ref.watch(kinrelProvider(familyId));
    final kinrel = kinrelState.kinrel;

    // Collapse progress: 0 = expanded, 1 = collapsed.
    final collapse = (scrollOffset / 200).clamp(0.0, 1.0);

    // Hero height: 280 expanded → 80 collapsed.
    final heroHeight = 280 - (collapse * 200);

    // Symbol size: 140 expanded → 0 (hidden) collapsed.
    final symbolSize = (140 * (1 - collapse)).clamp(0.0, 140.0);

    // Name opacity: 1 expanded → 0 collapsed (in the hero position).
    final nameOpacity = 1.0 - collapse;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(
          '/family/$familyId/graph?name=${Uri.encodeComponent(familyName)}',
        ),
        borderRadius: BorderRadius.circular(0),
        splashColor: KinrelColors.orange.withValues(alpha: 0.08),
        highlightColor: KinrelColors.orange.withValues(alpha: 0.04),
        child: Container(
          height: heroHeight,
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                KinrelColors.darkCard,
                KinrelColors.darkBackground,
              ],
              stops: [0.0, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // ── Layer 1: Animated mandala background ────────────────
              // Faint (6% opacity), breathing slowly behind the avatar.
              // Derived from the family's Kinrel symbol parameters so every
              // family's hero is uniquely theirs.
              if (kinrel != null)
                Positioned.fill(
                  child: _BreathingMandala(
                    parameters: kinrel.symbol,
                  ),
                )
              else
                // Fallback: static concentric rings when Kinrel not computed.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StaticHeroBackground(),
                  ),
                ),

              // ── Layer 2: Centered symbol + name ─────────────────────
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Kinrel symbol (or family initial fallback) with a
                    // persistent graph-icon badge on the ring so the
                    // tap target is obvious without reading caption text.
                    if (symbolSize > 10)
                      Opacity(
                        opacity: nameOpacity,
                        child: _HeroSymbolWithGraphBadge(
                          kinrel: kinrel,
                          familyName: familyName,
                          size: symbolSize,
                        ),
                      )
                    else
                      // Collapsed: show a tiny initial circle pinned left.
                      Padding(
                        padding: const EdgeInsets.only(left: FamilyHubSpace.md),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _FamilyInitialAvatar(
                            familyName: familyName,
                            size: 40,
                          ),
                        ),
                      ),

                    if (symbolSize > 10) ...[
                      const SizedBox(height: FamilyHubSpace.md),
                      // Family name — Display type
                      Opacity(
                        opacity: nameOpacity,
                        child: Text(
                          familyName,
                          style: FamilyHubType.display,
                          textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: FamilyHubSpace.xs),
                    // Caption: member count + relationship count (folds
                    // the old "Family Graph" card data into the hero).
                    Opacity(
                      opacity: nameOpacity,
                      child: Text(
                        '$memberCount ${memberCount == 1 ? "member" : "members"}'
                        '  ·  '
                        '$relationshipCount ${relationshipCount == 1 ? "link" : "links"}',
                        style: FamilyHubType.caption,
                      ),
                    ),
                  ] else ...[
                    // Collapsed: show family name + caption inline.
                    Padding(
                      padding: const EdgeInsets.only(
                        left: FamilyHubSpace.md + 48,
                        right: FamilyHubSpace.md,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              familyName,
                              style: FamilyHubType.heading,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$memberCount ${memberCount == 1 ? "member" : "members"}'
                              '  ·  '
                              '$relationshipCount ${relationshipCount == 1 ? "link" : "links"}',
                              style: FamilyHubType.captionMuted,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Layer 3: "Explore graph" hint with chevron (expanded only) ─
            // Bug 2 fix: paired with the persistent graph-icon badge on
            // the avatar ring, this caption confirms the tap target.
            // The chevron reinforces "this opens something".
            if (collapse < 0.3)
              Positioned(
                bottom: FamilyHubSpace.md,
                right: FamilyHubSpace.md,
                child: Opacity(
                  opacity: (1 - collapse / 0.3) * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Explore graph',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.orange.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: KinrelColors.orange.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// A slowly breathing mandala background. Uses a 6-second animation
/// cycle (slower than the main Kinrel symbol's 2–6s pulse) so the hero
/// feels calm and meditative.
class _BreathingMandala extends StatefulWidget {
  const _BreathingMandala({required this.parameters});

  final KinrelSymbolParameters parameters;

  @override
  State<_BreathingMandala> createState() => _BreathingMandalaState();
}

class _BreathingMandalaState extends State<_BreathingMandala>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BreathingMandala oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parameters.pulseSpeedMs != widget.parameters.pulseSpeedMs) {
      _controller.duration =
          Duration(milliseconds: widget.parameters.pulseSpeedMs * 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return CustomPaint(
          painter: MandalaPainter(
            parameters: widget.parameters,
            progress: t,
            opacity: 0.06,
          ),
        );
      },
    );
  }
}

/// Static concentric-ring background used when Kinrel hasn't been
/// computed yet. Same visual language as the mandala but with fixed
/// parameters so the hero doesn't look empty on first load.
class _StaticHeroBackground extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2;
    final paint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      canvas.drawCircle(center, maxR * (0.3 + 0.6 * t), paint);
    }

    // Faint spokes
    for (var i = 0; i < 8; i++) {
      final angle = (2 * math.pi * i) / 8;
      canvas.drawLine(
        center,
        Offset(
          center.dx + maxR * 0.85 * math.cos(angle),
          center.dy + maxR * 0.85 * math.sin(angle),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StaticHeroBackground old) => false;
}

/// Family-initial avatar shown when Kinrel hasn't been computed yet.
/// Same size slot as the Kinrel symbol so the hero layout is stable.
class _FamilyInitialAvatar extends StatelessWidget {
  const _FamilyInitialAvatar({
    required this.familyName,
    required this.size,
  });

  final String familyName;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.orange.withValues(alpha: 0.25),
            KinrelColors.amber.withValues(alpha: 0.15),
          ],
        ),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          familyName.isNotEmpty ? familyName[0].toUpperCase() : 'F',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w700,
            color: KinrelColors.orange,
          ),
        ),
      ),
    );
  }
}

/// The Kinrel symbol (or family-initial fallback) wrapped in a Stack with
/// a persistent graph-icon badge on the bottom-right of the ring.
///
/// Bug 2 fix: "Tap to explore graph" as small caption text doesn't read
/// as tappable. This badge sits on the avatar ring itself — the same
/// graph icon used elsewhere in the app — so the tap target is obvious
/// without reading any caption text. The whole hero is already wrapped
/// in a Material+InkWell (ripple feedback), so tapping anywhere on the
/// hero opens the graph.
class _HeroSymbolWithGraphBadge extends StatelessWidget {
  const _HeroSymbolWithGraphBadge({
    required this.kinrel,
    required this.familyName,
    required this.size,
  });

  final KinrelModel? kinrel;
  final String familyName;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Badge size scales with the symbol: 22% of symbol diameter,
    // clamped to 28–44px so it's visible but not overwhelming.
    final badgeSize = (size * 0.28).clamp(28.0, 44.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The Kinrel symbol or family-initial avatar.
          if (kinrel != null)
            StaticKinrelSymbol(
              parameters: kinrel!.symbol,
              archetypeKey: kinrel!.archetype.key,
              size: size,
            )
          else
            _FamilyInitialAvatar(
              familyName: familyName,
              size: size,
            ),

          // Persistent graph-icon badge on the bottom-right of the ring.
          // This is the visual affordance that says "tap me to see the
          // graph" — it doesn't rely on users reading caption text.
          Positioned(
            right: -badgeSize * 0.15,
            bottom: -badgeSize * 0.15,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkBackground,
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Icon(
                Icons.account_tree_outlined,
                size: badgeSize * 0.55,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
