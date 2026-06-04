import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'global_kinship_service.dart';
import 'global_kinship_models.dart';

/// Singleton global kinship service provider
final globalKinshipServiceProvider = Provider<GlobalKinshipService>((ref) {
  return GlobalKinshipService();
});

/// List of all 50+ cultures with metadata
final availableCulturesProvider = Provider<List<GlobalCultureInfo>>((ref) {
  final service = ref.watch(globalKinshipServiceProvider);
  return service.allCultures;
});

/// Cultures that have full data files
final dataAvailableCulturesProvider = Provider<List<GlobalCultureInfo>>((ref) {
  final service = ref.watch(globalKinshipServiceProvider);
  return service.availableCultures;
});

/// Cultures that are metadata-only (Coming Soon)
final comingSoonCulturesProvider = Provider<List<GlobalCultureInfo>>((ref) {
  final service = ref.watch(globalKinshipServiceProvider);
  return service.comingSoonCultures;
});

/// Currently selected culture key
final selectedCultureProvider = StateProvider<String?>((ref) => null);

/// Search query for global kinship search
final globalKinshipSearchQueryProvider = StateProvider<String>((ref) => '');

/// Search across all loaded cultures
final globalKinshipSearchResultsProvider =
    FutureProvider<List<GlobalKinshipTerm>>((ref) async {
      final query = ref.watch(globalKinshipSearchQueryProvider);
      if (query.isEmpty) return [];

      final service = ref.watch(globalKinshipServiceProvider);

      // Ensure all available cultures are loaded before searching
      await service.loadAllAvailable();

      return service.searchGlobally(query);
    });

/// Load data for a specific culture
final cultureKinshipDataProvider =
    FutureProvider.family<GlobalKinshipData?, String>((ref, cultureKey) async {
      final service = ref.watch(globalKinshipServiceProvider);
      return service.loadCulture(cultureKey);
    });

/// Cross-cultural comparison for a specific relationship key
final crossCulturalComparisonProvider =
    FutureProvider.family<CrossCulturalComparison?, String>((
      ref,
      relationshipKey,
    ) async {
      final service = ref.watch(globalKinshipServiceProvider);

      // Ensure all available cultures are loaded
      await service.loadAllAvailable();

      return service.compareCrossCulturally(relationshipKey);
    });

/// Get common relationship keys across all loaded cultures
final commonRelationshipKeysProvider = FutureProvider<List<String>>((
  ref,
) async {
  final service = ref.watch(globalKinshipServiceProvider);
  await service.loadAllAvailable();
  return service.getCommonRelationshipKeys();
});

/// Get comparable relationship keys (in at least 2 cultures)
final comparableRelationshipKeysProvider = FutureProvider<List<String>>((
  ref,
) async {
  final service = ref.watch(globalKinshipServiceProvider);
  await service.loadAllAvailable();
  return service.getComparableRelationshipKeys();
});

/// Culture filter by region
final cultureRegionFilterProvider = StateProvider<String?>((ref) => null);

/// Filtered cultures based on region and search
final filteredCulturesProvider = Provider<List<GlobalCultureInfo>>((ref) {
  final cultures = ref.watch(availableCulturesProvider);
  final regionFilter = ref.watch(cultureRegionFilterProvider);
  final searchQuery = ref.watch(globalKinshipSearchQueryProvider);

  var filtered = cultures;

  if (regionFilter != null) {
    filtered = filtered.where((c) => c.region == regionFilter).toList();
  }

  if (searchQuery.isNotEmpty) {
    final q = searchQuery.toLowerCase();
    filtered = filtered.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.nativeName.toLowerCase().contains(q) ||
          c.languageFamily.toLowerCase().contains(q) ||
          c.cultureKey.toLowerCase().contains(q);
    }).toList();
  }

  return filtered;
});

/// All unique regions
final cultureRegionsProvider = Provider<List<String>>((ref) {
  final cultures = ref.watch(availableCulturesProvider);
  final regions = cultures.map((c) => c.region).toSet().toList()..sort();
  return regions;
});
