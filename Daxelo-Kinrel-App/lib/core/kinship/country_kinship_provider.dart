import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'country_kinship_models.dart';
import 'global_kinship_models.dart';
import 'global_kinship_provider.dart';

/// All countries in the registry
final allCountriesProvider = Provider<List<KinshipCountry>>((ref) {
  return countryRegistry;
});

/// Set of culture keys that have full data files available
final availableCultureKeysProvider = Provider<Set<String>>((ref) {
  final service = ref.watch(globalKinshipServiceProvider);
  return service.availableCultures.map((c) => c.cultureKey).toSet();
});

/// Countries grouped by continent
final countriesByContinentProvider =
    Provider<Map<String, List<KinshipCountry>>>((ref) {
      final countries = ref.watch(allCountriesProvider);
      final map = <String, List<KinshipCountry>>{};
      for (final country in countries) {
        (map[country.continent] ??= []).add(country);
      }
      // Sort countries within each continent by name
      for (final list in map.values) {
        list.sort((a, b) => a.name.compareTo(b.name));
      }
      return map;
    });

/// List of continents that have countries
final continentListProvider = Provider<List<String>>((ref) {
  final byContinent = ref.watch(countriesByContinentProvider);
  // Return in a specific order
  final ordered = <String>[];
  for (final c in KinshipContinent.all) {
    if (byContinent.containsKey(c)) {
      ordered.add(c);
    }
  }
  return ordered;
});

/// Currently selected continent filter
final selectedContinentProvider = StateProvider<String?>((ref) => null);

/// Search query for country search
final countrySearchQueryProvider = StateProvider<String>((ref) => '');

/// Filtered countries based on continent filter and search query
final filteredCountriesProvider = Provider<List<KinshipCountry>>((ref) {
  final countries = ref.watch(allCountriesProvider);
  final continentFilter = ref.watch(selectedContinentProvider);
  final searchQuery = ref.watch(countrySearchQueryProvider);

  var filtered = countries;

  if (continentFilter != null) {
    filtered = filtered.where((c) => c.continent == continentFilter).toList();
  }

  if (searchQuery.isNotEmpty) {
    final q = searchQuery.toLowerCase();
    filtered = filtered.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.nativeName.toLowerCase().contains(q) ||
          c.countryCode.toLowerCase().contains(q) ||
          c.cultureKeys.any((key) => key.toLowerCase().contains(q));
    }).toList();
  }

  return filtered;
});

/// Countries that have at least one culture with full data
final dataAvailableCountriesProvider = Provider<List<KinshipCountry>>((ref) {
  final countries = ref.watch(allCountriesProvider);
  final availableKeys = ref.watch(availableCultureKeysProvider);
  return countries.where((c) => c.hasAvailableData(availableKeys)).toList();
});

/// Get culture info objects for a specific country
final countryCulturesProvider =
    Provider.family<List<GlobalCultureInfo>, String>((ref, countryCode) {
      final countries = ref.watch(allCountriesProvider);
      final service = ref.watch(globalKinshipServiceProvider);

      final country = countries
          .where((c) => c.countryCode == countryCode)
          .firstOrNull;
      if (country == null) return [];

      return country.cultureKeys
          .map((key) => service.getCultureInfo(key))
          .whereType<GlobalCultureInfo>()
          .toList();
    });

/// Get a specific country by code
final countryByCodeProvider = Provider.family<KinshipCountry?, String>((
  ref,
  code,
) {
  final countries = ref.watch(allCountriesProvider);
  for (final c in countries) {
    if (c.countryCode == code) return c;
  }
  return null;
});

/// Load all kinship data for a country's available cultures
final countryKinshipDataProvider =
    FutureProvider.family<Map<String, GlobalKinshipData?>, String>((
      ref,
      countryCode,
    ) async {
      final cultures = ref.watch(countryCulturesProvider(countryCode));
      final result = <String, GlobalKinshipData?>{};

      // Load each culture's data using the existing provider
      final futures = <Future<GlobalKinshipData?>>[];
      final keys = <String>[];

      for (final culture in cultures) {
        if (culture.hasDataFile) {
          keys.add(culture.cultureKey);
          futures.add(
            ref.read(cultureKinshipDataProvider(culture.cultureKey).future),
          );
        }
      }

      final dataList = await Future.wait(futures);
      for (var i = 0; i < keys.length; i++) {
        result[keys[i]] = dataList[i];
      }

      return result;
    });
