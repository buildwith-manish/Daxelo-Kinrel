// lib/features/explore/presentation/explore_screen.dart
//
// DAXELO KINREL — Explore Screen
//
// Social-style explore with:
//   • Gradient search bar (blue→purple) with rounded corners
//   • Trending Kinship Terms — 2-column grid of rounded cards
//   • Kinship Dictionary — prominent card with search shortcut
//   • "Join a Family" CTA banner (coral→violet gradient)
//   • Quick access languages — horizontal scroll of language chips
//
// Uses DK* widget library, KinrelColors (purple #5D5FEF / gold #D4AF37),
// KinrelTypography, KinrelSpacing, flutter_animate.
// Both light and dark mode support.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/kinship/kinship_models.dart';
import '../../../shared/widgets/dk_components.dart';

/// Search provider for the explore screen
final _exploreSearchProvider = StateProvider<String>((ref) => '');

/// Kinship search results for the explore screen
final _exploreKinshipProvider = FutureProvider<List<KinshipSearchResult>>((ref) async {
  final query = ref.watch(_exploreSearchProvider);
  if (query.isEmpty) return [];
  await ref.watch(kinshipInitializedProvider.future);
  final service = ref.watch(kinshipServiceProvider);
  return service.search(query);
});

/// Search results provider — searches across all family members, families, and kinship terms
final _exploreResultsProvider =
    FutureProvider<_ExploreResults>((ref) async {
  final query = ref.watch(_exploreSearchProvider);
  if (query.isEmpty) return _ExploreResults.empty();

  final families = await ref.watch(familyListProvider.future);
  final matchingMembers = <_SearchResultItem>[];
  final matchingFamilies = <_SearchResultItem>[];

  for (final family in families) {
    // Match family names
    if (family.name.toLowerCase().contains(query.toLowerCase())) {
      matchingFamilies.add(_SearchResultItem(
        id: family.id,
        title: family.name,
        subtitle: 'Family',
        icon: Icons.family_restroom_rounded,
        type: _ResultType.family,
        familyId: family.id,
      ));
    }

    // Match family code
    final slug = family.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.contains(query.toLowerCase())) {
      final alreadyListed = matchingFamilies.any((f) => f.id == family.id);
      if (!alreadyListed) {
        matchingFamilies.add(_SearchResultItem(
          id: family.id,
          title: family.name,
          subtitle: 'Family code match',
          icon: Icons.family_restroom_rounded,
          type: _ResultType.family,
          familyId: family.id,
        ));
      }
    }

    // Match members
    try {
      final members =
          await ref.watch(familyMembersProvider(family.id).future);
      for (final member in members) {
        if (member.name.toLowerCase().contains(query.toLowerCase())) {
          matchingMembers.add(_SearchResultItem(
            id: member.id,
            title: member.name,
            subtitle: family.name,
            icon: Icons.person_outline_rounded,
            type: _ResultType.member,
            familyId: family.id,
          ));
        }
      }
    } catch (_) {
      // Skip families we can't load members for
    }
  }

  return _ExploreResults(
    members: matchingMembers,
    families: matchingFamilies,
  );
});

class _ExploreResults {
  final List<_SearchResultItem> members;
  final List<_SearchResultItem> families;

  const _ExploreResults({required this.members, required this.families});

  factory _ExploreResults.empty() => const _ExploreResults(
        members: [],
        families: [],
      );

  bool get isEmpty => members.isEmpty && families.isEmpty;
}

enum _ResultType { member, family }

class _SearchResultItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final _ResultType type;
  final String familyId;

  const _SearchResultItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.type,
    required this.familyId,
  });
}

// ── Trending Kinship Terms (static data for the default view) ───
const _trendingTerms = [
  ('Mother', 'माँ', 'Immediate', DKColors.brandPurple),
  ('Father', 'पिता', 'Immediate', DKColors.brandViolet),
  ('Elder Brother', 'बड़ा भाई', 'Sibling', DKColors.brandBlue),
  ('Sister', 'बहन', 'Sibling', DKColors.brandCoral),
  ('Grandmother', 'दादी', 'Extended', DKColors.brandGold),
  ('Uncle', 'चाचा', 'Extended', DKColors.brandPurple),
  ('Aunt', 'बुआ', 'Extended', DKColors.brandViolet),
  ('Cousin', 'चचेरा भाई', 'Extended', DKColors.brandBlue),
];

/// Languages for the quick access chips
const _languages = ['Hindi', 'Tamil', 'Telugu', 'Bengali', 'Marathi', 'Gujarati', 'Kannada', 'Punjabi'];

// ── Explore Screen ───────────────────────────────────────────────

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(_exploreSearchProvider.notifier).state = query;
    setState(() => _isSearching = query.isNotEmpty);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(_exploreSearchProvider.notifier).state = '';
    setState(() => _isSearching = false);
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);
    final isLight = DKColors.isLight(context);

    return DKScaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Gradient search section
          SliverToBoxAdapter(
            child: _GradientSearchSection(
              controller: _searchController,
              focusNode: _searchFocusNode,
              isSearching: _isSearching,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
              isLight: isLight,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // Search results or default content
          if (_isSearching)
            _buildSearchResults()
          else
            ..._buildDefaultContent(familiesAsync),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final resultsAsync = ref.watch(_exploreResultsProvider);
    final kinshipAsync = ref.watch(_exploreKinshipProvider);

    return resultsAsync.when(
      data: (results) {
        final kinshipResults = kinshipAsync.whenOrNull(data: (data) => data) ?? [];

        final hasNoResults = results.isEmpty && kinshipResults.isEmpty;

        if (hasNoResults) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 48,
                        color: DKColors.textSecondary(context).withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(
                      'No results found',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: DKColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching for a family member, family name, or kinship term',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: DKColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildListDelegate([
            // Kinship Terms section
            if (kinshipResults.isNotEmpty) ...[
              _SectionHeader(
                title: 'Kinship Terms',
                count: kinshipResults.length,
                onSeeAll: () => context.push('/kinship-search'),
              ),
              const SizedBox(height: 8),
              ...kinshipResults.take(5).map((result) => _KinshipResultCard(
                    result: result,
                    onTap: () => context.push('/kinship/${result.relationship.relationshipKey}'),
                  )),
              if (kinshipResults.length > 5)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base, vertical: 8),
                  child: DKButton(
                    label: 'View all ${kinshipResults.length} kinship terms →',
                    variant: DKButtonVariant.secondary,
                    size: DKButtonSize.sm,
                    fullWidth: true,
                    onPressed: () => context.push('/kinship-search'),
                  ),
                ),
              const SizedBox(height: 20),
            ],

            // Members section
            if (results.members.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                child: Text(
                  'Members',
                  style: KinrelTypography.sectionHeader.copyWith(
                    color: DKColors.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...results.members.map((item) => _SearchResultCard(
                    item: item,
                    onTap: () => context.push('/family/${item.familyId}'),
                  )),
              const SizedBox(height: 20),
            ],

            // Families section
            if (results.families.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                child: Text(
                  'Families',
                  style: KinrelTypography.sectionHeader.copyWith(
                    color: DKColors.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...results.families.map((item) => _SearchResultCard(
                    item: item,
                    onTap: () => context.push('/family/${item.familyId}'),
                  )),
            ],
          ]),
        );
      },
      loading: () => SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: DKLoadingShimmer(width: 200, height: 16),
          ),
        ),
      ),
      error: (_, __) => SliverToBoxAdapter(
        child: DKErrorState(
          message: 'Error searching',
          onRetry: () => ref.invalidate(_exploreResultsProvider),
        ),
      ),
    );
  }

  List<Widget> _buildDefaultContent(AsyncValue<List<Family>> familiesAsync) {
    return [
      // Trending Kinship Terms
      SliverToBoxAdapter(
        child: _TrendingSection()
            .animate()
            .fadeIn(duration: 350.ms)
            .slideY(begin: 0.05, end: 0),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),

      // Kinship Dictionary card
      SliverToBoxAdapter(
        child: _KinshipDictionaryCard(
          onTap: () => context.push('/kinship-search'),
        )
            .animate()
            .fadeIn(duration: 350.ms, delay: 100.ms)
            .slideY(begin: 0.05, end: 0),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),

      // CTA banner — Join a Family
      SliverToBoxAdapter(
        child: _JoinFamilyBanner(
          onJoin: () => _showJoinFamilyDialog(context),
        )
            .animate()
            .fadeIn(duration: 350.ms, delay: 150.ms)
            .slideY(begin: 0.05, end: 0),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),

      // Quick access languages
      SliverToBoxAdapter(
        child: _LanguageChips()
            .animate()
            .fadeIn(duration: 350.ms, delay: 200.ms),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),

      // Families quick links
      SliverToBoxAdapter(
        child: _FamiliesQuickLinks(familiesAsync: familiesAsync)
            .animate()
            .fadeIn(duration: 350.ms, delay: 250.ms)
            .slideY(begin: 0.05, end: 0),
      ),
    ];
  }

  void _showJoinFamilyDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: BorderSide(color: DKColors.borderColor(context)),
        ),
        title: Text(
          'Join Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: DKColors.textPrimary(context),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the family code shared with you',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: DKColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 14,
                color: DKColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: 'e.g., sharma-family-2a3b',
                hintStyle: TextStyle(color: DKColors.textSecondary(context)),
                filled: true,
                fillColor: DKColors.elevatedColor(context),
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
                style: TextStyle(color: DKColors.textSecondary(context))),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Join family coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.purple),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ── Gradient Search Section ──────────────────────────────────────

class _GradientSearchSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool isLight;

  const _GradientSearchSection({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.onChanged,
    required this.onClear,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Explore',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: DKColors.textPrimary(context),
                  )),
              // Quick search shortcut icon
              if (!isSearching)
                GestureDetector(
                  onTap: () => focusNode.requestFocus(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DKColors.brandPurple.withValues(alpha: 0.1),
                    ),
                    child: Icon(Icons.search_rounded,
                        size: 20,
                        color: DKColors.brandPurple),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Search bar with gradient in dark mode
          DKSearchField(
            controller: controller,
            hint: 'Search kinship terms, families...',
            useGradient: !isLight, // gradient in dark mode
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback? onSeeAll;

  const _SectionHeader({
    required this.title,
    required this.count,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        children: [
          Text(
            title,
            style: KinrelTypography.sectionHeader.copyWith(
              color: DKColors.textPrimary(context),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: DKColors.brandPurple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DKColors.brandPurple,
              ),
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See All',
                style: TextStyle(
                  color: KinrelColors.purple,
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Trending Kinship Terms ───────────────────────────────────────

class _TrendingSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            children: [
              Text('Trending Kinship Terms',
                  style: KinrelTypography.sectionHeader.copyWith(
                    color: DKColors.textPrimary(context),
                  )),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: DKColors.brandPurple.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.trending_up_rounded,
                    size: 14, color: DKColors.brandPurple),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.8,
            children: _trendingTerms.map((term) {
              final accentColor = term.$4;
              return GestureDetector(
                onTap: () => context.push('/kinship/${term.$1.toLowerCase().replaceAll(' ', '_')}'),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DKColors.cardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLight
                          ? accentColor.withValues(alpha: 0.15)
                          : const Color(0xFF3A3A4A),
                      width: 1,
                    ),
                    boxShadow: isLight
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: accentColor.withValues(alpha: 0.12),
                        ),
                        child: Center(
                          child: Text(
                            term.$2,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(term.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DKColors.textPrimary(context),
                                )),
                            Text(term.$3,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 9,
                                  color: DKColors.textSecondary(context),
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Kinship Dictionary Card ──────────────────────────────────────

class _KinshipDictionaryCard extends StatelessWidget {
  final VoidCallback onTap;
  const _KinshipDictionaryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: DKCard(
        onTap: onTap,
        padding: 20,
        radius: 20,
        gradient: isLight
            ? LinearGradient(
                colors: [
                  DKColors.brandPurple.withValues(alpha: 0.08),
                  DKColors.brandViolet.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [DKColors.brandDeepPurple, DKColors.darkSurface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderColor: DKColors.brandPurple.withValues(alpha: 0.25),
        child: Row(
          children: [
            // Dictionary icon with purple glow
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: DKColors.brandPurple.withValues(alpha: 0.2),
                boxShadow: [
                  BoxShadow(
                    color: DKColors.brandPurple.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.translate_rounded,
                  color: DKColors.brandPurple, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kinship Dictionary',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: DKColors.textPrimary(context),
                      )),
                  const SizedBox(height: 4),
                  Text('5,300+ terms in 15 languages',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: DKColors.textSecondary(context),
                      )),
                ],
              ),
            ),
            // Arrow with purple accent
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DKColors.brandPurple.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded,
                  size: 12, color: DKColors.brandPurple),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Join Family CTA Banner ───────────────────────────────────────

class _JoinFamilyBanner extends StatelessWidget {
  final VoidCallback onJoin;
  const _JoinFamilyBanner({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: GestureDetector(
        onTap: onJoin,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: DKColors.brandCoral.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [DKColors.brandCoral, DKColors.brandViolet],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: const Icon(Icons.group_add_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Join a Family',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enter a code to join an existing family tree',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: const Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Language Chips ───────────────────────────────────────────────

class _LanguageChips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            children: [
              Text('Quick Access Languages',
                  style: KinrelTypography.sectionHeader.copyWith(
                    color: DKColors.textPrimary(context),
                  )),
              const SizedBox(width: 8),
              Icon(Icons.language_rounded,
                  size: 16,
                  color: DKColors.brandPurple.withValues(alpha: 0.6)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: _languages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final lang = _languages[index];
              return DKSuggestionChip(
                label: lang,
                isSelected: index == 0,
                onTap: () {
                  // TODO: Filter kinship terms by language
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Families Quick Links ─────────────────────────────────────────

class _FamiliesQuickLinks extends ConsumerWidget {
  final AsyncValue<List<Family>> familiesAsync;

  const _FamiliesQuickLinks({required this.familiesAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return familiesAsync.when(
      data: (families) {
        if (families.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Your Families',
                          style: KinrelTypography.sectionHeader.copyWith(
                            color: DKColors.textPrimary(context),
                          )),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: DKColors.brandPurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${families.length}',
                            style: const TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DKColors.brandPurple,
                            )),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => context.go('/families'),
                    child: Text('See All',
                        style: TextStyle(
                          color: KinrelColors.purple,
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        )),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ...families.take(4).map((family) => Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base, vertical: 4),
                  child: _FamilyQuickLink(
                    family: family,
                    onTap: () => context.push('/family/${family.id}'),
                  ),
                )),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _FamilyQuickLink extends ConsumerWidget {
  final Family family;
  final VoidCallback onTap;

  const _FamilyQuickLink({
    required this.family,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCountAsync =
        ref.watch(familyMemberCountProvider(family.id));
    final isLight = DKColors.isLight(context);

    return DKCard(
      onTap: onTap,
      borderColor: DKColors.brandPurple.withValues(alpha: 0.15),
      child: Row(
        children: [
          DKAvatar(
            initials: family.name.isNotEmpty
                ? family.name[0].toUpperCase()
                : 'F',
            size: DKAvatarSize.md,
            borderColor: isLight
                ? DKColors.brandPurple
                : DKColors.brandPurple,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  family.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DKColors.textPrimary(context),
                  ),
                ),
                memberCountAsync.when(
                  data: (count) => Text(
                    '$count member${count != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: DKColors.textSecondary(context),
                    ),
                  ),
                  loading: () => Text('...',
                      style: TextStyle(color: DKColors.textSecondary(context))),
                  error: (_, __) => Text('...',
                      style: TextStyle(color: DKColors.textSecondary(context))),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DKColors.brandPurple.withValues(alpha: 0.08),
            ),
            child: Icon(Icons.chevron_right,
                color: DKColors.brandPurple, size: 18),
          ),
        ],
      ),
    );
  }
}

// ── Search Result Card ───────────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  final _SearchResultItem item;
  final VoidCallback onTap;

  const _SearchResultCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: 4),
      child: DKCard(
        onTap: onTap,
        child: Row(
          children: [
            DKAvatar(
              initials: item.title.isNotEmpty
                  ? item.title[0].toUpperCase()
                  : '?',
              size: DKAvatarSize.sm,
              borderColor: item.type == _ResultType.member
                  ? DKColors.brandPurple
                  : DKColors.brandGold,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DKColors.textPrimary(context),
                    ),
                  ),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: DKColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: DKColors.textSecondary(context), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Kinship Result Card ──────────────────────────────────────────

class _KinshipResultCard extends ConsumerWidget {
  final KinshipSearchResult result;
  final VoidCallback onTap;

  const _KinshipResultCard({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rel = result.relationship;
    final termAsync = ref.watch(kinshipTermProvider(
      (key: rel.relationshipKey, language: SupportedLanguage.hindi.name),
    ));

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: 4),
      child: DKCard(
        onTap: onTap,
        borderColor: DKColors.brandPurple.withValues(alpha: 0.15),
        child: Row(
          children: [
            DKAvatar(
              initials: rel.englishTerm.isNotEmpty
                  ? rel.englishTerm[0].toUpperCase()
                  : '?',
              size: DKAvatarSize.sm,
              borderColor: DKColors.brandPurple,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        rel.englishTerm,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DKColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: DKColors.brandPurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          rel.relationshipCategory.replaceAll('_', ' '),
                          style: const TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: DKColors.brandPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  termAsync.when(
                    data: (term) => Text(
                      term?.native ?? '',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: DKColors.brandPurple.withValues(alpha: 0.7),
                      ),
                    ),
                    loading: () => Text('...',
                        style: TextStyle(color: DKColors.textSecondary(context))),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: DKColors.textSecondary(context), size: 20),
          ],
        ),
      ),
    );
  }
}
