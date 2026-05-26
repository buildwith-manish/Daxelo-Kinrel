import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/family/family_provider.dart';

class FamilyListScreen extends ConsumerStatefulWidget {
  const FamilyListScreen({super.key});

  @override
  ConsumerState<FamilyListScreen> createState() => _FamilyListScreenState();
}

class _FamilyListScreenState extends ConsumerState<FamilyListScreen> {
  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);

    return Scaffold(
      body: SafeArea(
        child: familiesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: KinrelColors.orange),
          ),
          error: (error, _) => _ErrorState(
            message: 'Failed to load families',
            onRetry: () => ref.invalidate(familyListProvider),
          ),
          data: (families) {
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: _Header(familyCount: families.length),
                ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: 16)),

                // Join Family card
                SliverToBoxAdapter(
                  child: _JoinFamilyCard(
                    onJoin: () => _showJoinFamilyDialog(context),
                  ),
                ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: 20)),

                // Family cards or empty state
                if (families.isEmpty)
                  SliverToBoxAdapter(
                    child: _EmptyState(
                      onCreate: () => context.push('/families/create'),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final family = families[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _FamilyCard(
                              family: family,
                              onTap: () =>
                                  context.push('/family/${family.id}'),
                            ),
                          );
                        },
                        childCount: families.length,
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(
                    child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/families/create'),
        backgroundColor: KinrelColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Create Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showJoinFamilyDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: KinrelColors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.link_rounded,
                  color: KinrelColors.orange, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Join Family',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                color: KinrelColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the family code shared with you to join an existing family.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 14,
                color: KinrelColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., sharma-family-2a3b',
                hintStyle: TextStyle(color: KinrelColors.textDim),
                filled: true,
                fillColor: KinrelColors.elevated,
                prefixIcon: Icon(Icons.search_rounded,
                    color: KinrelColors.textDim, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.input),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: KinrelColors.textDim)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Implement join family by code
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Join family coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.orange,
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int familyCount;
  const _Header({required this.familyCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      child: Row(
        children: [
          const Text(
            'Your Families',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$familyCount',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Join Family Card ─────────────────────────────────────────────

class _JoinFamilyCard extends StatelessWidget {
  final VoidCallback onJoin;
  const _JoinFamilyCard({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: GestureDetector(
        onTap: onJoin,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.card),
            gradient: LinearGradient(
              colors: [
                KinrelColors.amber.withValues(alpha: 0.08),
                KinrelColors.orange.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
                color: KinrelColors.amber.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.amber.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.mail_outline_rounded,
                    color: KinrelColors.amber, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join Family by Code',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enter a family code to join an existing family',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: KinrelColors.amber),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.xl, vertical: 60),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.family_restroom_rounded,
                size: 40,
                color: KinrelColors.orange.withValues(alpha: 0.5),
              ),
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
              icon: const Icon(Icons.add_rounded),
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

// ── Error State ──────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: KinrelColors.error.withValues(alpha: 0.5)),
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
                backgroundColor: KinrelColors.orange),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Family Card ──────────────────────────────────────────────────

class _FamilyCard extends ConsumerWidget {
  final Family family;
  final VoidCallback onTap;

  const _FamilyCard({
    required this.family,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCountAsync =
        ref.watch(familyMemberCountProvider(family.id));
    final languageName = family.primaryLanguage != null
        ? SupportedLanguage.fromCode(family.primaryLanguage!).name
        : 'English';

    // Generate family code
    final slug = family.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final idSuffix =
        family.id.length >= 4 ? family.id.substring(0, 4) : family.id;
    final familyCode = 'kinrel.co/f/$slug-$idSuffix';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.card),
          border: Border.all(
              color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: KinrelGradients.igniteGradient,
              ),
              child: Center(
                child: Text(
                  family.name.isNotEmpty
                      ? family.name[0].toUpperCase()
                      : 'F',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
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
                  const SizedBox(height: 3),
                  Text(
                    familyCode,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      color: KinrelColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Member count
                      memberCountAsync.when(
                        data: (count) => Row(
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 13,
                                color: KinrelColors.orange.withValues(alpha: 0.7)),
                            const SizedBox(width: 4),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: KinrelColors.textSilver,
                              ),
                            ),
                          ],
                        ),
                        loading: () => const SizedBox(
                            width: 40, height: 14),
                        error: (_, __) => const SizedBox(
                            width: 40, height: 14),
                      ),
                      const SizedBox(width: 12),
                      // Language
                      Icon(Icons.translate_rounded,
                          size: 13,
                          color: KinrelColors.textDim),
                      const SizedBox(width: 4),
                      Text(
                        languageName,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                      if (family.createdAt != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.access_time_rounded,
                            size: 13, color: KinrelColors.textDim),
                        const SizedBox(width: 4),
                        Text(
                          _timeAgo(family.createdAt!),
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.textDim,
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

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).round()}w ago';
    return '${(diff.inDays / 30).round()}mo ago';
  }
}
