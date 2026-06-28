// lib/providers/kinship_providers.dart
//
// DAXELO KINREL — Kinship Riverpod Providers
//
// Provides dependency injection for the kinship resolution system:
//   - AssetDownloadService: downloads data files from GitHub Releases
//   - KinshipResolver: main resolver (SQLite + JSON + math fallback)
//   - kinshipReadyProvider: boolean state indicating assets are loaded
//   - downloadProgressProvider: stream of download progress updates

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/asset_download_service.dart';
import '../services/kinship_resolver.dart';
import '../services/kinship_sqlite_service.dart';
import '../services/kinship_json_service.dart';

/// Singleton AssetDownloadService instance.
final assetDownloadServiceProvider = Provider<AssetDownloadService>((ref) {
  final service = AssetDownloadService();
  ref.onDispose(() {
    // Clean up if needed
  });
  return service;
});

/// Singleton KinshipSqliteService instance.
final kinshipSqliteServiceProvider = Provider<KinshipSqliteService>((ref) {
  final service = KinshipSqliteService();
  ref.onDispose(() {
    service.close();
  });
  return service;
});

/// Singleton KinshipJsonService instance.
final kinshipJsonServiceProvider = Provider<KinshipJsonService>((ref) {
  return KinshipJsonService();
});

/// Singleton KinshipResolver instance.
final kinshipResolverProvider = Provider<KinshipResolver>((ref) {
  final sqlite = ref.watch(kinshipSqliteServiceProvider);
  final json = ref.watch(kinshipJsonServiceProvider);
  final resolver = KinshipResolver(sqlite: sqlite, json: json);
  ref.onDispose(() {
    resolver.dispose();
  });
  return resolver;
});

/// Whether kinship assets are fully loaded and ready for queries.
/// Set to true after SQLite + JSON are initialized, or when continuing
/// in basic (math fallback) mode.
final kinshipReadyProvider = StateProvider<bool>((ref) => false);

/// Stream of download progress updates from AssetDownloadService.
/// Subscribe to this during the setup screen to show progress.
final downloadProgressProvider =
    StreamProvider<DownloadProgress>((ref) async* {
  // This provider is intentionally a placeholder — the AssetSetupScreen
  // calls downloadAssets() directly and listens to the returned stream.
  // This provider exists for cases where other parts of the app want to
  // observe download progress.
  yield* const Stream.empty();
});

/// Whether the app should show the AssetSetupScreen on launch.
/// Returns true if assets are NOT ready.
final needsAssetSetupProvider = FutureProvider<bool>((ref) async {
  final downloadService = ref.watch(assetDownloadServiceProvider);
  final ready = await downloadService.areAssetsReady();
  return !ready;
});
