// lib/providers/kinship_providers.dart
//
// DAXELO KINREL — Kinship Riverpod Providers
//
// Provides dependency injection for the kinship resolution system.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/kinship/kinship_service.dart';
import '../services/kinship_resolver.dart';
import '../services/asset_download_service.dart';

/// Singleton KinshipService provider.
final kinshipServiceProvider = Provider<KinshipService>((ref) {
  return KinshipService.instance;
});

/// Singleton KinshipResolver provider.
final kinshipResolverProvider = Provider<KinshipResolver>((ref) {
  return KinshipResolver();
});

/// Singleton AssetDownloadService provider.
final assetDownloadProvider = Provider<AssetDownloadService>((ref) {
  return AssetDownloadService();
});

/// Whether kinship data is loaded (either core or full JSON).
final kinshipReadyProvider = StateProvider<bool>((ref) => false);

/// Whether the FULL JSON (5363 entries) has been downloaded and loaded
/// (vs the core fallback with 60 entries).
final kinshipFullyLoadedProvider = StateProvider<bool>((ref) => false);

/// Download progress (0.0 to 1.0, null = not downloading).
final downloadProgressProvider = StateProvider<double?>((ref) => null);

/// Resolve a single kinship chain.
/// Usage: ref.read(chainResolverProvider((fromKey: 'father', viaKey: 'brother', gender: 'male')))
final chainResolverProvider = Provider.family<
    ResolvedKinship, ({String fromKey, String viaKey, String gender})>(
  (ref, args) {
    final resolver = ref.read(kinshipResolverProvider);
    return resolver.resolve(
      args.fromKey,
      args.viaKey,
      viewerGender: args.gender,
    );
  },
);

/// Get display name for a relationship key in a specific language.
final relationshipDisplayNameProvider =
    Provider.family<String, ({String key, String language})>(
  (ref, args) {
    final resolver = ref.read(kinshipResolverProvider);
    return resolver.getDisplayName(args.key, args.language);
  },
);
