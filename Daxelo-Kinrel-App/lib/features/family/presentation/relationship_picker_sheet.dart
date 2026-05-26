import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/kinship/kinship_models.dart';
import '../../../core/kinship/kinship_service.dart';
import '../../../core/kinship/kinship_provider.dart';

/// Contextual relationship picker that shows smart suggestions based on
/// existing family structure. When linking Person A to Person B, the header
/// asks "How is [Person B] related to [Person A]?" and surfaces the most
/// relevant kinship terms as quick-select chips.
class RelationshipPickerSheet extends ConsumerStatefulWidget {
  const RelationshipPickerSheet({
    super.key,
    this.personAName,
    this.personBName,
    this.existingRelationshipTypes = const [],
  });

  /// Name of the person we are linking FROM (the anchor)
  final String? personAName;

  /// Name of the person we are linking TO
  final String? personBName;

  /// Existing relationships of personA (relationshipType strings)
  /// Used to determine smart suggestions
  final List<String> existingRelationshipTypes;


  /// Show the picker and return selected relationship key
  static Future<String?> show(
    BuildContext context, {
    String? personAName,
    String? personBName,
    List<String> existingRelationshipTypes = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => RelationshipPickerSheet(
        personAName: personAName,
        personBName: personBName,
        existingRelationshipTypes: existingRelationshipTypes,
      ),
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
  final _scrollController = ScrollController();

  // Common quick-select relationships
  static const _quickSelectKeys = [
    'father',
    'mother',
    'husband',
    'wife',
    'son',
    'daughter',
    'brother',
    'sister',
    'uncle',
    'aunt',
    'grandfather',
    'grandmother',
  ];

  @override
  void initState() {
    super.initState();
    // Ensure kinship data is loaded
    ref.read(kinshipInitializedProvider.future);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Compute smart suggestion keys based on what Person A is missing
  List<String> get _suggestedKeys {
    final existing = widget.existingRelationshipTypes.toSet();
    final suggestions = <String>[];

    // If no parents linked, suggest father/mother
    final hasParent = existing
        .any((t) => ['father', 'mother', 'parent'].contains(t));
    if (!hasParent) {
      suggestions.addAll(['father', 'mother']);
    }

    // If no spouse linked, suggest husband/wife
    final hasSpouse =
        existing.any((t) => ['spouse', 'husband', 'wife'].contains(t));
    if (!hasSpouse) {
      suggestions.addAll(['husband', 'wife']);
    }

    // If has parents but no siblings, suggest brother/sister
    if (hasParent) {
      final hasSibling = existing
          .any((t) => ['brother', 'sister', 'sibling'].contains(t));
      if (!hasSibling) {
        suggestions.addAll(['brother', 'sister']);
      }
    }

    // If has parents, suggest uncle/aunt
    if (hasParent) {
      suggestions.addAll(['uncle', 'aunt']);
    }

    // If has spouse, suggest son/daughter
    if (hasSpouse) {
      suggestions.addAll(['son', 'daughter']);
    }

    // Always suggest grandparents if not present
    final hasGrandparent = existing.any(
        (t) => ['grandfather', 'grandmother', 'grandparent'].contains(t));
    if (!hasGrandparent) {
      suggestions.addAll(['grandfather', 'grandmother']);
    }

    // Remove duplicates and already-existing ones
    final seen = <String>{};
    return suggestions.where((s) {
      if (seen.contains(s) || existing.contains(s)) return false;
      seen.add(s);
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.8;

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

          // Contextual header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KinrelSpacing.base,
              KinrelSpacing.base,
              KinrelSpacing.base,
              KinrelSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headerconst Title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                if (widget.personAName != null &&
                    widget.personBName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'How isconst  ${widget.personBName} related to ${widget.personAName}?',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Quick-select chips
          if (_suggestedKeys.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
              ),
              child: _buildQuickChips(),
            ),

          const SizedBox(height: 8),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
            ),
            child: TextField(
              controller: _searchController,
              onChangconst ed: (v) => setState(() => _query = v),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'const Search kinship terms...',
                hintStyle: TextStyle(color: KinrelColors.textDim),
                prefconst ixIcon:
                    Icon(Icons.search, color: KinrelColors.purple, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButtconst on(
                        icon: Icon(Icons.clear,
                            color: KinrelColors.textDim, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
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
          const SizedBox(height: 8),

          // Results
          Expanded(
            child: _query.isEmpty ? _buildSuggestionsList() : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  String get _headerTitle {
    if (widget.personAName != null && widget.personBName != null) {
      return 'Link ${widget.personBName}';
    }
    return 'Select Relationship';
  }

  Widget _buildQuickChips() {
    final kinshipService = ref.read(kinshipServiceProvider);
    final chips = _suggestedKeys.take(8).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map((key) {
        final rel = kinshipService.getRelationship(key);
        final label = rel?.englishTerm ?? key.snakeToTitle;
        return _QuickChip(
          label: label,
          onTap: () => Navigator.of(context).pop(key),
        );
      }).toList(),
    );
  }

  Widget _buildSuggestionsList() {
    final kinshipService = ref.read(kinshipServiceProvider);

    // All quick-select keys that are still available
    final availableQuickKeys = _quickSelectKeys
        .where((k) => !widget.existingRelationshipTypes.contains(k))
        .toList();

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
      ),
      children: [
        // Common relationships section
        ifconst  (availableQuickKeys.isNotEmpty) ...[
          _SectionHeader(title: 'Common Relationships'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: availableQuickKeys.map((key) {
              final rel = kinshipService.getRelationship(key);
              final label = rel?.englishTerm ?? key.snakeToTitle;
              final genderIcon = _genderIcon(rel?.gender);
              return _SuggestionChip(
                label: label,
                genderIcon: genderIcon,
                lineage: rel?.lineage,
                onTap: () => Navigator.of(context).pop(key),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        const // By category browse
        _SectionHeader(title: 'Browse by Category'),
        const SizedBox(height: 4),
        ..._buildCategoryTiles(kinshipService),
      ],
    );
  }

  List<Widget> _buildCategoryTiles(KinshipService kinshipService) {
    final categories = kinshipService.categories;
    return categories.map((category) {
      final count = kinshipService.getByCategory(category).length;
      return _CategoryTile(
        category: category,
        count: count,
        onTap: () => _showCategoryResults(category),
      );
    }).toList();
  }

  void _showCategoryResults(String category) {
    setState(() {
      _query = category;
      _searchController.text = category;
    });
    ref.read(kinshipSearchProvider.notifier).state = category;
  }

  Widget _buildSearchResults() {
    final searchAsync = ref.watch(kinshipSearchResultsProvider);

    return searchAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.purple),
      ),const 
      error: (econst , _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          chconst ildren: [
            Icon(Icons.search_off, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            Text(
              'Searchconst  failed',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
      data: (results) {
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              chconst ildren: [
                Icon(Icons.search_off, size: 48, color: KinrelColors.textDim),
                const SizedBox(height: 12),
                Text(
                  'No relconst ationships found for "$_query"',
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
        for (final r in results.take(60)) {
          final cat = r.relationship.relationshipCategory;
          grouped.putIfAbsent(cat, () => []).add(r);
        }

        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
          ),
          children: [
            for (final entry in grouped.entries) ...[
              _SectionHeader(title: entry.key.snakeToTitle),
              const SizedBox(height: 4),
              for (final result in entry.value)
                _ContextualRelationshipTile(
                  relationship: result.relationship,
                  kinshipService: ref.read(kinshipServiceProvider),
                  onTap: () =>
                      Navigator.of(context).pop(result.relationship.relationshipKey),
                ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  IconData _genderIcon(String? gender) {
    switch (gender) {
      case 'male':
        return Icons.male;
      case 'female':
        return Icons.female;
      default:
        return Icons.person;
    }
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    return Material(
      color: KinrelColors.purple.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: KinrelColors.purple.withValues(alpha: 0.3),
            ),
          ),
          child: Teconst xt(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KinrelColors.purple,
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.genderIcon,
    this.lineage,
    required this.onTap,
  });

  final String label;
  final IconData genderIcon;
  final String? lineage;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    return Material(
      color: KinrelColors.darkElevated,
      borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
            border: Border.all(
              color: KinrelColors.darkSurface.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(genderIcon, size: 14, color: KinrelColors.amber),
              const Sizconst edBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textWhite,
                ),
              ),
              if (lineage != null && lineage!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _lineageColor(lineage!).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    lineage!.snakeToTitle,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _lineageColor(lineage!),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _lineageColor(String lineage) {
    switch (lineage.toLowerCase()) {
      case 'paternal':
        return KinrelColors.purple;
      case 'maternal':
        return KinrelColors.amber;
      case 'marital':
        return KinrelColors.durgaPurple;
      default:
        return KinrelColors.textSilver;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Paddconst ing(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: KinrelColors.gold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
  });

  final String category;
  final int count;
  final VoidCallback onTap;


  @override
  Widget build(const BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        category.snakeToTitle,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textWhite,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const KinrelColors.darkSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
          const       color: KinrelColors.textDim,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: KinrelColors.textDim, size: 18),
        ],
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _ContextualRelationshipTile extends StatelessWidget {
  const _ContextualRelationshipTile({
    required this.relationship,
    required this.kinshipService,
    required this.onTap,
  });

  final KinshipRelationship relationship;
  final KinshipService kinshipService;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    final nativeTranslation =
        kinshipService.getKinshipTerm(relationship.relationshipKey, 'hindi');

    return ListTile(
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _genderBgColor(relationship.gender),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _genderIcon(relationship.gender),
          color: _genderFgColor(relationship.gender),
          size: 20,
        ),
      ),const 
      title: Row(
        children: [
          Expanded(
            child: Text(
              relationship.englishTerm,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          if (relationship.lineage.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _lineageColor(relationship.lineage).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                relationship.lineage.snakeToTitle,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: _lineageColor(relationship.lineage),
                  letterSpacing: 0.3,
                ),
              ),
            ),const 
        ],
      ),
      subtitle: nativeTranslation != null
          ? Text(
              nativeTranslation.native,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSconst ize: 12,
                color: KinrelColors.textDim,
              ),
            )
          : Text(
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

  Color _genderBgColor(String gender) {
    switch (gender) {
      case 'male':
        return KinrelColors.info.withValues(alpha: 0.1);
      case 'female':
        return KinrelColors.holiPink.withValues(alpha: 0.1);
      default:
        return KinrelColors.purple.withValues(alpha: 0.1);
    }
  }

  Color _genderFgColor(String gender) {
    switch (gender) {
      case 'male':
        return KinrelColors.info;
      case 'female':
        return KinrelColors.holiPink;
      default:
        return KinrelColors.purple;
    }
  }

  IconData _genderIcon(String gender) {
    switch (gender) {
      case 'male':
        return Icons.male;
      case 'female':
        return Icons.female;
      default:
        return Icons.person;
    }
  }

  Color _lineageColor(String lineage) {
    switch (lineage.toLowerCase()) {
      case 'paternal':
        return KinrelColors.purple;
      case 'maternal':
        return KinrelColors.amber;
      case 'marital':
        return KinrelColors.durgaPurple;
      default:
        return KinrelColors.textSilver;
    }
  }
}
