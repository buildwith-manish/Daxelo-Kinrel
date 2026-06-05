import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/kinship/kinship_provider.dart';

class RelationshipGraphPicker extends ConsumerStatefulWidget {
  const RelationshipGraphPicker({
    super.key,
    this.anchorName,
    this.anchorGender,
    this.existingRelationshipTypes = const [],
  });

  final String? anchorName;
  final String? anchorGender;
  final List<String> existingRelationshipTypes;

  static Future<String?> show(
    BuildContext context, {
    String? anchorName,
    String? anchorGender,
    List<String> existingRelationshipTypes = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RelationshipGraphPicker(
        anchorName: anchorName,
        anchorGender: anchorGender,
        existingRelationshipTypes: existingRelationshipTypes,
      ),
    );
  }

  @override
  ConsumerState<RelationshipGraphPicker> createState() =>
      _RelationshipGraphPickerState();
}

class _RelationshipGraphPickerState
    extends ConsumerState<RelationshipGraphPicker> {
  String _searchQuery = '';
  String? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();

  static const _categories = [
    'All', 'Paternal', 'Maternal', 'Marital', 'Siblings',
  ];

  static Color _categoryColor(String cat) {
    switch (cat) {
      case 'Paternal': return const Color(0xFFE07B39);
      case 'Maternal': return const Color(0xFFD4943A);
      case 'Marital':  return const Color(0xFFC8B84A);
      case 'Siblings': return Colors.lightBlueAccent;
      default:         return KinrelColors.orange;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relationshipsAsync = ref.watch(allRelationshipsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Relationship',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.anchorName != null)
                    Text(
                      'How are they related to ${widget.anchorName}?',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Search bar
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search relationship...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: KinrelColors.darkCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Category chips
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final cat = _categories[i];
                        final selected = _selectedCategory == cat ||
                            (cat == 'All' && _selectedCategory == null);
                        return GestureDetector(
                          onTap: () => setState(() =>
                              _selectedCategory = cat == 'All' ? null : cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _categoryColor(cat)
                                  : KinrelColors.darkCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? _categoryColor(cat)
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.white60,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // Relationship list
            Expanded(
              child: relationshipsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: KinrelColors.orange,
                  ),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Could not load relationships',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                data: (allRelationships) {
                  final filtered = allRelationships.where((r) {
                    final matchesSearch = _searchQuery.isEmpty ||
                        r.englishTerm.toLowerCase().contains(_searchQuery) ||
                        r.relationshipKey.toLowerCase().contains(_searchQuery) ||
                        r.searchKeywords.any((k) => k.toLowerCase().contains(_searchQuery));
                    final matchesCategory = _selectedCategory == null ||
                        r.lineage.toLowerCase() == _selectedCategory!.toLowerCase() ||
                        r.relationshipCategory.toLowerCase() == _selectedCategory!.toLowerCase();
                    return matchesSearch && matchesCategory;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No relationships found',
                        style: TextStyle(color: Colors.white38),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final rel = filtered[index];
                      final alreadyUsed = widget.existingRelationshipTypes
                          .contains(rel.relationshipKey);
                      final catColor = _categoryColor(rel.lineage);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: alreadyUsed
                              ? null
                              : () => Navigator.of(context).pop(rel.relationshipKey),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: KinrelColors.darkCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: alreadyUsed
                                    ? Colors.white10
                                    : Colors.white12,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: alreadyUsed
                                        ? Colors.white24
                                        : catColor,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rel.englishTerm,
                                        style: TextStyle(
                                          color: alreadyUsed
                                              ? Colors.white38
                                              : Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (rel.relationshipCategory.isNotEmpty)
                                        Text(
                                          rel.relationshipCategory,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    rel.lineage,
                                    style: TextStyle(
                                      color: catColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (alreadyUsed) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_circle,
                                      color: Colors.white24, size: 18),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
