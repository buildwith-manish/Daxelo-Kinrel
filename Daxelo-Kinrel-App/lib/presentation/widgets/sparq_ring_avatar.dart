// lib/presentation/widgets/sparq_ring_avatar.dart
//
// DAXELO KINREL — Sparq Ring Avatar
//
// Avatar with a ring indicator:
//   • Orange gradient ring = hasUnseen sparqs
//   • Grey ring = all seen
//   • No ring = no sparqs
//
// Uses CustomPainter for the ring. Watches sparqProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../data/repositories/follow_repository.dart';
import '../providers/sparq_provider.dart';

class SparqRingAvatar extends ConsumerWidget {
  const SparqRingAvatar({
    super.key,
    required this.userId,
    this.imageUrl,
    this.initials,
    this.size = 60,
    this.onTap,
  });

  final String userId;
  final String? imageUrl;
  final String? initials;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sparqState = ref.watch(sparqProvider);

    // Find the user's sparq group in the feed
    final group = sparqState.feed.where((g) => g.userId == userId).firstOrNull;
    final hasSparqs = group != null && group.sparqs.isNotEmpty;
    final hasUnseen = group?.hasUnseen ?? false;

    // Determine ring type
    final RingType ringType;
    if (!hasSparqs) {
      ringType = RingType.none;
    } else if (hasUnseen) {
      ringType = RingType.unseen;
    } else {
      ringType = RingType.seen;
    }

    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _SparqRingPainter(
          ringType: ringType,
          ringWidth: 2.5,
          gap: 3,
        ),
        child: Container(
          width: size - 10, // subtract ring + gap
          height: size - 10,
          margin: EdgeInsets.all(5 + 2.5), // gap + ringWidth
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: imageUrl != null
                ? null
                : KinrelColors.orange.withValues(alpha: 0.15),
            image: imageUrl != null
                ? DecorationImage(
                    image: NetworkImage(imageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: imageUrl != null
              ? null
              : Center(
                  child: Text(
                    initials ?? '?',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: (size - 10) * 0.38,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                      height: 1,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

enum RingType { unseen, seen, none }

class _SparqRingPainter extends CustomPainter {
  _SparqRingPainter({
    required this.ringType,
    required this.ringWidth,
    required this.gap,
  });

  final RingType ringType;
  final double ringWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (ringType == RingType.none) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - gap;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    if (ringType == RingType.unseen) {
      // Orange gradient ring
      paint.shader = SweepGradient(
        startAngle: 0.0,
        endAngle: 6.283185307, // 2π
        colors: [
          KinrelColors.orange,
          KinrelColors.amber,
          KinrelColors.orange,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    } else {
      // Grey ring
      paint.color = KinrelColors.textDim.withValues(alpha: 0.4);
    }

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_SparqRingPainter oldDelegate) {
    return oldDelegate.ringType != ringType;
  }
}
