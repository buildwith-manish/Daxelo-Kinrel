import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/kinship/global_kinship_models.dart';
import '../../../core/kinship/global_kinship_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/utils/device_tier.dart';

/// Cross-Cultural Comparison Screen
///
/// Compare how a relationship term is expressed across cultures:
///   - Dropdown/chips to select relationship key
///   - Horizontal scrollable cards showing the term in each culture
///   - Color-coded by region
///   - Shows native script, romanization, and notes
class CrossCulturalComparisonScreen extends ConsumerStatefulWidget {
  const CrossCulturalComparisonScreen({super.key});

  @override
  ConsumerState<CrossCulturalComparisonScreen> createState() =>
      _CrossCulturalComparisonScreenState();
}

class _CrossCulturalComparisonScreenState
    extends ConsumerState<CrossCulturalComparisonScreen> {
  String? _selectedKey;
  final _searchController = TextEditingController();
  bool _showKeyPicker = false;

  // Common relationship keys for quick selection
  static const _commonKeys = [
    'father',
    'mother',
    'brother',
    'sister',
    'son',
    'daughter',
    'grandfather',
    'grandmother',
    'uncle',
    'aunt',
    'cousin',
    'nephew',
    'niece',
    'husband',
    'wife',
  ];

  @override
  void initState() {
    super.initState();
    _selectedKey = 'father';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Cross-Cultural Compare',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: DKColors.textPrimary(context),
          ),
        ),
      ),
      body: Column(
        children: [
          // Relationship key selector
          _buildKeySelector(context),

          // Comparison results
          Expanded(
            child: _selectedKey == null
                ? DKEmptyState(
                    icon: Icons.compare_arrows_rounded,
                    title: 'Select a Relationship',
                    subtitle:
                        'Choose a relationship to compare across cultures',
                  )
                : ref
                      .watch(crossCulturalComparisonProvider(_selectedKey!))
                      .when(
                        data: (comparison) {
                          if (comparison == null ||
                              comparison.entries.isEmpty) {
                            return DKEmptyState(
                              icon: Icons.language_rounded,
                              title: 'No Comparison Available',
                              subtitle:
                                  'Load cultures first from the Global Kinship screen',
                            );
                          }
                          return _buildComparisonResults(context, comparison);
                        },
                        loading: () => ListView(
                          padding: const EdgeInsets.all(KinrelSpacing.base),
                          children: List.generate(
                            6,
                            (_) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: DKLoadingShimmer(
                                width: double.infinity,
                                height: 90,
                                radius: KinrelRadius.card,
                              ),
                            ),
                          ),
                        ),
                        error: (err, _) => DKErrorState(
                          message: 'Error loading comparison data',
                          onRetry: () => ref.invalidate(
                            crossCulturalComparisonProvider(_selectedKey!),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeySelector(BuildContext context) {
    return Column(
      children: [
        // Current selection header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.sm,
          ),
          child: DKCard(
            padding: 12,
            borderColor: DKColors.brandPurple.withValues(alpha: 0.15),
            onTap: () => setState(() => _showKeyPicker = !_showKeyPicker),
            child: Row(
              children: [
                Icon(
                  Icons.compare_arrows_rounded,
                  size: 20,
                  color: DKColors.brandPurple,
                ),
                const SizedBox(width: 8),
                Text(
                  'Compare:',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: DKColors.textSecondary(context),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _selectedKey?.snakeToTitle ?? 'Select...',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DKColors.textPrimary(context),
                    ),
                  ),
                ),
                Icon(
                  _showKeyPicker
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: DKColors.brandPurple,
                ),
              ],
            ),
          ),
        ),

        // Key picker panel
        if (_showKeyPicker) _buildKeyPickerPanel(context),
      ],
    );
  }

  Widget _buildKeyPickerPanel(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: DKColors.cardColor(context),
        border: Border(
          top: BorderSide(
            color: DKColors.brandPurple.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.sm),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: DKColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: 'Search relationship...',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: DKColors.textSecondary(context),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: DKColors.textSecondary(context),
                ),
                filled: true,
                fillColor: DKColors.elevatedColor(context),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Common key chips
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _getFilteredKeys().map((key) {
                  final isSelected = key == _selectedKey;
                  return DKSuggestionChip(
                    label: key.snakeToTitle,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedKey = key;
                        _showKeyPicker = false;
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getFilteredKeys() {
    var keys = _commonKeys;
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      keys = keys.where((k) => k.toLowerCase().contains(query)).toList();
    }
    return keys;
  }

  Widget _buildComparisonResults(
    BuildContext context,
    CrossCulturalComparison comparison,
  ) {
    final byRegion = comparison.byRegion;
    final regions = byRegion.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                    comparison.englishTerm,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: DKColors.textPrimary(context),
                    ),
                  )
                  .animate(onPlay: (c) => c.forward())
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0, duration: 400.ms),
              const SizedBox(height: 4),
              Text(
                'Across ${comparison.entries.length} culture${comparison.entries.length > 1 ? 's' : ''}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: DKColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),

        // Region sections
        ...regions.map((region) {
          final entries = byRegion[region]!;
          return _buildRegionSection(context, region, entries);
        }),
      ],
    );
  }

  Widget _buildRegionSection(
    BuildContext context,
    String region,
    List<CrossCulturalEntry> entries,
  ) {
    final regionColor = _getRegionColor(region);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Region header
        Padding(
          padding: const EdgeInsets.only(
            left: KinrelSpacing.base,
            top: KinrelSpacing.xl,
            bottom: KinrelSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: regionColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                region,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: regionColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: regionColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${entries.length}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: regionColor,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Horizontal scrollable culture cards
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _ComparisonCard(
                entry: entry,
                regionColor: regionColor,
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getRegionColor(String region) {
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

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.entry,
    required this.regionColor,
    required this.index,
  });

  final CrossCulturalEntry entry;
  final Color regionColor;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
          width: 160,
          child: DKCard(
            padding: 12,
            borderColor: regionColor.withValues(alpha: 0.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Culture name + flag
                Row(
                  children: [
                    Text(entry.flagEmoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.cultureName,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DKColors.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Native term
                Text(
                  entry.nativeTerm,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: regionColor,
                  ),
                  textDirection: entry.isRTL
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 2),

                // Romanization
                if (entry.romanization.isNotEmpty)
                  Text(
                    entry.romanization,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: DKColors.textSecondary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                const Spacer(),

                // Dialect / formality tag
                if (entry.dialect.isNotEmpty || entry.formality.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: regionColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      [
                        entry.dialect,
                        entry.formality,
                      ].where((s) => s.isNotEmpty).join(' • '),
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 8,
                        color: regionColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: index * 60),
        )
        .slideX(begin: 0.1, end: 0, duration: 300.ms);
  }
}
