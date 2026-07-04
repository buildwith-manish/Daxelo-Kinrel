// lib/features/games/redlight/redlight_card.dart
//
// Freeze & Dash — preview card shown on the Family Detail screen.
// Mirrors the GhostPainterCard pattern.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../services/game_asset_manager.dart';
import 'redlight_provider.dart';

class RedlightCard extends ConsumerStatefulWidget {
  const RedlightCard({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<RedlightCard> createState() => _RedlightCardState();
}

class _RedlightCardState extends ConsumerState<RedlightCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      // Trigger download-status check so the card label flips from
      // "Download in Games hub" to "Tap to play" once assets are cached.
      ref
          .read(gameDownloadStatusProvider('freeze-dash').notifier)
          .checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(gameDownloadStatusProvider('freeze-dash'));

    // Emerald accent for traffic-light association (matches Games Hub card).
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
              // Not yet downloaded — send the user to the Games Hub to fetch.
              context.push('/games?familyId=${widget.familyId}');
              return;
            }
            // Downloaded — go straight to the lobby.
            context.push('/family/${widget.familyId}/freeze-dash/lobby');
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
                        Icons.directions_run_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Freeze & Dash',
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
                    'Race to the finish — but freeze when the Caller calls RED!',
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
