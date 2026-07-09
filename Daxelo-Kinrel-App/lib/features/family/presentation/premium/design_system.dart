// lib/features/family/presentation/premium/design_system.dart
//
// DAXELO KINREL — Family Hub Design System
//
// A disciplined 4-size type scale, 8px spacing unit, 2 elevation levels,
// and a single terracotta accent. Everything else (icons included) sits
// on a muted warm-neutral. This is the visual grammar that makes the
// family hub read as "calm premium app" instead of "widget dashboard".
//
// Type scale (exactly 4 sizes — no more inventing sizes per card):
//   Display  32  — family name in hero, Truth Streak question
//   Heading  20  — section titles
//   Body     16  — primary text, card content
//   Caption  13  — metadata, timestamps, stat lines
//
// Spacing unit: 8px. Everything is a multiple (8 / 16 / 24 / 32 / 48).
//
// Elevation: exactly 2 surface levels.
//   Level 0 = the scroll background (KinrelColors.darkBackground).
//   Level 1 = raised cards, reserved ONLY for things the user acts on
//             (Truth Streak input, Games). Stats + activity rows sit
//             flat on Level 0 with a hairline divider, never a box.
//
// Color logic: terracotta/orange (KinrelColors.orange) is the SINGLE
// accent for action + energy (streak, CTA buttons, glyphs). Everything
// else — including icons — goes to KinrelColors.textDim (muted warm-
// neutral). No mixing filled emoji with orange outline icons.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// TYPE SCALE — exactly 4 sizes
// ═══════════════════════════════════════════════════════════════════════

class FamilyHubType {
  FamilyHubType._();

  /// Display 32 — family name in hero, Truth Streak question.
  static const TextStyle display = TextStyle(
    fontFamily: KinrelTypography.displayFont,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: KinrelColors.textWhite,
    height: 1.2,
    letterSpacing: -0.5,
  );

  /// Heading 20 — section titles.
  static const TextStyle heading = TextStyle(
    fontFamily: KinrelTypography.displayFont,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: KinrelColors.textWhite,
    height: 1.3,
  );

  /// Body 16 — primary text, card content.
  static const TextStyle body = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: KinrelColors.textSilver,
    height: 1.45,
  );

  /// Caption 13 — metadata, timestamps, stat lines.
  static const TextStyle caption = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: KinrelColors.textDim,
    height: 1.4,
  );

  /// Caption muted — for secondary metadata under a caption.
  static const TextStyle captionMuted = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: KinrelColors.textDim,
    height: 1.4,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// SPACING — 8px base unit, multiples only
// ═══════════════════════════════════════════════════════════════════════

class FamilyHubSpace {
  FamilyHubSpace._();

  static const double xs = 4; // half-unit for tight icon gaps
  static const double sm = 8; // base unit
  static const double md = 16; // 2×
  static const double lg = 24; // 3×
  static const double xl = 32; // 4×
  static const double xxl = 48; // 6× — section spacing
}

// ═══════════════════════════════════════════════════════════════════════
// ELEVATION — exactly 2 surface levels
// ═══════════════════════════════════════════════════════════════════════

class FamilyHubSurface {
  FamilyHubSurface._();

  /// Level 0 — the scroll background. Transparent so the Scaffold's
  /// background (KinrelColors.darkBackground) shows through.
  static const Color level0 = Colors.transparent;

  /// Level 1 — raised cards, reserved ONLY for things the user acts on
  /// (Truth Streak input, Games). Stats + activity rows sit flat on
  /// Level 0 with a hairline divider, never this elevated surface.
  static const Color level1 = KinrelColors.darkCard;

  /// Hairline divider color for separating flat rows on Level 0.
  static Color hairline(BuildContext context) =>
      KinrelColors.textWhite.withValues(alpha: 0.06);

  /// The single accent — terracotta/orange. Used for action, energy,
  /// streaks, CTA buttons, glyphs. Everything else stays muted.
  static const Color accent = KinrelColors.orange;

  /// Muted warm-neutral for icons that aren't the accent. Stops the
  /// "mixing filled emoji with orange outline icons" tell.
  static const Color iconMuted = KinrelColors.textDim;
}

// ═══════════════════════════════════════════════════════════════════════
// KOLAM-DOT SECTION HEADER
//
// A small kolam-dot or rangoli-inspired glyph used as a bullet instead
// of an emoji or generic icon. Same 3-4 glyphs reused everywhere —
// this becomes the app's icon language, rooted in Indian kinship
// geometry rather than copied from iOS patterns.
// ═══════════════════════════════════════════════════════════════════════

/// The 3 kolam glyph variants — pick one per section, reuse throughout.
enum KolamGlyph {
  /// 6-petal lotus dot — for "moment" sections (Truth Streak).
  lotus,

  /// 4-dot quadrant — for "play" sections (Games).
  quadrant,

  /// 8-dot spiral — for "pulse" sections (activity, calendar).
  spiral,
}

/// A section header with a kolam-dot glyph bullet + heading text,
/// on a single line. No bordered box — just type + glyph + spacing.
class KolamSectionHeader extends StatelessWidget {
  const KolamSectionHeader({
    super.key,
    required this.glyph,
    required this.title,
    this.trailing,
  });

  final KolamGlyph glyph;
  final String title;
  final Widget? trailing; // optional "View All" / toggle on the right

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FamilyHubSpace.md,
        vertical: FamilyHubSpace.sm,
      ),
      child: Row(
        children: [
          KolamDot(glyph: glyph, size: 14),
          const SizedBox(width: FamilyHubSpace.sm),
          Text(title, style: FamilyHubType.heading),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Renders a single kolam-dot glyph at the given size + color.
/// Defaults to the muted warm-neutral so it reads as a quiet bullet,
/// not a loud icon. Pass [FamilyHubSurface.accent] for the active section.
class KolamDot extends StatelessWidget {
  const KolamDot({
    super.key,
    required this.glyph,
    this.size = 14,
    this.color = FamilyHubSurface.iconMuted,
  });

  final KolamGlyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _KolamDotPainter(glyph: glyph, color: color),
      ),
    );
  }
}

class _KolamDotPainter extends CustomPainter {
  _KolamDotPainter({required this.glyph, required this.color});

  final KolamGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final dotR = r * 0.22; // individual dot radius

    switch (glyph) {
      case KolamGlyph.lotus:
        // 6-petal lotus: center dot + 6 surrounding dots
        canvas.drawCircle(center, dotR, paint);
        for (var i = 0; i < 6; i++) {
          final angle = (2 * math.pi * i) / 6;
          canvas.drawCircle(
            Offset(
              center.dx + r * 0.7 * math.cos(angle),
              center.dy + r * 0.7 * math.sin(angle),
            ),
            dotR * 0.8,
            paint,
          );
        }
        break;
      case KolamGlyph.quadrant:
        // 4-dot quadrant: 4 dots in a square + center
        canvas.drawCircle(center, dotR * 0.9, paint);
        for (final sign in [
          [-1, -1],
          [1, -1],
          [-1, 1],
          [1, 1],
        ]) {
          canvas.drawCircle(
            Offset(
              center.dx + r * 0.55 * sign[0],
              center.dy + r * 0.55 * sign[1],
            ),
            dotR,
            paint,
          );
        }
        break;
      case KolamGlyph.spiral:
        // 8-dot spiral: 8 dots arranged in a loose spiral
        for (var i = 0; i < 8; i++) {
          final t = i / 8;
          final angle = t * 2 * math.pi * 1.5;
          final radius = r * (0.3 + t * 0.6);
          canvas.drawCircle(
            Offset(
              center.dx + radius * math.cos(angle),
              center.dy + radius * math.sin(angle),
            ),
            dotR * (0.6 + t * 0.4),
            paint,
          );
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _KolamDotPainter old) =>
      old.glyph != glyph || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════
// SKELETON LOADER
//
// Shimmer-based skeleton for loading states. Replaces error text —
// "Couldn't load active games" reads cheap. A shimmer placeholder
// while loading, and a designed empty-state when genuinely empty, is
// a big perceived-quality jump for near-zero engineering cost.
// ═══════════════════════════════════════════════════════════════════════

/// A simple shimmer-animated container. Wrap it around child widgets
/// (or use it bare for a blank skeleton block).
class FamilyHubSkeleton extends StatefulWidget {
  const FamilyHubSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 4,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<FamilyHubSkeleton> createState() => _FamilyHubSkeletonState();
}

class _FamilyHubSkeletonState extends State<FamilyHubSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmer = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        // Opacity oscillates between 0.15 and 0.35 — subtle shimmer.
        final opacity = 0.15 + 0.20 * (_shimmer.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: KinrelColors.textWhite.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// A designed empty-state (not a string) — muted icon + caption.
class FamilyHubEmptyState extends StatelessWidget {
  const FamilyHubEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FamilyHubSpace.md,
        vertical: FamilyHubSpace.lg,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 32, color: FamilyHubSurface.iconMuted),
            const SizedBox(height: FamilyHubSpace.sm),
            Text(
              message,
              style: FamilyHubType.captionMuted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
