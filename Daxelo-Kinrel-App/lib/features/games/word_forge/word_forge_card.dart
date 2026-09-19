// lib/features/games/word_forge/word_forge_card.dart
//
// Word Forge — preview card for the Family Detail / Games hub screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class WordForgeCard extends ConsumerStatefulWidget {
  const WordForgeCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<WordForgeCard> createState() => _WordForgeCardState();
}

class _WordForgeCardState extends ConsumerState<WordForgeCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('word-forge').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('word-forge'));

    // Purple accent — evokes the dictionary / vocabulary / bookish theme.
    const accent = Color(0xFF8B5CF6);

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
            context.push('/family/${widget.familyId}/word-forge/lobby');
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
                    painter: _WordForgeMotifPainter(accent: accent),
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
                              'Word Forge',
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
                              '3–8',
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
                        'Balderdash · Forge fake definitions',
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
                          'Obscure words. Fool your family with fake definitions. Guess the real one!',
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

/// Custom painter that renders a "dictionary / book" motif — an open book
/// with a magnifier, evoking the vocabulary/definition theme.
class _WordForgeMotifPainter extends CustomPainter {
  _WordForgeMotifPainter({required this.accent});
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

    // ── Open book (two pages) ──
    // The spine is a vertical line in the center.
    final spineX = w * 0.5;
    final spineTop = Offset(spineX, h * 0.28);
    final spineBottom = Offset(spineX, h * 0.78);

    // Left page
    final leftPage = Path()
      ..moveTo(w * 0.16, h * 0.34)
      ..quadraticBezierTo(w * 0.32, h * 0.26, spineX, h * 0.28)
      ..lineTo(spineX, h * 0.78)
      ..quadraticBezierTo(w * 0.32, h * 0.80, w * 0.16, h * 0.74)
      ..close();
    canvas.drawPath(
      leftPage,
      Paint()
        ..color = const Color(0xFF2A2D45)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      leftPage,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Right page
    final rightPage = Path()
      ..moveTo(spineX, h * 0.28)
      ..quadraticBezierTo(w * 0.68, h * 0.26, w * 0.84, h * 0.34)
      ..lineTo(w * 0.84, h * 0.74)
      ..quadraticBezierTo(w * 0.68, h * 0.80, spineX, h * 0.78)
      ..close();
    canvas.drawPath(
      rightPage,
      Paint()
        ..color = const Color(0xFF2A2D45)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      rightPage,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Spine line
    canvas.drawLine(
      spineTop,
      spineBottom,
      Paint()
        ..color = accent.withValues(alpha: 0.75)
        ..strokeWidth = 1.4,
    );

    // ── Text lines on each page (faint accent strokes) ──
    final linePaint = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    // Left page text lines
    for (var i = 0; i < 3; i++) {
      final y = h * (0.38 + i * 0.10);
      canvas.drawLine(
        Offset(w * 0.22, y),
        Offset(w * 0.44, y),
        linePaint,
      );
    }
    // Right page text lines
    for (var i = 0; i < 3; i++) {
      final y = h * (0.38 + i * 0.10);
      canvas.drawLine(
        Offset(w * 0.56, y),
        Offset(w * 0.78, y),
        linePaint,
      );
    }

    // ── Magnifier (small accent ring on the top-right page) ──
    final magCenter = Offset(w * 0.74, h * 0.30);
    final magRadius = w * 0.08;
    canvas.drawCircle(
      magCenter,
      magRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            accent.withValues(alpha: 0.85),
            accent.withValues(alpha: 0.45),
          ],
        ).createShader(
            Rect.fromCircle(center: magCenter, radius: magRadius)),
    );
    canvas.drawCircle(
      magCenter,
      magRadius,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Handle of magnifier
    canvas.drawLine(
      Offset(magCenter.dx + magRadius * 0.7, magCenter.dy + magRadius * 0.7),
      Offset(magCenter.dx + magRadius * 1.4, magCenter.dy + magRadius * 1.4),
      Paint()
        ..color = accent
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
