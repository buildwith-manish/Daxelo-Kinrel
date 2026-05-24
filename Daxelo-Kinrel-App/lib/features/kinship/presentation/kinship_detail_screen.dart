import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/extensions/context_extensions.dart';

class KinshipDetailScreen extends ConsumerWidget {
  final String relationshipKey;

  const KinshipDetailScreen({
    super.key,
    required this.relationshipKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTranslationsAsync = ref.watch(kinshipAllTranslationsProvider(relationshipKey));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Share the relationship
              Share.share('Check out this kinship term: $relationshipKey');
            },
          ),
        ],
      ),
      body: allTranslationsAsync.when(
        data: (translations) {
          if (translations == null) {
            return const Center(child: Text('Relationship not found'));
          }

          // Get the relationship metadata
          final kinshipService = ref.read(kinshipServiceProvider);
          final rel = kinshipService.getRelationship(relationshipKey);

          return CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(KinrelSpacing.xl),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [KinrelColors.orange.withValues(alpha: 0.1), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category badge
                      if (rel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: KinrelColors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rel.relationshipCategory.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.orange,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // English term
                      Text(
                        rel?.englishTerm ?? relationshipKey.snakeToTitle,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),

                      if (rel?.notes != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          rel!.notes!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Metadata tags
              if (rel != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaChip(icon: Icons.person, label: rel.gender),
                        _MetaChip(icon: Icons.family_restroom, label: rel.lineage),
                        _MetaChip(icon: Icons.format_list_numbered, label: 'Generation ${rel.generation}'),
                        _MetaChip(icon: Icons.category, label: rel.relationType),
                        if (rel.cousinType != null)
                          _MetaChip(icon: Icons.people, label: rel.cousinType!),
                        _MetaChip(icon: Icons.compare_arrows, label: rel.elderYounger),
                      ],
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Relationship path
              if (rel != null && rel.relationshipPath.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Relationship Path',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: rel.relationshipPath.asMap().entries.expand((entry) {
                            final step = entry.value;
                            final isLast = entry.key == rel.relationshipPath.length - 1;
                            return [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: KinrelColors.darkElevated,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  step,
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 13,
                                    color: KinrelColors.amber,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (!isLast)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Icon(Icons.arrow_forward, size: 16, color: KinrelColors.textDim),
                                ),
                            ];
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Translations header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                  child: Text(
                    'Translations',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Translations grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.2,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final lang = SupportedLanguage.values[index];
                      final translation = translations[lang.name];
                      if (translation == null) return const SizedBox.shrink();

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KinrelColors.darkCard,
                          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                          border: Border.all(
                            color: KinrelColors.darkSurface.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              lang.nativeName,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 10,
                                color: KinrelColors.textDim,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              translation.native,
                              style: TextStyle(
                                fontFamily: lang.fontFamily,
                                fontSize: 16,
                                color: KinrelColors.amber,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              translation.latin,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: KinrelColors.textDim,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: SupportedLanguage.values.length,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: KinrelColors.error))),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: KinrelColors.orange),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }
}
