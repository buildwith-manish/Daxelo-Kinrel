// lib/features/games/night_falls/night_falls_card.dart
//
// Night Falls — preview card for the Family Detail / Games hub screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class NightFallsCard extends ConsumerStatefulWidget {
  const NightFallsCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<NightFallsCard> createState() => _NightFallsCardState();
}

class _NightFallsCardState extends ConsumerState<NightFallsCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('night-falls').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('night-falls'));

    // Indigo accent — evokes the "night" theme.
    const accent = Color(0xFF6366F1);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.15), const Color(0xFF191B2C)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (dlState.status != GameDownloadStatus.downloaded) {
              context.push('/games?familyId=${widget.familyId}');
              return;
            }
            context.push('/family/${widget.familyId}/night-falls/lobby');
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(
                    painter: _NightFallsMoonPainter(accent: accent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Night Falls',
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '5–12',
                              style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Social deduction · Classic Werewolf',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (dlState.status !=
                          GameDownloadStatus.downloaded)
                        Text(
                          'Download in Games hub to play',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.textDim
                                .withValues(alpha: 0.7),
                          ),
                        )
                      else
                        Text(
                          'Wolves hunt by night, village votes by day. Find the wolves before they outnumber you!',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.textDim,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter that renders a crescent moon with a star — the night
/// motif for Night Falls, without cartoon artwork.
class _NightFallsMoonPainter extends CustomPainter {
  _NightFallsMoonPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Outer rounded-rect background ──
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 4, w - 4, h - 8),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = const Color(0xFF191B2C)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = accent.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // ── Crescent moon ──
    final moonCenter = Offset(w * 0.5, h * 0.45);
    final moonRadius = w * 0.22;

    // Full moon (filled with indigo gradient)
    canvas.drawCircle(
      moonCenter,
      moonRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            const Color(0xFFA5B4FC),
            accent,
          ],
        ).createShader(Rect.fromCircle(
            center: moonCenter, radius: moonRadius)),
    );

    // "Bite" — subtract a circle offset to create crescent
    canvas.drawCircle(
      Offset(moonCenter.dx + moonRadius * 0.45, moonCenter.dy - moonRadius * 0.2),
      moonRadius * 0.85,
      Paint()
        ..color = const Color(0xFF191B2C)
        ..style = PaintingStyle.fill,
    );

    // ── Small stars ──
    final starPaint = Paint()..color = const Color(0xFFFCD34D);
    // Star 1 (top-right)
    _drawStar(canvas, Offset(w * 0.78, h * 0.28), 2.0, starPaint);
    // Star 2 (bottom-left)
    _drawStar(canvas, Offset(w * 0.22, h * 0.72), 1.5, starPaint);
    // Star 3 (bottom-right, tiny)
    _drawStar(canvas, Offset(w * 0.75, h * 0.7), 1.2,
        Paint()..color = accent.withValues(alpha: 0.8));
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    // Simple 4-point sparkle: two crossed lines + center dot
    canvas.drawCircle(center, radius * 0.6, paint);
    canvas.drawLine(
      Offset(center.dx - radius * 1.8, center.dy),
      Offset(center.dx + radius * 1.8, center.dy),
      paint..strokeWidth = radius * 0.5,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 1.8),
      Offset(center.dx, center.dy + radius * 1.8),
      paint..strokeWidth = radius * 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
