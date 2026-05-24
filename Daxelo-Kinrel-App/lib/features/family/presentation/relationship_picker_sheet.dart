import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/kinship/kinship_models.dart';
import '../../../core/kinship/kinship_provider.dart';

class RelationshipPickerSheet extends ConsumerStatefulWidget {
  const RelationshipPickerSheet({super.key});

  /// Show the picker and return selected relationship
  static Future<KinshipRelationship?> show(BuildContext context) {
    return showModalBottomSheet<KinshipRelationship>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => const RelationshipPickerSheet(),
    );
  }

  @override
  ConsumerState<RelationshipPickerSheet> createState() =>
      _RelationshipPickerSheetState();
}

class _RelationshipPickerSheetState
    extends ConsumerState<RelationshipPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Ensure kinship data is loaded
    ref.read(kinshipInitializedProvider.future);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.75;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KinrelColors.darkSurface,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            child: Text(
              'Select Relationship',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'Search kinship terms...',
                hintStyle: TextStyle(color: KinrelColors.textDim),
                prefixIcon:
                    Icon(Icons.search, color: KinrelColors.orange, size: 20),
                filled: true,
                fillColor: KinrelColors.darkElevated,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusSm),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Results
          Expanded(
            child: _query.isEmpty
                ? _buildCategoryList()
                : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    final categoriesAsync = ref.watch(kinshipCategoriesProvider);

    return categoriesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (e, _) => Center(
        child: Text(
          'Failed to load categories',
          style: TextStyle(color: KinrelColors.textDim),
        ),
      ),
      data: (categories) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            return _CategoryTile(
              category: categories[index],
              onTap: () => _showCategoryResults(categories[index]),
            );
          },
        );
      },
    );
  }

  void _showCategoryResults(String category) {
    ref.read(kinshipCategoryProvider.notifier).state = category;
    setState(() => _query = category);
    // Force search via the category
    _searchController.text = category;
  }

  Widget _buildSearchResults() {
    final searchAsync = ref.watch(kinshipSearchResultsProvider);

    return searchAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (e, _) => Center(
        child: Text(
          'Search failed',
          style: TextStyle(color: KinrelColors.textDim),
        ),
      ),
      data: (results) {
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off,
                    size: 48, color: KinrelColors.textDim),
                const SizedBox(height: 12),
                Text(
                  'No relationships found',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          );
        }

        // Group by category
        final grouped = <String, List<KinshipSearchResult>>{};
        for (final r in results.take(50)) {
          final cat = r.relationship.relationshipCategory;
          grouped.putIfAbsent(cat, () => []).add(r);
        }

        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
          ),
          children: [
            for (final entry in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: 12,
                  bottom: 6,
                ),
                child: Text(
                  entry.key.snakeToTitle,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                    letterSpacing: 1,
                  ),
                ),
              ),
              for (final result in entry.value)
                _RelationshipTile(
                  relationship: result.relationship,
                  onTap: () => Navigator.of(context).pop(result.relationship),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String category;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        category.snakeToTitle,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textWhite,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: KinrelColors.textDim),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _RelationshipTile extends StatelessWidget {
  final KinshipRelationship relationship;
  final VoidCallback onTap;

  const _RelationshipTile({
    required this.relationship,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: KinrelColors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          relationship.gender == 'male'
              ? Icons.male
              : relationship.gender == 'female'
                  ? Icons.female
                  : Icons.person,
          color: KinrelColors.orange,
          size: 20,
        ),
      ),
      title: Text(
        relationship.englishTerm,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: KinrelColors.textWhite,
        ),
      ),
      subtitle: Text(
        relationship.relationshipKey.replaceAll('_', ' '),
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: KinrelColors.textDim,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
