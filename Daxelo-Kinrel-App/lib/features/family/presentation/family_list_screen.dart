import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/family/family_provider.dart';

class FamilyListScreen extends ConsumerWidget {
  const FamilyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familiesAsync = ref.watch(familyListProvider);

    return Scaffold(
      body: Container(
        color: KinrelColors.darkBackground,
        child: SafeArea(
          child: familiesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            ),
            error: (error, _) => _ErrorState(
              message: 'Failed to load families',
              onRetry: () => ref.invalidate(familyListProvider),
            ),
            data: (families) {
              if (families.isEmpty) {
                return _EmptyState(
                  onCreate: () => context.go('/families/create'),
                );
              }
              return RefreshIndicator(
                color: KinrelColors.orange,
                onRefresh: () async {
                  ref.invalidate(familyListProvider);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(KinrelSpacing.base),
                  itemCount: families.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final family = families[index];
                    return _FamilyCard(
                      family: family,
                      onTap: () => context.go('/family/${family.id}'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/families/create'),
        backgroundColor: KinrelColors.orange,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.family_restroom,
              size: 80,
              color: KinrelColors.textDim.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No Families Yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create your first family tree to start exploring relationships and kinship terms.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Family'),
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusSm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: KinrelColors.error.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.orange,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  final Family family;
  final VoidCallback onTap;

  const _FamilyCard({
    required this.family,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final languageName = family.primaryLanguage != null
        ? SupportedLanguage.fromCode(family.primaryLanguage!).name
        : 'English';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
              color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.15),
                borderRadius:
                    BorderRadius.circular(KinrelSpacing.radiusSm),
              ),
              child:
                  const Icon(Icons.family_restroom, color: KinrelColors.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    family.name,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        languageName,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim,
                        ),
                      ),
                      if (family.gotra != null) ...[
                        Text(
                          ' · ',
                          style: TextStyle(color: KinrelColors.textDim),
                        ),
                        Text(
                          family.gotra!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                      if (family.originVillage != null) ...[
                        Text(
                          ' · ',
                          style: TextStyle(color: KinrelColors.textDim),
                        ),
                        Flexible(
                          child: Text(
                            family.originVillage!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: KinrelColors.textDim,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: KinrelColors.textDim),
          ],
        ),
      ),
    );
  }
}
