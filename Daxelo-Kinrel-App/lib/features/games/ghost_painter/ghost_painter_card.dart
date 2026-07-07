// lib/features/games/ghost_painter/ghost_painter_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../services/game_asset_manager.dart';
import 'ghost_painter_provider.dart';

class GhostPainterCard extends ConsumerStatefulWidget {
  const GhostPainterCard({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<GhostPainterCard> createState() => _GhostPainterCardState();
}

class _GhostPainterCardState extends ConsumerState<GhostPainterCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(ghostPainterProvider(widget.familyId).notifier).load();
      ref.read(gameDownloadStatusProvider('ghost-painter').notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ghostPainterProvider(widget.familyId));
    final dlState = ref.watch(gameDownloadStatusProvider('ghost-painter'));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xFFEC4899).withValues(alpha: 0.15), const Color(0xFF191B2C)]),
        border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.3)),
      ),
      child: Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (dlState.status != GameDownloadStatus.downloaded) {
            context.push('/games?familyId=${widget.familyId}');
            return;
          }
          if (state.hasActiveRound) {
            context.push('/family/${widget.familyId}/ghost-painter/guess');
          } else {
            context.push('/family/${widget.familyId}/ghost-painter/draw');
          }
        },
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFEC4899).withValues(alpha: 0.2)),
              child: const Icon(Icons.brush_rounded, color: Color(0xFFEC4899), size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text('Ghost Painter', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
            if (state.hasActiveRound)
              _LiveBadge(),
          ]),
          const SizedBox(height: 10),
          if (dlState.status != GameDownloadStatus.downloaded)
            Text('Download in Games hub to play', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim))
          else if (state.hasActiveRound)
            Text('${state.activeRound!.drawerPersonName} is drawing — tap to guess!',
              style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: KinrelColors.textWhite))
          else if (state.isLoading)
            Text('Loading...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim))
          else
            Text('No active round — tap to start drawing',
              style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
        ])),
      )),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (_, __) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFEC4899).withValues(alpha: 0.5 + _ctrl.value * 0.5), borderRadius: BorderRadius.circular(8)),
      child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
    ));
  }
}
