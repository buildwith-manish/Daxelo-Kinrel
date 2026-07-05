// lib/features/games/twotruths/twotruths_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../services/game_asset_manager.dart';

class TtCard extends ConsumerStatefulWidget {
  const TtCard({super.key, required this.familyId}); final String familyId;
  @override
  ConsumerState<TtCard> createState() => _TtCardState();
}
class _TtCardState extends ConsumerState<TtCard> {
  @override
  void initState() { super.initState(); Future.microtask(() => ref.read(gameDownloadStatusProvider('twotruths').notifier).checkStatus()); }
  @override
  Widget build(BuildContext context) {
    final dl = ref.watch(gameDownloadStatusProvider('twotruths'));
    const accent = Color(0xFFD946EF); // fuchsia
    return Container(margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent.withValues(alpha: 0.15), const Color(0xFF191B2C)]),
        border: Border.all(color: accent.withValues(alpha: 0.3))),
      child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(16),
        onTap: () { if (dl.status != GameDownloadStatus.downloaded) { context.push('/games?familyId=${widget.familyId}'); return; } context.push('/family/${widget.familyId}/twotruths/lobby'); },
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.2)),
              child: const Icon(Icons.psychology, color: accent, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text('Two Truths and a Lie', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
          ]),
          const SizedBox(height: 10),
          Text(dl.status != GameDownloadStatus.downloaded ? 'Download in Games hub to play' : 'Fool your family — 2 truths, 1 lie!',
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
        ])),
      )),
    );
  }
}
