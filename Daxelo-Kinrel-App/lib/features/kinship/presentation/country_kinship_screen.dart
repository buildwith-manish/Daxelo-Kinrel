import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/kinship/country_kinship_models.dart';
import '../../../core/kinship/country_kinship_provider.dart';
import '../../../core/kinship/global_kinship_models.dart';
import '../../../core/kinship/global_kinship_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/utils/device_tier.dart';

/// Country Kinship Detail Screen — Shows kinship terms for a specific country
///
/// Flow:
///   1. Displays country header with flag, name, and native name
///   2. Shows language/culture cards for each culture in the country
///   3. When a culture is selected, displays its kinship terms
///   4. Search within the country's kinship terms
///   5. Cross-cultural comparison shortcut
class CountryKinshipDetailScreen extends ConsumerStatefulWidget {
  const CountryKinshipDetailScreen({super.key, required this.countryCode});

  final String countryCode;

  @override
  ConsumerState<CountryKinshipDetailScreen> createState() =>
      _CountryKinshipDetailScreenState();
}

class _CountryKinshipDetailScreenState
    extends ConsumerState<CountryKinshipDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _termQuery = '';
  String? _selectedCultureKey;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final country = ref.watch(countryByCodeProvider(widget.countryCode));
    final cultures = ref.watch(countryCulturesProvider(widget.countryCode));
    final availableKeys = ref.watch(availableCultureKeysProvider);

    if (country == null) {
      return DKScaffold(
        body: DKEmptyState(
          icon: Icons.public_off_rounded,
          title: 'Country Not Found',
          subtitle: 'This country is not in our registry yet',
        ),
      );
    }

    // Auto-select first available culture
    if (_selectedCultureKey == null) {
      final available = cultures
          .where((c) => c.hasDataFile)
          .map((c) => c.cultureKey)
          .toList();
      if (available.isNotEmpty) {
        // Use a post-frame callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedCultureKey == null) {
            setState(() => _selectedCultureKey = available.first);
          }
        });
      }
    }

    return DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(country.flagEmoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                country.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: DKColors.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows_rounded),
            tooltip: 'Compare Cultures',
            onPressed: () => context.push('/kinship/compare'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: DKColors.brandOrange,
          unselectedLabelColor: DKColors.textSecondary(context),
          indicatorColor: DKColors.brandOrange,
          labelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: [
            Tab(text: 'Languages'),
            Tab(text: 'Kinship Terms'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Languages tab
          _LanguagesTab(
            country: country,
            cultures: cultures,
            availableKeys: availableKeys,
            onCultureSelected: (key) {
              setState(() => _selectedCultureKey = key);
              _tabController.animateTo(1);
            },
          ),
          // Kinship terms tab
          _KinshipTermsTab(
            country: country,
            cultures: cultures,
            selectedCultureKey: _selectedCultureKey,
            searchController: _searchController,
            termQuery: _termQuery,
            onQueryChanged: (q) => setState(() => _termQuery = q),
            onCultureChanged: (key) =>
                setState(() => _selectedCultureKey = key),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LANGUAGES TAB — Shows all languages/cultures for the country
// ═══════════════════════════════════════════════════════════════════════

class _LanguagesTab extends StatelessWidget {
  const _LanguagesTab({
    required this.country,
    required this.cultures,
    required this.availableKeys,
    required this.onCultureSelected,
  });

  final KinshipCountry country;
  final List<GlobalCultureInfo> cultures;
  final Set<String> availableKeys;
  final ValueChanged<String> onCultureSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Country hero
          _buildCountryHero(context),

          // Culture/language cards
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: KinrelSpacing.sm,
            ),
            child: Text(
              'LANGUAGES & DIALECTS',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: DKColors.textSecondary(context),
                letterSpacing: 1.5,
              ),
            ),
          ),

          // Culture list
          ...cultures.map((culture) {
            final isAvailable = availableKeys.contains(culture.cultureKey);
            return _CultureLanguageCard(
              culture: culture,
              isAvailable: isAvailable,
              onTap: isAvailable
                  ? () => onCultureSelected(culture.cultureKey)
                  : null,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCountryHero(BuildContext context) {
    final continentColor = _getContinentColor(country.continent);

    return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(KinrelSpacing.base),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                continentColor.withValues(alpha: 0.1),
                Colors.transparent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Flag + name
              Row(
                children: [
                  Text(country.flagEmoji, style: const TextStyle(fontSize: 48)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          country.name,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: DKColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          country.nativeName,
                          style: TextStyle(
                            fontSize: 16,
                            color: continentColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Stats row
              Row(
                children: [
                  _StatBadge(
                    icon: Icons.translate_rounded,
                    label:
                        '${country.totalCultures} Language${country.totalCultures > 1 ? 's' : ''}',
                    color: continentColor,
                  ),
                  const SizedBox(width: 12),
                  _StatBadge(
                    icon: Icons.public_rounded,
                    label: country.region,
                    color: continentColor,
                  ),
                  const SizedBox(width: 12),
                  _StatBadge(
                    icon: Icons.check_circle_rounded,
                    label:
                        '${country.availableCultureCount(availableKeys)} Available',
                    color: KinrelColors.success,
                  ),
                ],
              ),
            ],
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
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

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CULTURE LANGUAGE CARD — Card for each culture/language
// ═══════════════════════════════════════════════════════════════════════

class _CultureLanguageCard extends StatelessWidget {
  const _CultureLanguageCard({
    required this.culture,
    required this.isAvailable,
    this.onTap,
  });

  final GlobalCultureInfo culture;
  final bool isAvailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final continentColor = _getContinentColor(culture.region);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
      child: DKCard(
        borderColor: isAvailable
            ? continentColor.withValues(alpha: 0.15)
            : DKColors.brandGold.withValues(alpha: 0.1),
        onTap: onTap,
        child: Row(
          children: [
            // Culture icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isAvailable
                    ? continentColor.withValues(alpha: 0.1)
                    : DKColors.brandGold.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: Center(
                child: Text(
                  culture.flagEmoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Culture info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        culture.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: DKColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: KinrelColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'LIVE',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        culture.nativeName,
                        style: TextStyle(
                          fontSize: 14,
                          color: isAvailable
                              ? continentColor
                              : DKColors.textSecondary(context),
                          fontWeight: FontWeight.w500,
                        ),
                        textDirection: culture.isRTL
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${culture.languageFamily}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: DKColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${culture.totalRelationships} terms',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: DKColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${culture.dialects.length} dialects',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: DKColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Arrow or coming soon
            if (isAvailable)
              Icon(
                Icons.chevron_right_rounded,
                color: continentColor.withValues(alpha: 0.5),
                size: 24,
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DKColors.brandGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Soon',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: DKColors.brandGold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getContinentColor(String region) {
    switch (region) {
      case 'East Asia':
        return const Color(0xFFE8612A);
      case 'South Asia':
        return const Color(0xFFF59240);
      case 'Middle East':
        return const Color(0xFFD4AF37);
      case 'Europe':
        return const Color(0xFF3B82F6);
      case 'Southeast Asia':
        return const Color(0xFF4CAF7A);
      case 'Africa':
        return const Color(0xFFC44A18);
      case 'Central Asia':
        return const Color(0xFFFF6B6B);
      case 'Northern Europe':
        return const Color(0xFF60A5FA);
      case 'Eastern Europe':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF8A7A72);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// KINSHIP TERMS TAB — Shows kinship terms for selected culture
// ═══════════════════════════════════════════════════════════════════════

class _KinshipTermsTab extends ConsumerWidget {
  const _KinshipTermsTab({
    required this.country,
    required this.cultures,
    required this.selectedCultureKey,
    required this.searchController,
    required this.termQuery,
    required this.onQueryChanged,
    required this.onCultureChanged,
  });

  final KinshipCountry country;
  final List<GlobalCultureInfo> cultures;
  final String? selectedCultureKey;
  final TextEditingController searchController;
  final String termQuery;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onCultureChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableCultures = cultures.where((c) => c.hasDataFile).toList();

    if (availableCultures.isEmpty) {
      return DKEmptyState(
        icon: Icons.hourglass_empty_rounded,
        title: 'Coming Soon',
        subtitle:
            '${country.name} kinship data is not yet available. Stay tuned!',
      );
    }

    return Column(
      children: [
        // Culture selector (horizontal chips)
        if (availableCultures.length > 1)
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: 4,
              ),
              itemCount: availableCultures.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final culture = availableCultures[index];
                final isSelected = culture.cultureKey == selectedCultureKey;
                return DKSuggestionChip(
                  label: '${culture.flagEmoji} ${culture.name}',
                  isSelected: isSelected,
                  onTap: () => onCultureChanged(culture.cultureKey),
                );
              },
            ),
          ),

        // Term search
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.sm,
          ),
          child: DKSearchField(
            hint: selectedCultureKey != null
                ? 'Search terms in ${_getCultureName(selectedCultureKey!)}...'
                : 'Search kinship terms...',
            controller: searchController,
            onChanged: onQueryChanged,
          ),
        ),

        // Terms list
        Expanded(
          child: selectedCultureKey == null
              ? DKEmptyState(
                  icon: Icons.translate_rounded,
                  title: 'Select a Language',
                  subtitle:
                      'Choose a language from above to browse kinship terms',
                )
              : _KinshipTermList(
                  cultureKey: selectedCultureKey!,
                  termQuery: termQuery,
                ),
        ),
      ],
    );
  }

  String _getCultureName(String key) {
    for (final c in cultures) {
      if (c.cultureKey == key) return c.name;
    }
    return key;
  }
}

class _KinshipTermList extends ConsumerWidget {
  const _KinshipTermList({required this.cultureKey, required this.termQuery});

  final String cultureKey;
  final String termQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(cultureKinshipDataProvider(cultureKey));

    return dataAsync.when(
      data: (data) {
        if (data == null) {
          return DKEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Failed to Load',
            subtitle: 'Could not load kinship data for this culture',
          );
        }

        var terms = data.terms.values.toList();

        // Apply search filter
        if (termQuery.isNotEmpty) {
          terms = data.search(termQuery);
        }

        // Sort by relationship key
        terms.sort((a, b) => a.relationshipKey.compareTo(b.relationshipKey));

        if (terms.isEmpty) {
          return DKEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No Terms Found',
            subtitle: termQuery.isEmpty
                ? 'No kinship terms available'
                : 'No terms match "$termQuery"',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: terms.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final term = terms[index];
            return _KinshipTermCard(
              term: term,
              cultureInfo: data.cultureInfo,
              index: index,
            );
          },
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: List.generate(
          8,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DKLoadingShimmer(
              width: double.infinity,
              height: 72,
              radius: KinrelRadius.card,
            ),
          ),
        ),
      ),
      error: (err, _) => DKErrorState(
        message: 'Error loading data',
        onRetry: () => ref.invalidate(cultureKinshipDataProvider(cultureKey)),
      ),
    );
  }
}

class _KinshipTermCard extends StatelessWidget {
  const _KinshipTermCard({
    required this.term,
    required this.cultureInfo,
    required this.index,
  });

  final GlobalKinshipTerm term;
  final GlobalCultureInfo cultureInfo;
  final int index;

  @override
  Widget build(BuildContext context) {
    final primary = term.primaryTerm;

    return DKCard(
          borderColor: DKColors.brandPurple.withValues(alpha: 0.08),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Relationship key + category
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: DKColors.brandPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      term.relationshipKey.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        color: DKColors.brandPurple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (term.relationType.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: DKColors.brandGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        term.relationType,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 9,
                          color: DKColors.brandGold,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // English term
              Text(
                term.englishTerm.isNotEmpty
                    ? term.englishTerm
                    : term.relationshipKey.snakeToTitle,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DKColors.textPrimary(context),
                ),
              ),

              // Primary native term
              if (primary != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        primary.native,
                        style: TextStyle(
                          fontSize: 18,
                          color: DKColors.brandPurple,
                          fontWeight: FontWeight.w500,
                        ),
                        textDirection: cultureInfo.isRTL
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (primary.romanization.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          primary.romanization,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: DKColors.textSecondary(context),
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // Dialect variants preview
              if (term.dialectTerms.length > 1) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.record_voice_over_rounded,
                      size: 12,
                      color: DKColors.textSecondary(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${term.dialectTerms.length} dialect forms • Tap for details',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: DKColors.textSecondary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 250.ms,
          delay: Duration(milliseconds: (index % 20) * 20),
        );
  }
}
