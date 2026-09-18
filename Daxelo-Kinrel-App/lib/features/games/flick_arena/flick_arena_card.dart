// lib/features/games/flick_arena/flick_arena_card.dart
//
// Flick Arena — preview card for the Family Detail / Games hub screen.
//
// Premium dark-arena styling with disc + ball + goal motif. Matches the
// visual language of the carrom card (amber accent + dark gradient).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class FlickArenaCard extends ConsumerStatefulWidget {
  const FlickArenaCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FlickArenaCard> createState() => _FlickArenaCardState();
}

class _FlickArenaCardState extends ConsumerState<FlickArenaCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(gameDownloadStatusProvider('flick-arena').notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('flick-arena'));

    // Cyan accent — distinct from carrom's amber, evoking the neon-arena
    // theme of Flick Arena.
    const accent = Color(0xFF22D3EE);

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
            context.push('/family/${widget.familyId}/flick-arena/lobby');
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Premium disc + ball + goal motif ──
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(
                    painter: _FlickArenaMotifPainter(accent: accent),
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
                              'Flick Arena',
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
                              '2–4',
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
                        'Physics strategy · 1v1 or 2v2',
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
                          'Flick discs into the goal — bank shots, momentum, and angle play.',
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

/// Small custom painter that renders the disc + ball + goal motif
/// matching the brief's "no cartoon-style artwork" requirement.
class _FlickArenaMotifPainter extends CustomPainter {
  _FlickArenaMotifPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // ── Arena outline (rounded rect) ──
    final arenaRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 4, w - 4, h - 8),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      arenaRect,
      Paint()
        ..color = const Color(0xFF191B2C)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      arenaRect,
      Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // ── Top goal mouth ──
    final topGoalRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(center.dx, 4), width: 20, height: 4),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      topGoalRect,
      Paint()..color = accent.withValues(alpha: 0.6),
    );

    // ── Bottom goal mouth ──
    final bottomGoalRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(center.dx, h - 4), width: 20, height: 4),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      bottomGoalRect,
      Paint()..color = accent.withValues(alpha: 0.6),
    );

    // ── Top disc ──
    canvas.drawCircle(
      Offset(center.dx - 10, 16),
      5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.55),
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(center.dx - 10, 16), radius: 5)),
    );

    // ── Bottom disc ──
    canvas.drawCircle(
      Offset(center.dx + 10, h - 16),
      5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: const [
            Color(0xFFF59E0B),
            Color(0xFFB45309),
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(center.dx + 10, h - 16), radius: 5)),
    );

    // ── Ball (center) ──
    canvas.drawCircle(
      center,
      4,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFCBD5E1),
          ],
        ).createShader(
            Rect.fromCircle(center: center, radius: 4)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
