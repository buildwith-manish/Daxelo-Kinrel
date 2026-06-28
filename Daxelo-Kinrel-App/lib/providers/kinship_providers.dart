// lib/providers/kinship_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/asset_download_service.dart';
import '../services/kinship_resolver.dart';
import '../core/kinship/kinship_service.dart';

/// Singleton AssetDownloadService.
final assetDownloadServiceProvider = Provider<AssetDownloadService>((ref) {
  return AssetDownloadService();
});

/// Singleton KinshipResolver (chainRules-based, no SQLite).
final kinshipResolverProvider = Provider<KinshipResolver>((ref) {
  return KinshipResolver();
});

/// Whether KinshipService has loaded (at minimum, core JSON).
final kinshipReadyProvider = StateProvider<bool>((ref) => false);

/// Whether the full indian_kinship.json is loaded (vs core fallback).
final kinshipFullyLoadedProvider = StateProvider<bool>((ref) => false);

/// Background download progress (0.0–1.0, null = not downloading).
final downloadProgressProvider = StateProvider<double?>((ref) => null);

/// Whether app needs asset setup (kept for backward compat — always false now).
final needsAssetSetupProvider = FutureProvider<bool>((ref) async => false);

/// Resolve a single kinship chain.
final chainResolverProvider = Provider.family<
  ResolvedKinship,
  ({String fromKey, String viaKey, String gender})
>((ref, args) {
  final resolver = ref.read(kinshipResolverProvider);
  return resolver.resolve(args.fromKey, args.viaKey, viewerGender: args.gender);
});

/// Get display name for a relationship key in a given language.
final relationshipDisplayNameProvider = Provider.family<
  String,
  ({String key, String language})
>((ref, args) {
  final resolver = ref.read(kinshipResolverProvider);
  return resolver.getDisplayName(args.key, args.language);
});
