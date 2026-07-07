// lib/features/games/sos/sos_card.dart
//
// SOS Game — preview card shown on the Family Detail screen.
// Mirrors the GhostPainterCard / RedlightCard pattern.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class SosCard extends ConsumerStatefulWidget {
  const SosCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SosCard> createState() => _SosCardState();
}

class _SosCardState extends ConsumerState<SosCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(gameDownloadStatusProvider('sos').notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('sos'));

    // Amber accent — distinct from Ghost Painter (pink) and Freeze & Dash (emerald)
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
            context.push('/family/${widget.familyId}/sos/lobby');
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.2),
                      ),
                      child: const Icon(
                        Icons.grid_on_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'SOS',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (dlState.status != GameDownloadStatus.downloaded)
                  Text(
                    'Download in Games hub to play',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
                    ),
                  )
                else
                  Text(
                    'Complete S-O-S sequences — 2-player or 4-player team mode',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
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
