// lib/features/games/code_clues/code_clues_card.dart
//
// Code Clues — preview card for the Family Detail / Games hub screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class CodeCluesCard extends ConsumerStatefulWidget {
  const CodeCluesCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<CodeCluesCard> createState() => _CodeCluesCardState();
}

class _CodeCluesCardState extends ConsumerState<CodeCluesCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(gameDownloadStatusProvider('code-clues').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('code-clues'));

    // Amber accent — evokes the "lock / key / hidden code" theme.
    const accent = Color(0xFFF59E0B);

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
            context.push('/family/${widget.familyId}/code-clues/lobby');
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
                    painter: _CodeCluesMotifPainter(accent: accent),
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
                              'Code Clues',
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
                        'Word association · Teams',
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
                          'Codenames duel — give one-word clues, find your team\'s words. Avoid the assassin!',
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

/// Custom painter that renders a "lock + key" motif — a padlock with a
/// keyhole, evoking the hidden-associations / secret-codes theme without
/// cartoon artwork.
class _CodeCluesMotifPainter extends CustomPainter {
  _CodeCluesMotifPainter({required this.accent});
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

    // ── Padlock shackle (arc above the body) ──
    final shackleRect = Rect.fromLTWH(
      w * 0.32,
      h * 0.18,
      w * 0.36,
      h * 0.32,
    );
    canvas.drawArc(
      shackleRect,
      3.14, // start (180°)
      3.14, // sweep (180°)
      false,
      Paint()
        ..color = accent.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // ── Padlock body ──
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.26, h * 0.40, w * 0.48, h * 0.36),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.55),
          ],
        ).createShader(bodyRect.outerRect),
    );

    // ── Keyhole (circle + tapered slot) ──
    final keyholeCenter = Offset(w * 0.50, h * 0.52);
    canvas.drawCircle(
      keyholeCenter,
      w * 0.07,
      Paint()..color = const Color(0xFF191B2C),
    );
    final slotPath = Path()
      ..moveTo(keyholeCenter.dx - w * 0.03, keyholeCenter.dy + w * 0.04)
      ..lineTo(keyholeCenter.dx + w * 0.03, keyholeCenter.dy + w * 0.04)
      ..lineTo(keyholeCenter.dx + w * 0.025,
          keyholeCenter.dy + w * 0.14)
      ..lineTo(keyholeCenter.dx - w * 0.025,
          keyholeCenter.dy + w * 0.14)
      ..close();
    canvas.drawPath(
      slotPath,
      Paint()
        ..color = const Color(0xFF191B2C)
        ..style = PaintingStyle.fill,
    );

    // ── Tiny accent dots beside the lock (the "code" of clues) ──
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(w * 0.18, h * 0.62), 1.4, dotPaint);
    canvas.drawCircle(Offset(w * 0.18, h * 0.70), 1.4, dotPaint);
    canvas.drawCircle(Offset(w * 0.82, h * 0.62), 1.4, dotPaint);
    canvas.drawCircle(Offset(w * 0.82, h * 0.70), 1.4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
