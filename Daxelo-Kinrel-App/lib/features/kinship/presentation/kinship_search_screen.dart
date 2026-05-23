import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/kinship/kinship_models.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/extensions/context_extensions.dart';

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

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: KinrelColors.darkBackground,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(color: KinrelColors.textWhite),
                        decoration: InputDecoration(
                          hintText: 'Search relationships (bua, chacha, mama...)',
                          hintStyle: TextStyle(color: KinrelColors.textDim),
                          prefixIcon: const Icon(Icons.search, color: KinrelColors.textDim),
                          suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: KinrelColors.textDim),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(kinshipSearchProvider.notifier).state = '';
                                },
                              )
                            : null,
                          filled: true,
                          fillColor: KinrelColors.darkElevated,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          ref.read(kinshipSearchProvider.notifier).state = value;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Language selector
                    Container(
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                      ),
                      child: PopupMenuButton<SupportedLanguage>(
                        icon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedLanguage.code.toUpperCase(),
                              style: TextStyle(
                                color: KinrelColors.orange,
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: KinrelColors.orange),
                          ],
                        ),
                        onSelected: (lang) => setState(() => _selectedLanguage = lang),
                        itemBuilder: (context) => SupportedLanguage.values
                          .map((lang) => PopupMenuItem(
                            value: lang,
                            child: Text('${lang.nativeName} (${lang.name})'),
                          ))
                          .toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Category filters
              categoriesAsync.when(
                data: (categories) => SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                    itemCount: categories.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return FilterChip(
                          label: const Text('All'),
                          selected: selectedCategory == null,
                          onSelected: (_) => ref.read(kinshipCategoryProvider.notifier).state = null,
                          selectedColor: KinrelColors.orange.withValues(alpha: 0.2),
                          checkmarkColor: KinrelColors.orange,
                        );
                      }
                      final cat = categories[index - 1];
                      return FilterChip(
                        label: Text(cat.snakeToTitle),
                        selected: selectedCategory == cat,
                        onSelected: (_) => ref.read(kinshipCategoryProvider.notifier).state = cat,
                        selectedColor: KinrelColors.orange.withValues(alpha: 0.2),
                        checkmarkColor: KinrelColors.orange,
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
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 64, color: KinrelColors.textDim.withValues(alpha: 0.3)),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                ? 'Search for any Indian kinship term'
                                : 'No results found',
                              style: TextStyle(
                                color: KinrelColors.textDim,
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 16,
                              ),
                            ),
                            if (_searchController.text.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Try: bua, chacha, mama, jethani...',
                                style: TextStyle(
                                  color: KinrelColors.textDim.withValues(alpha: 0.6),
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
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
                          onTap: () => context.go('/kinship/${result.relationship.relationshipKey}'),
                        );
                      },
                    );
                  },
                  loading: () => ListView(
                    padding: const EdgeInsets.all(KinrelSpacing.base),
                    children: List.generate(5, (_) => _ShimmerCard()),
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      'Error: $err',
                      style: const TextStyle(color: KinrelColors.error),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KinshipTermCard extends ConsumerWidget {
  final KinshipSearchResult result;
  final SupportedLanguage language;
  final VoidCallback onTap;

  const _KinshipTermCard({
    required this.result,
    required this.language,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rel = result.relationship;
    final termAsync = ref.watch(kinshipTermProvider(
      (key: rel.relationshipKey, language: language.name),
    ));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: KinrelColors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rel.relationshipCategory.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.orange,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, color: KinrelColors.textDim, size: 20),
              ],
            ),

            const SizedBox(height: 10),

            // English term
            Text(
              rel.englishTerm,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
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
                      Text(
                        translation.native,
                        style: TextStyle(
                          fontFamily: language.fontFamily,
                          fontSize: 16,
                          color: KinrelColors.amber,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        translation.latin,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: KinrelColors.textDim,
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
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
      ),
    );
  }
}
