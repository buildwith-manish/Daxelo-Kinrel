import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/sparq_provider.dart';


/// SparqRingAvatar — avatar with colored ring indicating Sparq status.
///
/// Ring colors:
/// - Orange ring: user has unseen Sparqs
/// - Grey ring: all Sparqs have been seen
/// - No ring: no active Sparqs
class SparqRingAvatar extends ConsumerWidget {
  const SparqRingAvatar({
    super.key,
    required this.userId,
    this.avatarUrl,
    this.radius = 24,
    this.onTap,
    this.child,
  });

  final String userId;
  final String? avatarUrl;
  final double radius;
  final VoidCallback? onTap;

  /// Optional custom child widget. When provided, replaces the default
  /// CircleAvatar so callers can supply their own avatar rendering
  /// (e.g. CachedNetworkImage, upload spinner, camera overlay).
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sparqState = ref.watch(sparqProvider);
    final userGroup = sparqState.feed.where((g) => g.userId == userId).firstOrNull;

    // Determine ring state
    final hasSparqs = userGroup != null && userGroup.hasActiveSparqs;
    final allSeen = userGroup?.allSeen ?? true;

    Color? ringColor;
    double ringWidth = 0;
    if (hasSparqs && !allSeen) {
      ringColor = KinrelColors.orange; // Unseen Sparqs
      ringWidth = 3.0;
    } else if (hasSparqs && allSeen) {
      ringColor = KinrelColors.textSilver.withValues(alpha: 0.4); // All seen
      ringWidth = 2.0;
    }

    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: ringColor != null
            ? _RingPainter(
                ringColor: ringColor,
                ringWidth: ringWidth,
                gap: 2.0,
              )
            : null,
        child: Padding(
          padding: ringColor != null
              ? EdgeInsets.all(ringWidth + 2.0)
              : EdgeInsets.zero,
          child: child ?? CircleAvatar(
            radius: radius,
            backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                ? NetworkImage(avatarUrl!)
                : null,
            backgroundColor: KinrelColors.elevation2,
            child: avatarUrl == null || avatarUrl!.isEmpty
                ? Icon(Icons.person, size: radius, color: KinrelColors.textSilver)
                : null,
          ),
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

  _RingPainter({
    required this.ringColor,
    required this.ringWidth,
    required this.gap,
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

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return ringColor != oldDelegate.ringColor || ringWidth != oldDelegate.ringWidth;
  }
}
