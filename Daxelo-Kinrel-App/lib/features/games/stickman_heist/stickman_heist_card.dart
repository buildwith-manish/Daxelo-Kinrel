// lib/features/games/stickman_heist/stickman_heist_card.dart
//
// Stickman Heist — preview card for the Family Detail / Games hub screen.
//
// Red accent (#EF4444) — evokes the high-stakes heist / shooter theme.
// Custom painter renders a diamond (treasure) motif overlapping a
// stickman silhouette, so the card reads instantly even at a glance.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class StickmanHeistCard extends ConsumerStatefulWidget {
  const StickmanHeistCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<StickmanHeistCard> createState() =>
      _StickmanHeistCardState();
}

class _StickmanHeistCardState extends ConsumerState<StickmanHeistCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('stickman-heist').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('stickman-heist'));

    // Red accent — high-stakes heist theme.
    const accent = Color(0xFFEF4444);

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
            context.push('/family/${widget.familyId}/stickman-heist/lobby');
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
                    painter: _HeistMotifPainter(accent: accent),
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
                              'Stickman Heist',
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
                              '2–8',
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
                        'Treasure hunt shooter',
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
                          'Find the treasure, hold it, escape. Hunt the carrier — drop the loot!',
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

/// Custom painter that renders the Stickman Heist motif: a stickman
/// silhouette with a treasure diamond floating above (its head). The
/// diamond has a subtle gold gradient to evoke the heist treasure.
class _HeistMotifPainter extends CustomPainter {
  _HeistMotifPainter({required this.accent});
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

    // ── Stickman silhouette (centered) ──
    final cx = w * 0.5;
    final headY = h * 0.62;
    final headR = w * 0.13;
    final bodyTopY = headY + headR;
    final bodyBottomY = h * 0.92;
    final legSpread = w * 0.13;
    final armSpread = w * 0.18;

    final strokePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // Head
    canvas.drawCircle(
      Offset(cx, headY),
      headR,
      strokePaint,
    );
    // Body line
    canvas.drawLine(
      Offset(cx, bodyTopY),
      Offset(cx, bodyBottomY),
      strokePaint,
    );
    // Arms (slightly raised, heist-style)
    canvas.drawLine(
      Offset(cx, bodyTopY + (bodyBottomY - bodyTopY) * 0.25),
      Offset(cx - armSpread, bodyTopY + (bodyBottomY - bodyTopY) * 0.05),
      strokePaint,
    );
    canvas.drawLine(
      Offset(cx, bodyTopY + (bodyBottomY - bodyTopY) * 0.25),
      Offset(cx + armSpread, bodyTopY + (bodyBottomY - bodyTopY) * 0.05),
      strokePaint,
    );
    // Legs (spread, running stance)
    canvas.drawLine(
      Offset(cx, bodyBottomY),
      Offset(cx - legSpread, h * 0.98),
      strokePaint,
    );
    canvas.drawLine(
      Offset(cx, bodyBottomY),
      Offset(cx + legSpread, h * 0.98),
      strokePaint,
    );

    // ── Treasure diamond (floating above the stickman's head) ──
    final diamondCenter = Offset(cx, h * 0.22);
    final diamondHalfW = w * 0.15;
    final diamondHalfH = w * 0.12;

    final diamondPath = Path()
      ..moveTo(diamondCenter.dx, diamondCenter.dy - diamondHalfH)
      ..lineTo(diamondCenter.dx + diamondHalfW, diamondCenter.dy)
      ..lineTo(diamondCenter.dx, diamondCenter.dy + diamondHalfH)
      ..lineTo(diamondCenter.dx - diamondHalfW, diamondCenter.dy)
      ..close();

    // Gold gradient fill.
    final diamondPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFFFCD34D),
          Color(0xFFB45309),
        ],
      ).createShader(Rect.fromCircle(
          center: diamondCenter, radius: diamondHalfW * 1.5));
    canvas.drawPath(diamondPath, diamondPaint);

    // Diamond rim.
    canvas.drawPath(
      diamondPath,
      Paint()
        ..color = const Color(0xFFFCD34D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // ── Small accent dots around the diamond (sparkle) ──
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.7);
    canvas.drawCircle(
        Offset(diamondCenter.dx - diamondHalfW - 3,
            diamondCenter.dy - diamondHalfH + 2),
        1.2,
        dotPaint);
    canvas.drawCircle(
        Offset(diamondCenter.dx + diamondHalfW + 3,
            diamondCenter.dy + diamondHalfH - 2),
        1.2,
        dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
