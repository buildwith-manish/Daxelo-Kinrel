// lib/widgets/kinship_asset_gate.dart
//
// DAXELO KINREL — Kinship Asset Gate
//
// Wraps the main app content. On first launch, checks if kinship assets
// are downloaded. If not, shows the AssetSetupScreen. Once assets are ready
// (or user chooses basic mode), shows the child content.
//
// Usage in main.dart:
//   return KinshipAssetGate(
//     child: MaterialApp.router(...),
//   );

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/asset_download_service.dart';
import '../providers/kinship_providers.dart';
import 'asset_setup_screen.dart';

/// Wraps the app and shows AssetSetupScreen on first launch.
class KinshipAssetGate extends ConsumerStatefulWidget {
  final Widget child;

  const KinshipAssetGate({super.key, required this.child});

  @override
  ConsumerState<KinshipAssetGate> createState() => _KinshipAssetGateState();
}

class _KinshipAssetGateState extends ConsumerState<KinshipAssetGate> {
  bool? _needsSetup; // null = checking, true = needs setup, false = ready

  @override
  void initState() {
    super.initState();
    _checkAssets();
  }

  Future<void> _checkAssets() async {
    final downloadService = ref.read(assetDownloadServiceProvider);
    final ready = await downloadService.areAssetsReady();

    if (mounted) {
      setState(() {
        _needsSetup = !ready;
      });

      // If already ready, initialize the resolver
      if (ready) {
        await _initializeResolver();
      }
    }
  }

  Future<void> _initializeResolver() async {
    try {
      final downloadService = ref.read(assetDownloadServiceProvider);
      final resolver = ref.read(kinshipResolverProvider);

      final dbPath = await downloadService.getSqlitePath();
      final jsonPath = await downloadService.getJsonPath();

      await resolver.initializeSqlite(dbPath);
      await resolver.initializeJson(jsonPath);

      if (mounted) {
        ref.read(kinshipReadyProvider.notifier).state = true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to initialize kinship resolver: $e');
      // App will fall back to math engine automatically
      if (mounted) {
        ref.read(kinshipReadyProvider.notifier).state = true;
      }
    }
  }

  void _onSetupComplete() {
    if (mounted) {
      setState(() {
        _needsSetup = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Still checking
    if (_needsSetup == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.family_restroom,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Loading Kinrel...',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show setup screen
    if (_needsSetup == true) {
      return AssetSetupScreen(onComplete: _onSetupComplete);
    }

    // Assets ready — show the main app
    return widget.child;
  }
}
