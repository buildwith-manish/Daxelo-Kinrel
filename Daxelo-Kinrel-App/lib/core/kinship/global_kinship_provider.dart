import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'global_kinship_service.dart';
import 'global_kinship_models.dart';
import '../services/kinship_loader_service.dart';

/// Singleton global kinship service provider.
///
/// Injects [KinshipLoaderService] so that global cultures (arabic, korean,
/// japanese, vietnamese, russian, chinese) are fetched on demand from the
/// server instead of being bundled in the APK (~165 MB savings).
final globalKinshipServiceProvider = Provider<GlobalKinshipService>((ref) {
  final loader = ref.watch(kinshipLoaderProvider);
  return GlobalKinshipService(loader);
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
/// NOTE: Only searches already-loaded cultures — does NOT trigger loadAllAvailable()
/// to avoid ANR. Cultures are loaded lazily via cultureKinshipDataProvider.
final globalKinshipSearchResultsProvider =
    FutureProvider<List<GlobalKinshipTerm>>((ref) async {
      final query = ref.watch(globalKinshipSearchQueryProvider);
      if (query.isEmpty) return [];

      final service = ref.watch(globalKinshipServiceProvider);

      // Search only already-loaded cultures (lazy approach to avoid ANR)
      return service.searchGlobally(query);
    });

/// Load data for a specific culture
final cultureKinshipDataProvider =
    FutureProvider.family<GlobalKinshipData?, String>((ref, cultureKey) async {
      final service = ref.watch(globalKinshipServiceProvider);
      return service.loadCulture(cultureKey);
    });

/// Cross-cultural comparison for a specific relationship key
/// Only compares across already-loaded cultures to avoid ANR from eager loading
final crossCulturalComparisonProvider =
    FutureProvider.family<CrossCulturalComparison?, String>((
      ref,
      relationshipKey,
    ) async {
      final service = ref.watch(globalKinshipServiceProvider);

      // Compare only already-loaded cultures (avoid loading all at once)
      return service.compareCrossCulturally(relationshipKey);
    });

/// Get common relationship keys across all loaded cultures
/// Only checks already-loaded cultures to avoid ANR
final commonRelationshipKeysProvider = FutureProvider<List<String>>((
  ref,
) async {
  final service = ref.watch(globalKinshipServiceProvider);
  return service.getCommonRelationshipKeys();
});

/// Get comparable relationship keys (in at least 2 cultures)
/// Only checks already-loaded cultures to avoid ANR
final comparableRelationshipKeysProvider = FutureProvider<List<String>>((
  ref,
) async {
  final service = ref.watch(globalKinshipServiceProvider);
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
