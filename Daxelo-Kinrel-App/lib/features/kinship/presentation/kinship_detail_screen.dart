import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/dk_components.dart';

class KinshipDetailScreen extends ConsumerWidget {
  const KinshipDetailScreen({
    super.key,
    required this.relationshipKey,
  });

  final String relationshipKey;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTranslationsAsync =
        ref.watch(kinshipAllTranslationsProvider(relationshipKey));

    return DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
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

          final kinshipService = ref.read(kinshipServiceProvider);
          final rel = kinshipService.getRelationship(relationshipKey);

          return CustomScrollView(
            slivers: [
              // Hero section
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(KinrelSpacing.xl),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        DKColors.brandPurple.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: DKColors.brandPurple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rel.relationshipCategory
                                .replaceAll('_', ' ')
                                .toconst UpperCase(),
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DKColors.brandPurple,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // Large kinship term display
                      Text(
                        rel?.englishTerm ?? relationshipKey.snakeToTitle,
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: DKColors.textPrimary(context),
                        ),
                      )
                          .animate(onPlay: (c) => c.forward())
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.1, end: 0, duration: 400.ms),

                      if (rel?.notes != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          rel!.notes!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            color: DKColors.textSecondary(context),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaChip(icon: Icons.person, label: rel.gender),
                        _MetaChip(
                            icon: Icons.family_restroom, label: rel.lineage),
                        _MetaChip(
                            icon: Icons.format_list_numbered,
                            label: 'Generation ${rel.generation}'),
                        _MetaChip(
                            icon: Icons.category, label: rel.relationType),
                        if (rel.cousinType != null)
                          _MetaChip(
                              icon: Icons.people, label: rel.cousinType!),
                        _MetaChip(
                            icon: Icons.compare_arrows,
                            label: rel.elderYounger),
                      ],
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Relationship path
              if (rel != null && rel.relationshipPath.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    child: DKCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Relationship Path',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: DKColors.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children:
                                rel.relationshipPath.asMap().entries.expand((entry) {
                              final step = entry.value;
                              final isLast =
                                  entry.key == rel.relationshipPath.length - 1;
                              return [
                                DKSuggestionChip(
                                  label: step,
                                  isSelected: isLast,
                                  onTap: () {},
                                ),
                                if (!isLast)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    child: Icon(Icons.arrow_forward,
                                        size: 16,
                                        color: DKColors.brandPurple
                                            .withValues(alpha: 0.5)),
                                  ),
                              ];
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Translations header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base),
                  child: Text(
                    'Translations',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DKColors.textPrimary(context),
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Translations grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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

                      return DKCard(
                        padding: 10,
                        borderColor:
                            DKColors.brandPurple.withValues(alpha: 0.08),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              lang.nativeName,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 10,
                                color: DKColors.textSecondary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              translation.native,
                              style: TextStyle(
                                fontFamily: lang.fontFamily,
                                fontSize: 16,
                                color: DKColors.brandPurple,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              translation.latin,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: DKColors.textSecondary(context),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate(onPlay: (c) => c.forward())
                          .fadeIn(
                            duration: 300.ms,
                            delay: Duration(milliseconds: index * 30),
                          );
                    },
                    childCount: SupportedLanguage.values.length,
                  ),
                ),
              ),

              // Related terms section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: KinrelSpacing.base,
                    top: KinrelSpacing.xxl,
                    bottom: KinrelSpacing.sm,
                  ),
                  child: Text(
                    'Related Terms',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: DKColors.textPrimary(context),
                    ),
                  ),
                ),
              ),

              // Related terms horizontal scroll
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    itemCount: _getRelatedTerms(relationshipKey).length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final term = _getRelatedTerms(relationshipKey)[index];
                      return SizedBox(
                        width: 140,
                        child: DKCard(
                          padding: 10,
                          borderColor:
                              DKColors.brandGold.withValues(alpha: 0.15),
                          onTap: () => context.push('/kinship/$term'),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              term.snakeToTitle,
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: DKColors.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap toconst  view',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: DKColors.brandGold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.all(KinrelSpacing.base),
          chconst ildren: [
            DKLoadingShimmer(width: 200, height: 32),
            const SizedBox(height: 12),
            DKLoadingShimmer(width: double.infinity, height: 60, radius: KinrelRadius.card),
            const SizedBox(height: 12),
            ...List.generate(
              6,const 
              (_) => Padding(
                paddingconst : const EdgeInsets.only(bottom: 8),
                child: DKLoadingShimmer(
                    width: double.infinity, height: 50, radius: KinrelRadius.md),
              ),
            ),
          ],
        ),
        error: (err, _) => DKErrorState(
          message: 'Error loading kinship details',
          onRetry: () =>
              ref.invalidate(kinshipAllTranslationsProvider(relationshipKey)),
        ),
      ),
    );
  }

  List<String> _getRelatedTerms(String key) {
    // Generate related terms based on the key
    final parts = key.split('_');
    final related = <String>[];
    if (parts.contains('paternal')) {
      related.addAll(['maternal_${parts.last}', key.replaceAll('father', 'grandfather'), key.replaceAll('mother', 'grandmother')]);
    } else if (parts.contains('maternal')) {
      related.addAll(['paternal_${parts.last}', key.replaceAll('father', 'grandfather'), key.replaceAll('mother', 'grandmother')]);
    } else {
      related.addAll(['paternal_$key', 'maternal_$key']);
    }
    // Filter out duplicates and the original
    return related.where((r) => r != key).toSet().take(5).toList();
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: DKColors.brandPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: DKColors.brandPurple.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: DKColors.brandPurple),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: DKColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
