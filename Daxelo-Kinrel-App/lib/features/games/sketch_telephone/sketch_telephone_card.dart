// lib/features/games/sketch_telephone/sketch_telephone_card.dart
//
// Sketch Telephone — preview card for the Family Detail / Games hub screen.
//
// Premium pink accent (matches fn__game_meta). The motif is a "pencil
// + phone" composition: a slanted pencil with a wavy line trailed behind
// it (the prompt traveling through the chain), then a phone handset at
// the end — evoking the "telephone" degradation without cartoon art.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class SketchTelephoneCard extends ConsumerStatefulWidget {
  const SketchTelephoneCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SketchTelephoneCard> createState() =>
      _SketchTelephoneCardState();
}

class _SketchTelephoneCardState extends ConsumerState<SketchTelephoneCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('sketch-telephone').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('sketch-telephone'));

    // Premium pink accent — matches fn__game_meta.
    const accent = Color(0xFFEC4899);

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
            context.push(
                '/family/${widget.familyId}/sketch-telephone/lobby');
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
                    painter: _SketchTelephoneMotifPainter(accent: accent),
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
                              'Sketch Telephone',
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
                              '4–8',
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
                        'Drawing chain · Gartic Phone-style',
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
                          'Write a prompt, draw it, describe the drawing, draw that… then reveal the chaos!',
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

/// Custom painter that renders a "pencil + phone" motif:
///   • A slanted pencil on the left (pink body + ivory tip + dark point)
///   • A wavy line trailing behind it (the prompt traveling through the
///     chain — gets wobblier as it goes, evoking "telephone" degradation)
///   • A small phone handset at the end of the line
///
/// No cartoon artwork — just geometric shapes evoking the game's identity.
class _SketchTelephoneMotifPainter extends CustomPainter {
  _SketchTelephoneMotifPainter({required this.accent});
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

    // ── Pencil (slanted, top-left) ──
    // Pencil body: pink rectangle, tilted -30°.
    canvas.save();
    final pencilCenter = Offset(w * 0.28, h * 0.38);
    canvas.translate(pencilCenter.dx, pencilCenter.dy);
    canvas.rotate(-0.5); // ~ -28°

    // Body
    final bodyPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset.zero, width: w * 0.34, height: h * 0.12),
      bodyPaint,
    );

    // Ivory tip (triangle)
    final tipPaint = Paint()
      ..color = const Color(0xFFFDF4FF)
      ..style = PaintingStyle.fill;
    final tipPath = Path()
      ..moveTo(w * 0.17, -h * 0.06)
      ..lineTo(w * 0.17, h * 0.06)
      ..lineTo(w * 0.24, 0)
      ..close();
    canvas.drawPath(tipPath, tipPaint);

    // Dark point (small triangle at the very tip)
    final pointPaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill;
    final pointPath = Path()
      ..moveTo(w * 0.22, -h * 0.02)
      ..lineTo(w * 0.22, h * 0.02)
      ..lineTo(w * 0.24, 0)
      ..close();
    canvas.drawPath(pointPath, pointPaint);

    // Ferrule (metal band between body and tip)
    final ferrulePaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.15, -h * 0.06, w * 0.03, h * 0.12),
      ferrulePaint,
    );

    canvas.restore();

    // ── Wavy line trailing behind the pencil (telephone chain) ──
    // Goes from below the pencil to the phone handset. The wave gets
    // wobblier as it travels, evoking the "telephone" degradation.
    final wavePaint = Paint()
      ..color = accent.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final wavePath = Path()
      ..moveTo(w * 0.38, h * 0.55)
      ..cubicTo(w * 0.45, h * 0.42, w * 0.50, h * 0.68, w * 0.55, h * 0.55)
      ..cubicTo(w * 0.60, h * 0.45, w * 0.65, h * 0.65, w * 0.70, h * 0.55);
    canvas.drawPath(wavePath, wavePaint);

    // ── Three small dots along the wave (the "chain" links) ──
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.85);
    canvas.drawCircle(Offset(w * 0.44, h * 0.50), 1.4, dotPaint);
    canvas.drawCircle(Offset(w * 0.55, h * 0.55), 1.4, dotPaint);
    canvas.drawCircle(Offset(w * 0.66, h * 0.58), 1.4, dotPaint);

    // ── Phone handset (right side) ──
    // A simple curved handset shape — rotated 90° to look like it's
    // "listening" to the wave.
    final phoneCenter = Offset(w * 0.80, h * 0.55);
    canvas.save();
    canvas.translate(phoneCenter.dx, phoneCenter.dy);
    canvas.rotate(0.35);

    // Handset body — a rounded "C" shape (rect with a notch).
    final phonePaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.fill;
    final phonePath = Path()
      ..moveTo(-w * 0.06, -h * 0.10)
      ..lineTo(w * 0.06, -h * 0.10)
      ..quadraticBezierTo(
          w * 0.10, -h * 0.10, w * 0.10, -h * 0.06)
      ..lineTo(w * 0.10, h * 0.06)
      ..quadraticBezierTo(
          w * 0.10, h * 0.10, w * 0.06, h * 0.10)
      ..lineTo(-w * 0.06, h * 0.10)
      ..quadraticBezierTo(
          -w * 0.10, h * 0.10, -w * 0.10, h * 0.06)
      ..lineTo(-w * 0.10, -h * 0.06)
      ..quadraticBezierTo(
          -w * 0.10, -h * 0.10, -w * 0.06, -h * 0.10)
      ..close();
    canvas.drawPath(phonePath, phonePaint);

    // Earpiece + mouthpiece dots (dark)
    final dotDark = Paint()..color = const Color(0xFF111111);
    canvas.drawCircle(Offset(0, -h * 0.05), 1.2, dotDark);
    canvas.drawCircle(Offset(0, h * 0.05), 1.2, dotDark);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
