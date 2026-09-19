// lib/features/games/secret_heist/secret_heist_card.dart
//
// Secret Heist — preview card for the Family Detail / Games hub screen.
//
// Premium dark-vault styling with vault + coin motif. Matches the visual
// language of the other game cards (amber accent + dark gradient).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class SecretHeistCard extends ConsumerStatefulWidget {
  const SecretHeistCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SecretHeistCard> createState() => _SecretHeistCardState();
}

class _SecretHeistCardState extends ConsumerState<SecretHeistCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('secret-heist').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('secret-heist'));

    // Emerald accent — distinct from existing games, evoking stealth +
    // vault themes.
    const accent = Color(0xFF10B981);

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
            context.push('/family/${widget.familyId}/secret-heist/lobby');
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
                    painter: _SecretHeistMotifPainter(accent: accent),
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
                              'Secret Heist',
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
                        'Social strategy · Bluff, steal, outsmart',
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
                          'Secretly choose actions, lock in, resolve. Most coins wins.',
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

/// Small custom painter that renders a vault + coin motif — premium
/// dark styling with no cartoon artwork.
class _SecretHeistMotifPainter extends CustomPainter {
  _SecretHeistMotifPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // ── Vault body (rounded rect) ──
    final vaultRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 6, w - 8, h - 12),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      vaultRect,
      Paint()
        ..color = const Color(0xFF191B2C)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      vaultRect,
      Paint()
        ..color = accent.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // ── Vault dial (inner circle) ──
    final dialRadius = (w - 22) / 2;
    canvas.drawCircle(
      center,
      dialRadius,
      Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      dialRadius,
      Paint()
        ..color = accent.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // ── Center coin ──
    final coinRadius = dialRadius * 0.45;
    canvas.drawCircle(
      center,
      coinRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            const Color(0xFFFCD34D),
            const Color(0xFFB45309),
          ],
        ).createShader(
            Rect.fromCircle(center: center, radius: coinRadius)),
    );

    // ── Vault handle marks (small lines on left/right of dial) ──
    final handlePaint = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Left handle
    canvas.drawLine(
      Offset(vaultRect.left + 2, center.dy - 3),
      Offset(vaultRect.left + 2, center.dy + 3),
      handlePaint,
    );
    // Right handle
    canvas.drawLine(
      Offset(vaultRect.right - 2, center.dy - 3),
      Offset(vaultRect.right - 2, center.dy + 3),
      handlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
