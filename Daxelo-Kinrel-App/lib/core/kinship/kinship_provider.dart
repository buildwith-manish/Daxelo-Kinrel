import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'kinship_service.dart';
import 'kinship_models.dart';

/// Singleton kinship service provider
final kinshipServiceProvider = Provider<KinshipService>((ref) {
  return KinshipService();
});

/// Async initialization provider — loads data on first access
final kinshipInitializedProvider = FutureProvider<void>((ref) async {
  // ANR FIX: Yield before heavy kinship JSON parsing to let the
  // Android message queue process pending touch/lifecycle events.
  await Future.delayed(Duration.zero);
  final service = ref.watch(kinshipServiceProvider);
  await service.load();
});

/// Meta info provider
final kinshipMetaProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  await Future.delayed(Duration.zero); // ANR fix: yield before work
  final kinshipReady = ref.watch(kinshipInitializedProvider);
  if (!kinshipReady.hasValue) return {};
  final service = ref.watch(kinshipServiceProvider);
  return service.getMeta();
});

/// Search provider
final kinshipSearchProvider = StateProvider<String>((ref) => '');

final kinshipSearchResultsProvider = FutureProvider<List<KinshipSearchResult>>((
  ref,
) async {
  await Future.delayed(Duration.zero); // ANR fix: yield before work
  final kinshipReady = ref.watch(kinshipInitializedProvider);
  if (!kinshipReady.hasValue) return [];
  final query = ref.watch(kinshipSearchProvider);
  if (query.isEmpty) return [];
  final service = ref.watch(kinshipServiceProvider);
  return service.search(query);
});

/// Category provider
final kinshipCategoryProvider = StateProvider<String?>((ref) => null);

final kinshipCategoryResultsProvider =
    FutureProvider<List<KinshipRelationship>>((ref) async {
      await Future.delayed(Duration.zero); // ANR fix: yield before work
      final kinshipReady = ref.watch(kinshipInitializedProvider);
      if (!kinshipReady.hasValue) return [];
      final category = ref.watch(kinshipCategoryProvider);
      if (category == null) return [];
      final service = ref.watch(kinshipServiceProvider);
      return service.getByCategory(category);
    });

/// All categories provider
final kinshipCategoriesProvider = FutureProvider<List<String>>((ref) async {
  await Future.delayed(Duration.zero); // ANR fix: yield before work
  final kinshipReady = ref.watch(kinshipInitializedProvider);
  if (!kinshipReady.hasValue) return [];
  final service = ref.watch(kinshipServiceProvider);
  return service.categories;
});

/// Single term lookup provider
final kinshipTermProvider =
    FutureProvider.family<KinshipTranslation?, ({String key, String language})>(
      (ref, params) async {
        final kinshipReady = ref.watch(kinshipInitializedProvider);
        if (!kinshipReady.hasValue) return null;
        final service = ref.watch(kinshipServiceProvider);
        return service.getKinshipTerm(params.key, params.language);
      },
    );

/// All translations for a key
final kinshipAllTranslationsProvider =
    FutureProvider.family<Map<String, KinshipTranslation>?, String>((
      ref,
      key,
    ) async {
      final kinshipReady = ref.watch(kinshipInitializedProvider);
      if (!kinshipReady.hasValue) return null;
      final service = ref.watch(kinshipServiceProvider);
      return service.getAllTranslations(key);
    });

/// All relationships provider
final allRelationshipsProvider = FutureProvider<List<KinshipRelationship>>((
  ref,
) async {
  final kinshipReady = ref.watch(kinshipInitializedProvider);
  if (!kinshipReady.hasValue) return [];
  final service = ref.watch(kinshipServiceProvider);
  return service.getAllRelationships();
});
