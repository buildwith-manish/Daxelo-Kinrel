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
import '../../../kinrel_intelligence/data/kinrel_model.dart';
import '../../../kinrel_intelligence/providers/kinrel_provider.dart';
import '../../../kinrel_intelligence/widgets/kinrel_symbol_widget.dart';
import '../../../truth_streak/providers/truth_streak_provider.dart';
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
    this.avatarUrl,
    this.onAvatarTap,
    this.onAvatarLongPress,
  });

  final String familyId;
  final String familyName;
  final int memberCount;
  final int relationshipCount;

  /// Current scroll offset (0–200) for the parallax collapse effect.
  /// 0 = fully expanded hero. 200 = fully collapsed into a pinned bar.
  final double scrollOffset;

  /// v118: The family's profile picture URL (from Family.avatarUrl).
  /// When non-null, the hero avatar renders the image instead of the
  /// Kinrel symbol / initial fallback.
  final String? avatarUrl;

  /// v118: Called when the user taps the family avatar. If null, the
  /// avatar is not tappable. Wired by family_detail_screen to open a
  /// role-based menu (admin/edit) or full-screen viewer (regular).
  final VoidCallback? onAvatarTap;

  /// v118: Called when the user long-presses the family avatar.
  /// Same role-based behaviour as onAvatarTap.
  final VoidCallback? onAvatarLongPress;

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

            // ── Layer 2 (v108): Graph + Map shortcuts flanking the avatar ──
            // Two large, faint, semi-transparent icons positioned on the
            // left and right of the centered profile icon (the family
            // initial / Kinrel symbol). Left = Graph, right = Map. They
            // are subtle background design elements (not separate buttons
            // or labels) that double as tap targets.
            //
            // The whole-hero InkWell that previously opened the Graph is
            // REMOVED — tapping the avatar/name no longer navigates. The
            // two icons are the ONLY Graph/Map entry points in the hero.
            //
            // Icons fade out as the hero collapses (matched to nameOpacity)
            // so they don't clutter the pinned-bar state.
            if (symbolSize > 10)
              Positioned.fill(
                child: Opacity(
                  opacity: nameOpacity,
                  child: Row(
                    children: [
                      // ── LEFT: Graph ────────────────────────────────
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(
                                left: FamilyHubSpace.lg),
                            child: Semantics(
                              button: true,
                              label: 'Open $familyName graph',
                              hint: 'Double tap to open the family graph',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => context.push(
                                  '/family/$familyId/graph?name='
                                  '${Uri.encodeComponent(familyName)}',
                                ),
                                child: Icon(
                                  Icons.account_tree_outlined,
                                  size: 64,
                                  color: KinrelColors.orange
                                      .withValues(alpha: 0.12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ── CENTER spacer (matches the avatar width) ──
                      SizedBox(width: symbolSize),
                      // ── RIGHT: Map ────────────────────────────────
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                                right: FamilyHubSpace.lg),
                            child: Semantics(
                              button: true,
                              label: 'Open $familyName map',
                              hint: 'Double tap to open the family map',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => context.push(
                                  '/family/$familyId/map',
                                ),
                                child: Icon(
                                  Icons.map_outlined,
                                  size: 64,
                                  color: KinrelColors.orange
                                      .withValues(alpha: 0.12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Layer 3: Centered symbol + name ─────────────────────
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Kinrel symbol (or family initial fallback).
                  // v108: The graph-icon badge on the ring is removed —
                  // the Graph + Map icons flanking the avatar now serve
                  // as the tap affordance.
                  if (symbolSize > 10)
                    Opacity(
                      opacity: nameOpacity,
                      child: GestureDetector(
                        onTap: onAvatarTap,
                        onLongPress: onAvatarLongPress,
                        child: _HeroSymbol(
                          kinrel: kinrel,
                          familyName: familyName,
                          size: symbolSize,
                          avatarUrl: avatarUrl,
                        ),
                      ),
                    )
                  else
                    // Collapsed: show a tiny initial circle pinned left.
                    Padding(
                      padding: const EdgeInsets.only(left: FamilyHubSpace.md),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: onAvatarTap,
                          onLongPress: onAvatarLongPress,
                          child: _FamilyInitialAvatar(
                            familyName: familyName,
                            size: 40,
                            avatarUrl: avatarUrl,
                          ),
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
                    // Caption: member count + relationship count.
                    Opacity(
                      opacity: nameOpacity,
                      child: Text(
                        '$memberCount ${memberCount == 1 ? "member" : "members"}'
                        '  ·  '
                        '$relationshipCount ${relationshipCount == 1 ? "link" : "links"}',
                        style: FamilyHubType.caption,
                      ),
                    ),
                    // ── Threshold teaser ───────────────────────────────
                    // Small persistent "next threshold" teaser so the hub
                    // doesn't feel empty on days nothing's happening.
                    if (symbolSize > 10)
                      Opacity(
                        opacity: nameOpacity * 0.8,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _ThresholdTeaser(familyId: familyId),
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
          ],
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
    this.avatarUrl,
  });

  final String familyName;
  final double size;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    // v118: If a family avatar URL is set, render the image in a
    // circular clip instead of the initial-letter fallback.
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            avatarUrl!,
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: (_, __, ___) => _buildInitialFallback(),
          ),
        ),
      );
    }
    return _buildInitialFallback();
  }

  Widget _buildInitialFallback() {
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

/// The Kinrel symbol (or family-initial fallback), WITHOUT the graph-icon
/// badge that used to sit on the ring.
///
/// v108: The graph-icon badge was removed because the Graph + Map shortcuts
/// now flank the avatar as separate semi-transparent icons (see Layer 2
/// in HeroSection.build). The badge would have been redundant with the
/// left-side Graph icon.
class _HeroSymbol extends StatelessWidget {
  const _HeroSymbol({
    required this.kinrel,
    required this.familyName,
    required this.size,
    this.avatarUrl,
  });

  final KinrelModel? kinrel;
  final String familyName;
  final double size;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    // v118: If a family avatar URL is set, render the image instead
    // of the Kinrel symbol / initial fallback. The image takes
    // priority so a custom family photo always shows when set.
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return _FamilyInitialAvatar(
        familyName: familyName,
        size: size,
        avatarUrl: avatarUrl,
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: kinrel != null
          ? StaticKinrelSymbol(
              parameters: kinrel!.symbol,
              archetypeKey: kinrel!.archetype.key,
              size: size,
            )
          : _FamilyInitialAvatar(
              familyName: familyName,
              size: size,
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// THRESHOLD TEASER
// Small persistent "next threshold" teaser on the Hero section so
// the hub doesn't feel empty on days nothing's happening.
// Shows the next Truth Streak threshold with a progress bar.
// ═══════════════════════════════════════════════════════════════════════

class _ThresholdTeaser extends ConsumerWidget {
  const _ThresholdTeaser({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(truthStreakProvider(familyId));
    final stats = streak.stats;

    if (stats == null) return const SizedBox.shrink();

    final current = stats.currentStreak;
    final nextThreshold = _getNextThreshold(current);
    if (nextThreshold == null) return const SizedBox.shrink();

    final progress = (current / nextThreshold).clamp(0.0, 1.0);
    final daysLeft = nextThreshold - current;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: KinrelColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔥', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Text(
                daysLeft > 0
                    ? '$daysLeft day${daysLeft == 1 ? '' : 's'} to $nextThreshold-day streak'
                    : 'New threshold unlocked!',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.orange,
                ),
              ),
              const SizedBox(width: 8),
              // Mini progress bar
              SizedBox(
                width: 40,
                height: 4,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(KinrelColors.orange),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
  }

  int? _getNextThreshold(int current) {
    const thresholds = [3, 7, 14, 30, 60, 90, 180, 365];
    for (final t in thresholds) {
      if (current < t) return t;
    }
    return null; // Past all thresholds
  }
}
