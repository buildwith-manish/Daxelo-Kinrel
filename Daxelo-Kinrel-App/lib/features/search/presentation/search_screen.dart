// lib/features/search/presentation/search_screen.dart
//
// DAXELO KINREL — Search Screen
//
// Instagram-style search/explore page for finding people and families.
// Supports search by name, person ID, or family ID with filter chips,
// recent searches, and rich result cards.
//
// Design tokens: KinrelColors, KinrelTypography, KinrelSpacing, KinrelRadius

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../data/repositories/search_repository.dart';
import '../../../presentation/providers/search_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../core/utils/device_tier.dart';
import '../../../presentation/widgets/skeletons/search_skeleton.dart';

// ═══════════════════════════════════════════════════════════════════════
// SEARCH SCREEN
// ═══════════════════════════════════════════════════════════════════════

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Rebuild to show/hide recent searches based on focus
    ref.invalidate(searchProvider);
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).updateQuery(query);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchProvider.notifier).clearSearch();
    _searchFocusNode.unfocus();
  }

  void _onRecentSearchTap(String query) {
    _searchController.text = query;
    ref.read(searchProvider.notifier).updateQuery(query);
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '';
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final query = ref.watch(searchQueryProvider);
    final hasQuery = query.trim().isNotEmpty;

    return DKScaffold(
      body: Column(
        children: [
          // ── Search Bar ────────────────────────────────────────────
          _buildSearchBar(query),

          // ── Filter Chip Row ───────────────────────────────────────
          const _SearchFilterChips(),

          // ── Content Area ──────────────────────────────────────────
          Expanded(child: _buildContent(hasQuery)),
        ],
      ),
    );
  }

  // ── Search Bar ───────────────────────────────────────────────────

  Widget _buildSearchBar(String query) {
    return Padding(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 15,
          color: DKColors.textPrimary(context),
        ),
        decoration: InputDecoration(
          hintText: 'Search by name, person ID, or family ID...',
          hintStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textDim,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: KinrelColors.orange,
            size: 22,
          ),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close,
                    color: KinrelColors.textDim,
                    size: 20,
                  ),
                  onPressed: _clearSearch,
                )
              : null,
          filled: true,
          fillColor: KinrelColors.darkElevated,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.xl),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.xl),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.xl),
            borderSide: BorderSide(color: KinrelColors.orange, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ── Filter Chips moved to _SearchFilterChips ConsumerWidget below ──

  // ── Content Area ─────────────────────────────────────────────────

  Widget _buildContent(bool hasQuery) {
    final state = ref.watch(searchProvider);

    // Loading state — extracted to separate widget for zero-rebuild
    if (hasQuery && state.isLoading) {
      return const _SearchLoadingWidget();
    }

    // No query entered — show empty or recent searches
    if (!hasQuery) {
      if (state.recentSearches.isEmpty) {
        return DKEmptyState(
          icon: Icons.search_rounded,
          title: 'Find Anyone, Any Family',
          subtitle: 'Search by name, unique person ID, or family ID',
        );
      }
      return _buildRecentSearches(state);
    }

    // Has query but no results
    if (state.results.isEmpty && !state.isLoading) {
      return _buildNoResults(state);
    }

    // Has results
    return _buildResults(state);
  }

  // ── Recent Searches ──────────────────────────────────────────────

  Widget _buildRecentSearches(SearchState state) {
    final searches = state.recentSearches;
    return ListView.builder(
      cacheExtent: 500,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      itemCount: searches.length + 2, // header row + spacer + search items
      itemBuilder: (context, index) {
        // Index 0: Header row
        if (index == 0) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DKColors.textPrimary(context),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(searchProvider.notifier).clearRecentSearches(),
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ],
          );
        }
        // Index 1: Spacer
        if (index == 1) {
          return const SizedBox(height: KinrelSpacing.xs);
        }
        // Index 2+: Recent search items
        final item = searches[index - 2];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 0,
            vertical: 0,
          ),
          leading: Icon(
            Icons.access_time,
            color: KinrelColors.textDim,
            size: 18,
          ),
          title: Text(
            item,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.close, color: KinrelColors.textDim, size: 16),
            onPressed: () =>
                ref.read(searchProvider.notifier).removeRecentSearch(item),
          ),
          onTap: () => _onRecentSearchTap(item),
        );
      },
    );
  }

  // ── No Results ───────────────────────────────────────────────────

  Widget _buildNoResults(SearchState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: KinrelColors.textDim,
            ),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'No results for "${state.query}"',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textSilver,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KinrelSpacing.xs),
            Text(
              'Try searching by ID directly',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Results List ─────────────────────────────────────────────────

  Widget _buildResults(SearchState state) {
    final filter = state.filter;
    final people = state.results.people;
    final families = state.results.families;

    // Build a flat list of items for lazy rendering
    final items = <_SearchResultItem>[];

    if (filter == SearchFilter.all || filter == SearchFilter.people) {
      if (filter == SearchFilter.all && people.isNotEmpty) {
        items.add(_SearchResultItem(
          type: _SearchResultItemType.peopleHeader,
          onSeeAll: () => ref
              .read(searchProvider.notifier)
              .updateFilter(SearchFilter.people),
        ));
      }
      for (final person in people) {
        items.add(_SearchResultItem(
          type: _SearchResultItemType.person,
          person: person,
        ));
      }
    }

    if (filter == SearchFilter.all || filter == SearchFilter.families) {
      if (filter == SearchFilter.all && families.isNotEmpty) {
        items.add(_SearchResultItem(
          type: _SearchResultItemType.familiesHeader,
          onSeeAll: () => ref
              .read(searchProvider.notifier)
              .updateFilter(SearchFilter.families),
        ));
      }
      for (final family in families) {
        items.add(_SearchResultItem(
          type: _SearchResultItemType.family,
          family: family,
        ));
      }
    }

    return ListView.builder(
      cacheExtent: 500,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      itemCount: items.length + 1, // +1 for bottom padding
      itemBuilder: (context, index) {
        // Bottom padding for nav bar
        if (index == items.length) {
          return const SizedBox(height: 100);
        }

        final item = items[index];
        switch (item.type) {
          case _SearchResultItemType.peopleHeader:
            return _buildSectionHeader(
              title: 'People',
              onSeeAll: item.onSeeAll!,
            );
          case _SearchResultItemType.familiesHeader:
            return _buildSectionHeader(
              title: 'Families',
              onSeeAll: item.onSeeAll!,
            );
          case _SearchResultItemType.person:
            return _buildPersonCard(item.person!);
          case _SearchResultItemType.family:
            return _buildFamilyCard(item.family!);
        }
      },
    );
  }

  // ── Section Header (for "All" filter) ───────────────────────────

  Widget _buildSectionHeader({
    required String title,
    required VoidCallback onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        top: KinrelSpacing.md,
        bottom: KinrelSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KinrelColors.gold,
              letterSpacing: 1,
            ),
          ),
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              'See all',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Person Result Card ───────────────────────────────────────────

  Widget _buildPersonCard(Person person) {
    final initials = _getInitials(person.name);
    final displayId = personDisplayId(person.id);

    return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DKCard(
            padding: 12,
            onTap: () => context.push('/member/${person.id}'),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: KinrelColors.orange.withAlpha(30),
                  child: person.photoUrl != null
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: person.photoUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 150,
                            memCacheHeight: 150,
                            fadeInDuration: const Duration(milliseconds: 150),
                            imageBuilder: (ctx, img) => Image(
                              image: img,
                              semanticLabel: '${person.name}\'s photo',
                            ),
                            placeholder: (_, __) => Text(
                              initials,
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.orange,
                              ),
                            ),
                            errorWidget: (_, __, ___) => Text(
                              initials,
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.orange,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          initials,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        ),
                ),
                const SizedBox(width: 12),

                // Name + Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: DKColors.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'ID: $displayId',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 11,
                              color: KinrelColors.textDim,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              person.familyId.isNotEmpty ? 'Family' : '',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: KinrelColors.textSilver,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Chevron
                Icon(
                  Icons.chevron_right,
                  color: KinrelColors.textDim,
                  size: 20,
                ),
              ],
            ),
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.04, end: 0, duration: 250.ms);
  }

  // ── Family Result Card ───────────────────────────────────────────

  Widget _buildFamilyCard(Family family) {
    final displayId = familyDisplayId(family.id);

    return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DKCard(
            padding: 12,
            onTap: () => context.push('/family/${family.id}'),
            child: Row(
              children: [
                // Family avatar
                _buildFamilyAvatar(family),
                const SizedBox(width: 12),

                // Name + Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        family.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: DKColors.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'ID: $displayId',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 11,
                              color: KinrelColors.textDim,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${family.memberCount} members',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              color: KinrelColors.textSilver,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Chevron
                Icon(
                  Icons.chevron_right,
                  color: KinrelColors.textDim,
                  size: 20,
                ),
              ],
            ),
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.04, end: 0, duration: 250.ms);
  }

  // ── Family Avatar (stacked member avatars or fallback) ───────────

  Widget _buildFamilyAvatar(Family family) {
    // Use family avatar URL if available
    if (family.avatarUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: family.avatarUrl!,
          fit: BoxFit.cover,
          width: 44,
          height: 44,
          memCacheWidth: 400,
          memCacheHeight: 200,
          fadeInDuration: const Duration(milliseconds: 150),
          imageBuilder: (ctx, img) => Image(
            image: img,
            semanticLabel: '${family.name} family photo',
          ),
          placeholder: (_, __) => Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: KinrelColors.amber.withAlpha(30),
            ),
            child: Center(
              child: Icon(Icons.group, color: KinrelColors.amber, size: 22),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: KinrelColors.amber.withAlpha(30),
            ),
            child: Center(
              child: Icon(Icons.group, color: KinrelColors.amber, size: 22),
            ),
          ),
        ),
      );
    }

    // Fallback: group icon with amber background
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: KinrelColors.amber.withAlpha(30),
      ),
      child: Center(
        child: Icon(Icons.group, color: KinrelColors.amber, size: 22),
      ),
    );
  }
}

// ── Filter Chips (extracted ConsumerWidget for zero-rebuild) ──────

class _SearchFilterChips extends ConsumerWidget {
  const _SearchFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(searchFilterProvider);
    final filters = [
      (SearchFilter.all, 'All'),
      (SearchFilter.people, 'People'),
      (SearchFilter.families, 'Families'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.xs,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((entry) {
            final filter = entry.$1;
            final label = entry.$2;
            final isSelected = currentFilter == filter;

            return Padding(
              padding: const EdgeInsets.only(right: KinrelSpacing.sm),
              child: GestureDetector(
                onTap: () =>
                    ref.read(searchProvider.notifier).updateFilter(filter),
                child: AnimatedContainer(
                  duration: KinrelMotion.fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? KinrelColors.orange
                        : KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? null
                        : Border.all(color: KinrelColors.darkSurface, width: 1),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : KinrelColors.textSilver,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Loading Widget (extracted for zero-rebuild optimization) ─────

class _SearchLoadingWidget extends ConsumerWidget {
  const _SearchLoadingWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SearchSkeleton(itemCount: 5);
  }
}

// ── Search result item types for lazy ListView.builder ────────────

enum _SearchResultItemType { peopleHeader, familiesHeader, person, family }

class _SearchResultItem {
  const _SearchResultItem({
    required this.type,
    this.person,
    this.family,
    this.onSeeAll,
  });

  final _SearchResultItemType type;
  final Person? person;
  final Family? family;
  final VoidCallback? onSeeAll;
}
