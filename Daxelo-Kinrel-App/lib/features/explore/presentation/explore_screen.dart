import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';

/// Search provider for the explore screen
final _exploreSearchProvider = StateProvider<String>((ref) => '');

/// Search results provider — searches across all family members and families
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
            subtitle: '${family.name}',
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

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Search bar
            SliverToBoxAdapter(
              child: _SearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                isSearching: _isSearching,
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // Search results or default content
            if (_isSearching)
              _buildSearchResults()
            else
              ..._buildDefaultContent(familiesAsync),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final resultsAsync = ref.watch(_exploreResultsProvider);

    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 48,
                        color: KinrelColors.textDim.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(
                      'No results found',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching for a family member or family name',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: KinrelColors.textDim,
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
            // Members section
            if (results.members.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                child: Text(
                  'Members',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
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
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
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
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: CircularProgressIndicator(color: KinrelColors.orange),
          ),
        ),
      ),
      error: (_, __) => SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Error searching',
              style: TextStyle(color: KinrelColors.textDim),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDefaultContent(AsyncValue<List<Family>> familiesAsync) {
    return [
      // Recent section
      SliverToBoxAdapter(
        child: _RecentSection(familiesAsync: familiesAsync),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),

      // Families section
      SliverToBoxAdapter(
        child: _FamiliesQuickLinks(familiesAsync: familiesAsync),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),

      // Join Family card
      SliverToBoxAdapter(
        child: _JoinFamilyCard(
          onJoin: () => _showJoinFamilyDialog(context),
        ),
      ),
    ];
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
        title: Text(
          'Join Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the family code shared with you',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textSecondary,
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
                const SnackBar(
                    content: Text('Join family coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ── Search Bar ───────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSearching
                ? KinrelColors.orange
                : KinrelColors.darkSurface.withValues(alpha: 0.6),
            width: isSearching ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                color: isSearching
                    ? KinrelColors.orange
                    : KinrelColors.orange.withValues(alpha: 0.7),
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: KinrelColors.textWhite,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Search members, families, or relationships...',
                  hintStyle: TextStyle(
                    color: KinrelColors.textDim,
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (isSearching)
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.darkElevated,
                  ),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: KinrelColors.textDim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Section ───────────────────────────────────────────────

class _RecentSection extends ConsumerWidget {
  final AsyncValue<List<Family>> familiesAsync;

  const _RecentSection({required this.familiesAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return familiesAsync.when(
      data: (families) {
        // Collect recent members from all families
        final recentMembers = <_RecentMember>[];

        for (final family in families) {
          final membersAsync = ref.watch(familyMembersProvider(family.id));
          membersAsync.whenData((members) {
            // Sort by creation date, take most recent
            final sorted = List<Person>.from(members)
              ..sort((a, b) =>
                  (b.createdAt ?? DateTime(1970))
                      .compareTo(a.createdAt ?? DateTime(1970)));
            for (final m in sorted.take(5)) {
              recentMembers.add(_RecentMember(
                name: m.name,
                familyName: family.name,
                familyId: family.id,
                gender: m.gender,
              ));
            }
          });
        }

        // Take last 5
        final display = recentMembers.take(5).toList();

        if (display.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    )),
                const SizedBox(height: 12),
                Text(
                  'No recently viewed members yet',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base),
              child: Text('Recent',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  )),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                itemCount: display.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final member = display[index];
                  return _RecentMemberCard(
                    member: member,
                    onTap: () =>
                        context.push('/family/${member.familyId}'),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RecentMember {
  final String name;
  final String familyName;
  final String familyId;
  final String? gender;

  const _RecentMember({
    required this.name,
    required this.familyName,
    required this.familyId,
    this.gender,
  });
}

class _RecentMemberCard extends StatelessWidget {
  final _RecentMember member;
  final VoidCallback onTap;

  const _RecentMemberCard({
    required this.member,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Text(
                  member.name.isNotEmpty
                      ? member.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
      ),
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
                  Text('Your Families',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      )),
                  GestureDetector(
                    onTap: () => context.go('/families'),
                    child: Text('See All',
                        style: TextStyle(
                          color: KinrelColors.orange,
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    KinrelColors.orange.withValues(alpha: 0.3),
                    KinrelColors.amber.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  family.name.isNotEmpty
                      ? family.name[0].toUpperCase()
                      : 'F',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  memberCountAsync.when(
                    data: (count) => Text(
                      '$count member${count != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    loading: () => Text('...',
                        style: TextStyle(color: KinrelColors.textDim)),
                    error: (_, __) => Text('...',
                        style: TextStyle(color: KinrelColors.textDim)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: KinrelColors.textDim, size: 20),
          ],
        ),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.card),
            gradient: LinearGradient(
              colors: [
                KinrelColors.orange.withValues(alpha: 0.12),
                KinrelColors.darkCard,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.link_rounded,
                    color: KinrelColors.orange, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join Family by Code',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter a family code to join an existing family tree',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textDim,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: KinrelColors.orange),
            ],
          ),
        ),
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.type == _ResultType.member
                      ? KinrelColors.orange.withValues(alpha: 0.12)
                      : KinrelColors.amber.withValues(alpha: 0.12),
                ),
                child: Icon(item.icon,
                    size: 18,
                    color: item.type == _ResultType.member
                        ? KinrelColors.orange
                        : KinrelColors.amber),
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
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: KinrelColors.textDim, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
