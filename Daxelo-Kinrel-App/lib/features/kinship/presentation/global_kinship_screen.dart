import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/kinship/country_kinship_models.dart';
import '../../../core/kinship/country_kinship_provider.dart';
import '../../../shared/widgets/dk_components.dart';

/// Global Kinship Screen — Country-first approach to world kinship
///
/// Flow:
///   1. User sees countries grouped by continent/region
///   2. User selects a country (e.g., China, Russia, India)
///   3. Navigates to CountryKinshipDetailScreen showing that country's
///      kinship terms in its languages
///
/// Features:
///   - Continent filter chips at the top
///   - Search countries by name, native name, or language
///   - Country cards showing flag, name, language count, data status
///   - Cross-cultural comparison entry point
class GlobalKinshipScreen extends ConsumerStatefulWidget {
  const GlobalKinshipScreen({super.key});

  @override
  ConsumerState<GlobalKinshipScreen> createState() =>
      _GlobalKinshipScreenState();
}

class _GlobalKinshipScreenState extends ConsumerState<GlobalKinshipScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final continents = ref.watch(continentListProvider);
    final selectedContinent = ref.watch(selectedContinentProvider);
    final filteredCountries = ref.watch(filteredCountriesProvider);
    final availableKeys = ref.watch(availableCultureKeysProvider);

    return DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'World Kinship',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: DKColors.textPrimary(context),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows_rounded),
            tooltip: 'Compare Cultures',
            onPressed: () => context.push('/kinship/compare'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Hero section
          _buildHeroSection(context),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: KinrelSpacing.sm,
            ),
            child: DKSearchField(
              hint: 'Search country, language, or region...',
              controller: _searchController,
              onChanged: (value) {
                ref.read(countrySearchQueryProvider.notifier).state = value;
              },
            ),
          ),

          // Continent filter chips
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: 4,
              ),
              itemCount: continents.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return DKSuggestionChip(
                    label: '🌍 All',
                    isSelected: selectedContinent == null,
                    onTap: () =>
                        ref.read(selectedContinentProvider.notifier).state =
                            null,
                  );
                }
                final continent = continents[index - 1];
                final icon = KinshipContinent.getIcon(continent);
                return DKSuggestionChip(
                  label: '$icon ${_shortContinentName(continent)}',
                  isSelected: selectedContinent == continent,
                  onTap: () =>
                      ref.read(selectedContinentProvider.notifier).state =
                          continent,
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Country grid
          Expanded(
            child: filteredCountries.isEmpty
                ? DKEmptyState(
                    icon: Icons.public_off_rounded,
                    title: 'No Countries Found',
                    subtitle: 'Try a different search or continent filter',
                  )
                : _buildCountryGrid(context, filteredCountries, availableKeys),
          ),
        ],
      ),
    );
  }

  /// Hero section with title and stats
  Widget _buildHeroSection(BuildContext context) {
    final countries = ref.watch(allCountriesProvider);
    final availableKeys = ref.watch(availableCultureKeysProvider);
    final dataCountries = countries
        .where((c) => c.hasAvailableData(availableKeys))
        .length;
    final totalCultures = countries.fold<int>(
      0,
      (sum, c) => sum + c.totalCultures,
    );

    return Container(
          padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base,
            KinrelSpacing.base,
            KinrelSpacing.base,
            KinrelSpacing.sm,
          ),
          child: Row(
            children: [
              // Globe icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: DKColors.ctaGradient,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: DKColors.brandOrange.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🌐', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explore Kinship Worldwide',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: DKColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dataCountries countries with data • $totalCultures languages',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: DKColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
  }

  /// Country grid grouped by continent when no filter is applied
  Widget _buildCountryGrid(
    BuildContext context,
    List<KinshipCountry> countries,
    Set<String> availableKeys,
  ) {
    final selectedContinent = ref.watch(selectedContinentProvider);
    final searchQuery = ref.watch(countrySearchQueryProvider);

    // When searching, show flat grid
    if (searchQuery.isNotEmpty) {
      return _buildFlatGrid(context, countries, availableKeys);
    }

    // When continent is selected, show flat grid for that continent
    if (selectedContinent != null) {
      return _buildFlatGrid(context, countries, availableKeys);
    }

    // Default: group by continent with section headers
    return _buildGroupedByContinent(context, countries, availableKeys);
  }

  /// Countries grouped by continent with section headers
  Widget _buildGroupedByContinent(
    BuildContext context,
    List<KinshipCountry> countries,
    Set<String> availableKeys,
  ) {
    final byContinent = <String, List<KinshipCountry>>{};
    for (final country in countries) {
      (byContinent[country.continent] ??= []).add(country);
    }

    // Use ordered continents
    final orderedContinents = KinshipContinent.all
        .where(byContinent.containsKey)
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: orderedContinents.length,
      itemBuilder: (context, index) {
        final continent = orderedContinents[index];
        final continentCountries = byContinent[continent]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Continent header
            _buildContinentHeader(
              context,
              continent,
              continentCountries.length,
            ),

            // Country cards in a horizontal scroll
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base,
                ),
                itemCount: continentCountries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, idx) {
                  return _CountryCard(
                    country: continentCountries[idx],
                    availableKeys: availableKeys,
                    index: idx,
                    onTap: () => _onCountrySelected(continentCountries[idx]),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// Continent section header
  Widget _buildContinentHeader(
    BuildContext context,
    String continent,
    int countryCount,
  ) {
    final icon = KinshipContinent.getIcon(continent);
    final color = _getContinentColor(continent);

    return Padding(
      padding: const EdgeInsets.only(
        left: KinrelSpacing.base,
        top: KinrelSpacing.base,
        bottom: KinrelSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            continent,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$countryCount',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Flat grid when searching or continent filter is applied
  Widget _buildFlatGrid(
    BuildContext context,
    List<KinshipCountry> countries,
    Set<String> availableKeys,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: countries.length,
      itemBuilder: (context, index) {
        return _CountryCard(
          country: countries[index],
          availableKeys: availableKeys,
          index: index,
          onTap: () => _onCountrySelected(countries[index]),
        );
      },
    );
  }

  void _onCountrySelected(KinshipCountry country) {
    context.push('/kinship/country/${country.countryCode}');
  }

  Color _getContinentColor(String continent) {
    switch (continent) {
      case KinshipContinent.asia:
        return const Color(0xFFE8612A);
      case KinshipContinent.europe:
        return const Color(0xFF3B82F6);
      case KinshipContinent.africa:
        return const Color(0xFFC44A18);
      case KinshipContinent.middleEast:
        return const Color(0xFFD4AF37);
      case KinshipContinent.americas:
        return const Color(0xFF4CAF7A);
      case KinshipContinent.oceania:
        return const Color(0xFF60A5FA);
      default:
        return const Color(0xFF8A7A72);
    }
  }

  String _shortContinentName(String continent) {
    switch (continent) {
      case KinshipContinent.asia:
        return 'Asia';
      case KinshipContinent.europe:
        return 'Europe';
      case KinshipContinent.africa:
        return 'Africa';
      case KinshipContinent.middleEast:
        return 'Middle East';
      case KinshipContinent.americas:
        return 'Americas';
      case KinshipContinent.oceania:
        return 'Oceania';
      default:
        return continent;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// COUNTRY CARD — Card for each country in the grid
// ═══════════════════════════════════════════════════════════════════════

class _CountryCard extends StatelessWidget {
  const _CountryCard({
    required this.country,
    required this.availableKeys,
    required this.index,
    required this.onTap,
  });

  final KinshipCountry country;
  final Set<String> availableKeys;
  final int index;
  final VoidCallback onTap;

  bool get _hasData => country.hasAvailableData(availableKeys);
  int get _availableCount => country.availableCultureCount(availableKeys);

  @override
  Widget build(BuildContext context) {
    final continentColor = _getContinentColor(country.continent);

    return DKCard(
          borderColor: _hasData
              ? continentColor.withValues(alpha: 0.2)
              : DKColors.brandGold.withValues(alpha: 0.1),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Flag + name row
              Row(
                children: [
                  Text(country.flagEmoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          country.name,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: DKColors.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          country.nativeName,
                          style: TextStyle(
                            fontSize: 12,
                            color: _hasData
                                ? continentColor
                                : DKColors.textSecondary(context),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Language count
              Row(
                children: [
                  Icon(
                    Icons.translate_rounded,
                    size: 14,
                    color: DKColors.textSecondary(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${country.totalCultures} language${country.totalCultures > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: DKColors.textSecondary(context),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Status badge
              if (_hasData)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: KinrelColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 10,
                        color: KinrelColors.success,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$_availableCount Available',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.success,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: DKColors.brandGold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 10,
                        color: DKColors.brandGold,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Coming Soon',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: DKColors.brandGold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: index * 30),
        )
        .scale(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1, 1),
          duration: 300.ms,
        );
  }

  Color _getContinentColor(String continent) {
    switch (continent) {
      case KinshipContinent.asia:
        return const Color(0xFFE8612A);
      case KinshipContinent.europe:
        return const Color(0xFF3B82F6);
      case KinshipContinent.africa:
        return const Color(0xFFC44A18);
      case KinshipContinent.middleEast:
        return const Color(0xFFD4AF37);
      case KinshipContinent.americas:
        return const Color(0xFF4CAF7A);
      case KinshipContinent.oceania:
        return const Color(0xFF60A5FA);
      default:
        return const Color(0xFF8A7A72);
    }
  }
}
