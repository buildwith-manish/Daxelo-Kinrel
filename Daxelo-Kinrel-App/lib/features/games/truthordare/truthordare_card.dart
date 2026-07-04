// lib/features/games/truthordare/truthordare_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class TodCard extends ConsumerStatefulWidget {
  const TodCard({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<TodCard> createState() => _TodCardState();
}

class _TodCardState extends ConsumerState<TodCard> {
  @override
  void initState() { super.initState(); Future.microtask(() => ref.read(gameDownloadStatusProvider('truthordare').notifier).checkStatus()); }
  @override
  Widget build(BuildContext context) {
    final dl = ref.watch(gameDownloadStatusProvider('truthordare'));
    const accent = Color(0xFFEF4444); // red — fitting for Truth or Dare
    return Container(margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent.withValues(alpha: 0.15), const Color(0xFF191B2C)]),
        border: Border.all(color: accent.withValues(alpha: 0.3))),
      child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(16),
        onTap: () { if (dl.status != GameDownloadStatus.downloaded) { context.push('/games?familyId=${widget.familyId}'); return; } context.push('/family/${widget.familyId}/truthordare/lobby'); },
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.2)),
              child: const Icon(Icons.local_bar, color: accent, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text('Truth or Dare', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
          ]),
          const SizedBox(height: 10),
          Text(dl.status != GameDownloadStatus.downloaded ? 'Download in Games hub to play' : 'Spin the bottle — family-submitted prompts!',
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
        ])),
      )),
    );
  }
}
