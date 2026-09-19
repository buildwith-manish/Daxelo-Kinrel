// lib/features/games/crystal_bridge/crystal_bridge_card.dart
//
// Crystal Bridge — preview card for the Family Detail / Games hub screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

/// Cyan accent — matches the canonical Crystal Bridge theme used across
/// the lobby, game screen, and SQL `fn__game_meta()` entry.
const Color kCrystalBridgeAccent = Color(0xFF06B6D4);

class CrystalBridgeCard extends ConsumerStatefulWidget {
  const CrystalBridgeCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<CrystalBridgeCard> createState() => _CrystalBridgeCardState();
}

class _CrystalBridgeCardState extends ConsumerState<CrystalBridgeCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('crystal-bridge').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('crystal-bridge'));

    const accent = kCrystalBridgeAccent;

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
            context.push('/family/${widget.familyId}/crystal-bridge/lobby');
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
                    painter: _CrystalBridgeMotifPainter(accent: accent),
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
                              'Crystal Bridge',
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
                        'Survival · Risk vs Reward',
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
                          'Cross the bridge — one crystal saves you, one shatters you. Use powers to outlast family!',
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

/// Custom painter that renders a crystal / diamond motif — a glowing
/// cyan diamond with subtle facet lines and a smaller secondary crystal
/// beside it, evoking the "two crystals, one safe" theme without any
/// cartoon artwork.
class _CrystalBridgeMotifPainter extends CustomPainter {
  _CrystalBridgeMotifPainter({required this.accent});
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

    // ── Main crystal (large diamond, top-left of center) ──
    final mainCenter = Offset(w * 0.42, h * 0.48);
    final mainHalfW = w * 0.20;
    final mainHalfH = h * 0.26;
    final mainPath = Path()
      ..moveTo(mainCenter.dx, mainCenter.dy - mainHalfH)
      ..lineTo(mainCenter.dx + mainHalfW, mainCenter.dy)
      ..lineTo(mainCenter.dx, mainCenter.dy + mainHalfH)
      ..lineTo(mainCenter.dx - mainHalfW, mainCenter.dy)
      ..close();

    // Filled with a radial glow
    final mainRect = Rect.fromCenter(
        center: mainCenter,
        width: mainHalfW * 2,
        height: mainHalfH * 2);
    canvas.drawPath(
      mainPath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.45),
          ],
        ).createShader(mainRect),
    );

    // Facet lines (vertical + horizontal cross)
    final facetPaint = Paint()
      ..color = const Color(0xFF0A1224).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
        Offset(mainCenter.dx, mainCenter.dy - mainHalfH),
        Offset(mainCenter.dx, mainCenter.dy + mainHalfH),
        facetPaint);
    canvas.drawLine(
        Offset(mainCenter.dx - mainHalfW, mainCenter.dy),
        Offset(mainCenter.dx + mainHalfW, mainCenter.dy),
        facetPaint);

    // Outer outline (slightly brighter for the "active" feel)
    canvas.drawPath(
      mainPath,
      Paint()
        ..color = accent.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // ── Secondary crystal (smaller, lower-right) ──
    final secCenter = Offset(w * 0.70, h * 0.62);
    final secHalfW = w * 0.10;
    final secHalfH = h * 0.14;
    final secPath = Path()
      ..moveTo(secCenter.dx, secCenter.dy - secHalfH)
      ..lineTo(secCenter.dx + secHalfW, secCenter.dy)
      ..lineTo(secCenter.dx, secCenter.dy + secHalfH)
      ..lineTo(secCenter.dx - secHalfW, secCenter.dy)
      ..close();

    final secRect = Rect.fromCenter(
        center: secCenter,
        width: secHalfW * 2,
        height: secHalfH * 2);
    canvas.drawPath(
      secPath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            const Color(0xFF67E8F9),
            accent.withValues(alpha: 0.55),
          ],
        ).createShader(secRect),
    );
    canvas.drawPath(
      secPath,
      Paint()
        ..color = const Color(0xFF67E8F9).withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // ── Three small "spark" dots around the main crystal ──
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.85);
    final dots = [
      Offset(w * 0.18, h * 0.30),
      Offset(w * 0.30, h * 0.72),
      Offset(w * 0.60, h * 0.28),
    ];
    for (final d in dots) {
      canvas.drawCircle(d, 1.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
