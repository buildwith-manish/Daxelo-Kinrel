// lib/widgets/kinship_asset_gate.dart
//
// New behaviour (non-blocking):
//   1. Load kinship_core.json immediately (bundled, ~142KB, instant)
//   2. Show the app immediately — no waiting, no blocking screen
//   3. In background: check if full indian_kinship.json is downloaded
//      - If yes: reload KinshipService with full data
//      - If no: download it silently, then reload when done
//
// Result: App is functional from the first frame.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/kinship/kinship_service.dart';
import '../services/asset_download_service.dart';
import '../providers/kinship_providers.dart';

class KinshipAssetGate extends ConsumerStatefulWidget {
  final Widget child;
  const KinshipAssetGate({super.key, required this.child});

  @override
  ConsumerState<KinshipAssetGate> createState() => _KinshipAssetGateState();
}

class _KinshipAssetGateState extends ConsumerState<KinshipAssetGate> {
  @override
  void initState() {
    super.initState();
    _initKinship();
  }

  Future<void> _initKinship() async {
    // Step 1: Load core JSON immediately (bundled, instant)
    try {
      await KinshipService.instance.load(); // loads kinship_core.json from assets
      if (mounted) {
        ref.read(kinshipReadyProvider.notifier).state = true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load core kinship data: $e');
    }

    // Step 2: Check/download full JSON in background
    _loadFullJsonInBackground();
  }

  Future<void> _loadFullJsonInBackground() async {
    final downloadService = ref.read(assetDownloadServiceProvider);

    try {
      final ready = await downloadService.areAssetsReady();

      if (ready) {
        // Full JSON already downloaded — reload service with full data
        final jsonPath = await downloadService.getJsonPath();
        await KinshipService.instance.reload(jsonPath);
        if (mounted) {
          ref.read(kinshipFullyLoadedProvider.notifier).state = true;
          debugPrint('✅ Full kinship data loaded: ${KinshipService.instance.totalRelationships} relationships');
        }
      } else {
        // Download in background — user is already using the app with core data
        debugPrint('📥 Starting background download of full kinship JSON...');
        if (mounted) ref.read(downloadProgressProvider.notifier).state = 0.0;

        await for (final progress in downloadService.downloadAssetsWithProgress()) {
          if (mounted) {
            ref.read(downloadProgressProvider.notifier).state = progress.progress;
          }
        }

        // Download complete — reload with full data
        final jsonPath = await downloadService.getJsonPath();
        await KinshipService.instance.reload(jsonPath);
        if (mounted) {
          ref.read(kinshipFullyLoadedProvider.notifier).state = true;
          ref.read(downloadProgressProvider.notifier).state = null;
          debugPrint('✅ Background download complete. Full kinship data loaded.');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Background kinship download failed: $e — using core data');
      if (mounted) {
        ref.read(downloadProgressProvider.notifier).state = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always show the child — never block the UI
    return widget.child;
  }
}
