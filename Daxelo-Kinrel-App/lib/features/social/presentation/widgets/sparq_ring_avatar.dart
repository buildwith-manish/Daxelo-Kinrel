import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/sparq_provider.dart';


/// SparqRingAvatar — avatar with colored ring indicating Sparq status.
///
/// Premium dark design:
/// - Unseen: mood-accent colored ring, 2.5px
/// - Fire intensity unseen: red #FF1744, pulsing glow
/// - Calm intensity unseen: blue #5C7AEA, no animation
/// - Time Capsule: dashed gold #D4AF37, 2.5px
/// - Seen: dim grey, 2px, faded
/// - No active sparqs: no ring
class SparqRingAvatar extends ConsumerWidget {
  const SparqRingAvatar({
    super.key,
    required this.userId,
    this.avatarUrl,
    this.radius = 24,
    this.onTap,
    this.child,
    this.intensity,
    this.isTimeCapsule = false,
    this.isSeen = false,
    this.mood,
  });

  final String userId;
  final String? avatarUrl;
  final double radius;
  final VoidCallback? onTap;

  /// Optional custom child widget. When provided, replaces the default
  /// CircleAvatar so callers can supply their own avatar rendering
  /// (e.g. CachedNetworkImage, upload spinner, camera overlay).
  final Widget? child;

  /// Intensity level: 'calm', 'warm', 'fire'. Affects ring color and animation.
  final String? intensity;

  /// Whether this user's sparq is a time capsule.
  final bool isTimeCapsule;

  /// Whether all sparqs have been seen.
  final bool isSeen;

  /// Mood key (happy/hype/love/sad/celebrate/angry). Used for ring color.
  final String? mood;

  // ── Mood accent color helper ──────────────────────────────────────

  Color _getMoodAccent(String? mood) {
    switch (mood) {
      case 'happy': return const Color(0xFFFFB300);
      case 'hype': return const Color(0xFFFF5722);
      case 'love': return const Color(0xFFE91E63);
      case 'sad': return const Color(0xFF5C7AEA);
      case 'celebrate': return const Color(0xFFD4AF37);
      case 'angry': return const Color(0xFFFF1744);
      default: return KinrelColors.orange;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sparqState = ref.watch(sparqProvider);
    final userGroup = sparqState.feed.where((g) => g.userId == userId).firstOrNull;

    // Determine ring state
    final hasSparqs = userGroup != null && userGroup.hasActiveSparqs;
    final seen = isSeen || (userGroup?.allSeen ?? true);

    // Resolve intensity from parameter or latest sparq
    String? resolvedIntensity = intensity;
    if (resolvedIntensity == null && userGroup != null && userGroup.sparqs.isNotEmpty) {
      resolvedIntensity = userGroup.sparqs.first.intensity;
    }

    // Resolve time capsule from parameter or latest sparq
    bool resolvedTimeCapsule = isTimeCapsule;
    if (!resolvedTimeCapsule && userGroup != null && userGroup.sparqs.isNotEmpty) {
      resolvedTimeCapsule = userGroup.sparqs.first.isTimeCapsule;
    }

    // Resolve mood from parameter or latest sparq
    String? resolvedMood = mood;
    if (resolvedMood == null && userGroup != null && userGroup.sparqs.isNotEmpty) {
      resolvedMood = userGroup.sparqs.first.mood;
    }

    Color? ringColor;
    double ringWidth = 0;
    bool pulsing = false;
    bool dashed = false;

    if (hasSparqs && !seen) {
      // Unseen — determine style by intensity/time capsule
      if (resolvedTimeCapsule) {
        // Time Capsule: dashed gold
        ringColor = const Color(0xFFD4AF37);
        ringWidth = 2.5;
        dashed = true;
      } else if (resolvedIntensity == 'fire') {
        // Fire: red, pulsing glow
        ringColor = const Color(0xFFFF1744);
        ringWidth = 2.5;
        pulsing = true;
      } else if (resolvedIntensity == 'calm') {
        // Calm: solid blue, no animation
        ringColor = const Color(0xFF5C7AEA);
        ringWidth = 2.5;
      } else {
        // Warm / default: mood accent color
        ringColor = _getMoodAccent(resolvedMood);
        ringWidth = 2.5;
      }
    } else if (hasSparqs && seen) {
      // Seen: dim, faded
      ringColor = const Color(0xFF333333);
      ringWidth = 2.0;
    }

    final avatarChild = child ?? CircleAvatar(
      radius: radius,
      backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
          ? NetworkImage(avatarUrl!)
          : null,
      backgroundColor: const Color(0xFF1A1A1A),
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Icon(Icons.person, size: radius, color: KinrelColors.textSilver.withValues(alpha: 0.4))
          : null,
    );

    return GestureDetector(
      onTap: onTap,
      child: pulsing
          ? _buildPulsingRing(ringColor!, ringWidth, dashed, avatarChild)
          : CustomPaint(
              painter: ringColor != null
                  ? _RingPainter(
                      ringColor: ringColor,
                      ringWidth: ringWidth,
                      gap: 2.0,
                      dashed: dashed,
                    )
                  : null,
              child: Padding(
                padding: ringColor != null
                    ? EdgeInsets.all(ringWidth + 2.0)
                    : EdgeInsets.zero,
                child: avatarChild,
              ),
            ),
    );
  }

  /// Builds a pulsing glow ring for fire intensity
  Widget _buildPulsingRing(Color ringColor, double ringWidth, bool dashed, Widget avatarChild) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, glowValue, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ringColor.withValues(alpha: 0.2 * glowValue),
                blurRadius: 6 * glowValue,
                spreadRadius: 1.5 * glowValue,
              ),
            ],
          ),
          child: child,
        );
      },
      child: CustomPaint(
        painter: _RingPainter(
          ringColor: ringColor,
          ringWidth: ringWidth,
          gap: 2.0,
          dashed: dashed,
        ),
        child: Padding(
          padding: EdgeInsets.all(ringWidth + 2.0),
          child: avatarChild,
        ),
      ),
    );
  }
}

/// Custom painter for the Sparq ring around avatars
class _RingPainter extends CustomPainter {
  final Color ringColor;
  final double ringWidth;
  final double gap;
  final bool dashed;

  _RingPainter({
    required this.ringColor,
    required this.ringWidth,
    required this.gap,
    this.dashed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - ringWidth) / 2;

    final paint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    if (dashed) {
      _drawDashedCircle(canvas, center, radius, paint);
    } else {
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const dashCount = 12;
    const dashAngle = 3.14159 * 2 / dashCount;
    const sweepAngle = dashAngle * 0.6;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return ringColor != oldDelegate.ringColor ||
        ringWidth != oldDelegate.ringWidth ||
        dashed != oldDelegate.dashed;
  }
}
