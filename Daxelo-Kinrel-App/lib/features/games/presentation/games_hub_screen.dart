// lib/features/games/presentation/games_hub_screen.dart
//
// Games catalog — shows all available games with download state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../services/game_asset_manager.dart';

class GamesHubScreen extends ConsumerStatefulWidget {
  const GamesHubScreen({super.key, this.familyId});
  final String? familyId;
  @override
  ConsumerState<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<GamesHubScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(gameDownloadStatusProvider('ghost-painter').notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Text('Games', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        Text('Family Games', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 8),
        Text('Download games to play with your family', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
        const SizedBox(height: 20),
        _GameCatalogCard(
          gameId: 'ghost-painter',
          name: 'Ghost Painter',
          description: 'Draw a word while your family guesses in real-time',
          icon: Icons.brush_outlined,
          color: const Color(0xFFEC4899),
          sizeEstimate: '~2 MB',
          familyId: widget.familyId,
        ),
      ]),
    );
  }
}

class _GameCatalogCard extends ConsumerWidget {
  const _GameCatalogCard({required this.gameId, required this.name, required this.description, required this.icon, required this.color, required this.sizeEstimate, this.familyId});
  final String gameId;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String sizeEstimate;
  final String? familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlState = ref.watch(gameDownloadStatusProvider(gameId));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
          child: Icon(icon, color: color, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(height: 2),
          Text(description, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
          const SizedBox(height: 4),
          Text(sizeEstimate, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.textDim)),
        ])),
        const SizedBox(width: 8),
        _buildAction(context, ref, dlState),
      ]),
    );
  }

  Widget _buildAction(BuildContext context, WidgetRef ref, GameDownloadState dlState) {
    switch (dlState.status) {
      case GameDownloadStatus.notDownloaded:
        return FilledButton(onPressed: () => ref.read(gameDownloadStatusProvider(gameId).notifier).download(),
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
          child: const Text('Get'));
      case GameDownloadStatus.downloading:
        return SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: color));
      case GameDownloadStatus.downloaded:
        return FilledButton(onPressed: () {
          if (familyId != null) {
            context.push('/family/$familyId/ghost-painter/draw');
          }
        }, style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
          child: const Text('Play'));
      case GameDownloadStatus.failed:
        return FilledButton(onPressed: () => ref.read(gameDownloadStatusProvider(gameId).notifier).download(),
          style: FilledButton.styleFrom(backgroundColor: KinrelColors.error, foregroundColor: Colors.white),
          child: const Text('Retry'));
    }
  }
}
