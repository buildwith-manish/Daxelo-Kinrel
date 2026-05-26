import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/kinship/kinship_models.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../shared/widgets/dk_components.dart';

class KinshipSearchScreen extends ConsumerStatefulWidget {
  const KinshipSearchScreen({super.key});

  @override
  ConsumerState<KinshipSearchScreen> createState() => _KinshipSearchScreenState();
}

class _KinshipSearchScreenState extends ConsumerState<KinshipSearchScreen> {
  final _searchController = TextEditingController();
  SupportedLanguage _selectedLanguage = SupportedLanguage.english;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(kinshipSearchResultsProvider);
    final categoriesAsync = ref.watch(kinshipCategoriesProvider);
    final selectedCategory = ref.watch(kinshipCategoryProvider);

    return DKScaffold(
      body: Column(
        children: [
          // Search bar (gradient in dark mode)
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            child: DKSearchField(
              hint: 'Search relationships (bua, chacha, mama...)',
              controller: _searchController,
              useGradient: DKColors.isLight(context) ? false : true,
              onChanged: (value) {
                ref.read(kinshipSearchProvider.notifier).state = value;
                setState(() {});
              },
              onSubmitted: (value) {
                ref.read(kinshipSearchProvider.notifier).state = value;
              },
            ),
          ),

          // Language selector chips
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
              itemCount: SupportedLanguage.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final lang = SupportedLanguage.values[index];
                final isSelected = lang == _selectedLanguage;
                return DKSuggestionChip(
                  label: lang.nativeName,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedLanguage = lang),
                );
              },
            ),
          ),

          // Category filters
          categoriesAsync.when(
            data: (categories) => SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base, vertical: 4),
                itemCount: categories.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return DKSuggestionChip(
                      label: 'All',
                      isSelected: selectedCategory == null,
                      onTap: () =>
                          ref.read(kinshipCategoryProvider.notifier).state = null,
                    );
                  }
                  final cat = categories[index - 1];
                  return DKSuggestionChip(
                    label: cat.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' '),
                    isSelected: selectedCategory == cat,
                    onTap: () =>
                        ref.read(kinshipCategoryProvider.notifier).state = cat,
                  );
                },
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),

          // Results
          Expanded(
            child: searchResults.when(
              data: (results) {
                if (results.isEmpty) {
                  return DKEmptyState(
                    icon: Icons.search_rounded,
                    title: _searchController.text.isEmpty
                        ? 'Search Kinship Terms'
                        : 'No Results Found',
                    subtitle: _searchController.text.isEmpty
                        ? 'Try: bua, chacha, mama, jethani...'
                        : 'No terms match "${_searchController.text}"',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                    vertical: 8,
                  ),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return _KinshipTermCard(
                      result: result,
                      language: _selectedLanguage,
                      index: index,
                      onTap: () => context
                          .push('/kinship/${result.relationship.relationshipKey}'),
                    );
                  },
                );
              },
              loading: () => ListView(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                children: List.generate(
                  5,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: DKLoadingShimmer(
                        width: double.infinity, height: 80, radius: KinrelRadius.card),
                  ),
                ),
              ),
              error: (err, _) => DKErrorState(
                message: 'Failed to load kinship data',
                onRetry: () => ref.invalidate(kinshipSearchResultsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KinshipTermCard extends ConsumerWidget {
  const _KinshipTermCard({
    required this.result,
    required this.language,
    required this.index,
    required this.onTap,
  });

  final KinshipSearchResult result;
  final SupportedLanguage language;
  final int index;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rel = result.relationship;
    final termAsync = ref.watch(kinshipTermProvider(
      (key: rel.relationshipKey, language: language.name),
    ));

    return DKCard(
      borderColor: DKColors.brandPurple.withValues(alpha: 0.12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with category badge
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DKColors.brandPurple.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.circular(6),
                ),
                child: const Text(
                  rel.relationshipCategory.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: DKColors.brandPurple,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              // Relationship key
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DKColors.brandGold.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.circular(4),
                ),
                child: const Text(
                  rel.relationshipKey.replaceAll('_', ' '),
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    color: DKColors.brandGold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: DKColors.brandPurple.withValues(alpha: 0.5), size: 20),
            ],
          ),

          const SizedBox(height: 10),

          // English term
          Text(
            rel.englishTerm,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: DKColors.textPrimary(context),
            ),
          ),

          // Native translation
          termAsync.when(
            data: (translation) {
              if (translation == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Text(
                      translation.native,
                      style: const TextStyle(
                        fontFamily: language.fontFamily,
                        fontSize: 16,
                        color: DKColors.brandPurple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      translation.latin,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: DKColors.textSecondary(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Tags
          const SizedBox(height: 8),
          Row(
            children: [
              _TagChip(label: rel.gender),
              const SizedBox(width: 6),
              _TagChip(label: rel.lineage),
              const SizedBox(width: 6),
              if (rel.cousinType != null) ...[
                _TagChip(label: rel.cousinType!),
                const SizedBox(width: 6),
              ],
              _TagChip(label: 'Gen ${rel.generation}'),
            ],
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: index * 40),
        )
        .slideX(begin: 0.05, end: 0, duration: 300.ms);
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DKColors.brandPurple.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.circular(4),
        border: Border.all(
          color: DKColors.brandPurple.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          color: DKColors.textSecondary(context),
        ),
      ),
    );
  }
}
