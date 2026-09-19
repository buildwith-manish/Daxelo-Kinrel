// lib/features/games/mind_match/mind_match_card.dart
//
// Mind Match — preview card for the Family Detail / Games hub screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class MindMatchCard extends ConsumerStatefulWidget {
  const MindMatchCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<MindMatchCard> createState() => _MindMatchCardState();
}

class _MindMatchCardState extends ConsumerState<MindMatchCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('mind-match').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('mind-match'));

    // Pink accent — evokes the "mind reading" / social theme.
    const accent = Color(0xFFF472B6);

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
            context.push('/family/${widget.familyId}/mind-match/lobby');
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
                    painter: _MindMatchMotifPainter(accent: accent),
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
                              'Mind Match',
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
                        'Social party · Think like everyone else',
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
                          'Match answers with family — most popular wins. Perfect matches = big bonuses!',
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

/// Custom painter that renders a "mind reading" motif — two overlapping
/// thought-bubble circles connected by dots, evoking the social/thinking
/// theme without cartoon artwork.
class _MindMatchMotifPainter extends CustomPainter {
  _MindMatchMotifPainter({required this.accent});
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

    // ── Two overlapping thought bubbles ──
    final leftCenter = Offset(w * 0.38, h * 0.42);
    final rightCenter = Offset(w * 0.62, h * 0.58);
    final bubbleRadius = w * 0.18;

    // Left bubble (filled)
    canvas.drawCircle(
      leftCenter,
      bubbleRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.55),
          ],
        ).createShader(Rect.fromCircle(
            center: leftCenter, radius: bubbleRadius)),
    );

    // Right bubble (filled — slightly different shade)
    canvas.drawCircle(
      rightCenter,
      bubbleRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: const [
            Color(0xFFFCD34D),
            Color(0xFFB45309),
          ],
        ).createShader(Rect.fromCircle(
            center: rightCenter, radius: bubbleRadius)),
    );

    // ── Three small connecting dots between the bubbles ──
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.7);
    final dotRadius = 1.5;
    for (var i = 0; i < 3; i++) {
      final t = (i + 1) / 4;
      final dx = leftCenter.dx + (rightCenter.dx - leftCenter.dx) * t;
      final dy = leftCenter.dy + (rightCenter.dy - leftCenter.dy) * t;
      canvas.drawCircle(Offset(dx, dy), dotRadius, dotPaint);
    }

    // ── Small "match" checkmark in the center overlap area ──
    // (Skip — the two bubbles are enough visual signal.)
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
