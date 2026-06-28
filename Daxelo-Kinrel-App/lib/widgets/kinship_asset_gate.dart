// lib/widgets/kinship_asset_gate.dart
//
// DAXELO KINREL — Kinship Asset Gate
//
// Wraps the main app. On first launch:
//   1. Loads bundled kinship_core.json (388 KB, instant) → app opens immediately
//   2. Downloads full indian_kinship.json (~3 MB) in background
//   3. When download completes, reloads KinshipService with full data
//
// User experience:
//   - App opens instantly with core data (60 relationships + chainRules)
//   - Full 5363 relationships download silently in background
//   - No blocking screen, no waiting

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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeKinship();
  }

  Future<void> _initializeKinship() async {
    try {
      final downloadService = ref.read(assetDownloadProvider);
      final kinship = KinshipService.instance;

      // Step 1: Check if full JSON is already downloaded
      final isFullReady = await downloadService.isIndianJsonReady();

      if (isFullReady) {
        // Load full JSON from local file
        final jsonPath = await downloadService.getIndianJsonPath();
        await kinship.load(localFilePath: jsonPath);
        ref.read(kinshipReadyProvider.notifier).state = true;
        ref.read(kinshipFullyLoadedProvider.notifier).state = true;
        debugPrint('✅ KinshipAssetGate: Full JSON loaded from local file');
      } else {
        // Step 2: Load bundled core JSON (instant, ~388 KB)
        await kinship.load(); // Falls back to kinship_core.json
        ref.read(kinshipReadyProvider.notifier).state = true;
        debugPrint('✅ KinshipAssetGate: Core JSON loaded (instant mode)');

        // Step 3: Download full JSON in background (non-blocking)
        _downloadFullJsonInBackground();
      }
    } catch (e) {
      debugPrint('⚠️ KinshipAssetGate: Failed to initialize kinship: $e');
      // App continues with empty kinship data — math fallback will be used
      ref.read(kinshipReadyProvider.notifier).state = true;
    } finally {
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    }
  }

  Future<void> _downloadFullJsonInBackground() async {
    try {
      final downloadService = ref.read(assetDownloadProvider);
      final kinship = KinshipService.instance;

      // Stream download progress (optional: could update a provider for UI)
      await for (final progress in downloadService.downloadIndianJson()) {
        debugPrint(
            '📥 Downloading kinship data: ${(progress.progress * 100).toStringAsFixed(0)}%');
      }

      // Reload KinshipService with full JSON
      final jsonPath = await downloadService.getIndianJsonPath();

      // Reset the singleton to allow reloading
      kinship.reload();

      // Load full JSON
      await kinship.load(localFilePath: jsonPath);

      ref.read(kinshipFullyLoadedProvider.notifier).state = true;
      debugPrint('✅ KinshipAssetGate: Full JSON downloaded and loaded (5363 relationships)');
    } catch (e) {
      debugPrint('⚠️ KinshipAssetGate: Background download failed: $e');
      // App continues with core JSON — user can retry later
    }
  }

  @override
  Widget build(BuildContext context) {
    // While initializing, show a minimal loading screen
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.family_restroom,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Initialized — show the main app
    return widget.child;
  }
}
