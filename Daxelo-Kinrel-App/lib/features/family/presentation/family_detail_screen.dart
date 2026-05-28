import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../presentation/widgets/skeletons/member_list_skeleton.dart';
import 'family_tree_canvas.dart';
import 'add_person_sheet.dart';
import 'person_detail_sheet.dart';
import 'relationship_builder_screen.dart';
import '../../core/utils/device_tier.dart';
import '../../../core/utils/smart_preloader.dart';
import '../../../core/utils/share_helper.dart';
import '../../profile/data/profile_provider.dart';

class FamilyDetailScreen extends ConsumerStatefulWidget {
  FamilyDetailScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends ConsumerState<FamilyDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));
    const primaryColor = KinrelColors.purple;

    return DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          tooltip: 'Go back',
          onPressed: () => context.pop(),
        ),
        title: detailAsync.when(
          loading: () => Text(
            'Family Tree',
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          error: (_, __) => Text(
            'Family Tree',
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          data: (detail) => Text(
            detail?.family.name ?? 'Family Tree',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined),
            tooltip: 'Share Family',
            onPressed: () => _shareFamily(context),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => _showFamilySettings(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryColor,
          unselectedLabelColor: KinrelColors.textSilver,
          indicatorColor: primaryColor,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: 'Graph'),
            Tab(text: 'Members'),
            Tab(text: 'Activity'),
          ],
        ),
      ),
      body: detailAsync.when(
        loading: () => const _FamilyDetailLoadingWidget(),
        error: (error, _) => DKErrorState(
          message: 'Failed to load family data',
          onRetry: () => ref.invalidate(familyDetailProvider(widget.familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return DKErrorState(
              message: 'Family not found',
              onRetry: () =>
                  ref.invalidate(familyDetailProvider(widget.familyId)),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _GraphTab(detail: detail, familyId: widget.familyId),
              _MembersTab(detail: detail, familyId: widget.familyId),
              _ActivityTab(detail: detail, familyId: widget.familyId),
            ],
          );
        },
      ),
      // Bottom action bar
      floatingActionButton: detailAsync.when(
        loading: () => null,
        error: (_, __) => null,
        data: (detail) {
          if (detail == null) return null;
          return _BottomActionBar(
            familyId: widget.familyId,
            familyName: detail.family.name,
            memberCount: detail.members.length,
          );
        },
      ),
    );
  }

  void _shareFamily(BuildContext context) {
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final familyName = detailAsync.valueOrNull?.family.name ?? 'Family';
    ShareHelper.shareFamily(
      familyId: widget.familyId,
      familyName: familyName,
    );
  }

  void _showFamilySettings(BuildContext context) {
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final family = detailAsync.valueOrNull?.family;
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isCreator =
        family != null &&
        family.createdBy != null &&
        family.createdBy == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              child: Row(
                children: [
                  Icon(
                    Icons.settings_outlined,
                    color: KinrelColors.purple,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Family Settings',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: KinrelColors.border, height: 1),

            // Family info section
            if (family != null) ...[
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    DKAvatar(
                      initials: family.name.isNotEmpty
                          ? family.name[0].toUpperCase()
                          : 'F',
                      size: DKAvatarSize.md,
                      backgroundColor: KinrelColors.purple,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            family.name,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textWhite,
                            ),
                          ),
                          if (family.familyCode != null) ...[
                            SizedBox(height: 2),
                            Text(
                              'Code: ${family.familyCode}',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                color: KinrelColors.textSilver,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: KinrelColors.border, height: 1),
            ],

            // Share option
            _QuickActionTile(
              icon: Icons.share_outlined,
              label: 'Share Family Code',
              onTap: () {
                Navigator.pop(ctx);
                _shareFamily(context);
              },
            ),

            // Only show delete option to the creator
            if (isCreator) ...[
              Divider(color: KinrelColors.border, height: 1),
              _QuickActionTile(
                icon: Icons.delete_outline,
                label: 'Delete Family',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteFamily(context, family.name);
                },
              ),
            ] else if (family != null && family.createdBy != null) ...[
              // Show info that only the creator can delete
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base,
                  vertical: KinrelSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: KinrelColors.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Only the family creator can delete this family',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFamily(BuildContext context, String familyName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: KinrelColors.error,
              size: 24,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Delete "$familyName"?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will permanently delete this family and all its members, relationships, and data.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: KinrelColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // Close dialog
              await _performDeleteFamily(context);
            },
            child: Text(
              'Delete Family',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w600,
                color: KinrelColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteFamily(BuildContext context) async {
    // Show a loading indicator
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: CircularProgressIndicator(color: KinrelColors.purple),
        ),
      ),
    );

    try {
      await deleteFamily(ref: ref, familyId: widget.familyId);

      // Close loading indicator
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Navigate back to family list
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Family deleted successfully'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/families');
      }
    } catch (e) {
      // Close loading indicator
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete family: ${e.toString().split('\n').first}',
            ),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ── Loading Widget (extracted for zero-rebuild optimization) ─────

class _FamilyDetailLoadingWidget extends ConsumerWidget {
  const _FamilyDetailLoadingWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const MemberListSkeleton(itemCount: 6);
  }
}

// ── Graph Tab ──────────────────────────────────────────────────────

class _GraphTab extends ConsumerWidget {
  const _GraphTab({required this.detail, required this.familyId});

  final FamilyDetail detail;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (detail.members.isEmpty) {
      return DKEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No Members Yet',
        subtitle:
            'Add family members to start building your tree. '
            'Tap the + button below to add the first person.',
        actionLabel: 'Add Member',
        onAction: () => AddPersonSheet.show(context, familyId: familyId),
      );
    }

    return Stack(
      children: [
        FamilyTreeCanvas(
          members: detail.members,
          relationships: detail.relationships,
          onNodeTap: (person) {
            // P8: Smart preloading — warm profile provider BEFORE navigation push
            try {
              ref.read(profileProvider.notifier).loadProfile();
            } catch (_) {
              // Silently ignore — preloading is best-effort
            }

            final kinshipAsync = ref.read(kinshipServiceProvider);
            PersonDetailSheet.show(
              context,
              person: person,
              familyId: familyId,
              kinshipService: kinshipAsync,
            );
          },
          onNodeLongPress: (person) {
            _showQuickActions(context, ref, person);
          },
        ),
        // Find path toolbar button
        Positioned(
          top: 56,
          right: 12,
          child: _ToolbarButton(
            icon: Icons.route,
            tooltip: 'Find Path',
            onTap: () => context.go('/family/$familyId/path-finder'),
          ),
        ),
      ],
    );
  }

  void _showQuickActions(BuildContext context, WidgetRef ref, Person person) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              child: Row(
                children: [
                  DKAvatar(
                    initials: person.name.isNotEmpty
                        ? person.name[0].toUpperCase()
                        : '?',
                    size: DKAvatarSize.md,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      person.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: KinrelColors.border, height: 1),
            _QuickActionTile(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: () {
                Navigator.pop(ctx);
                AddPersonSheet.show(
                  context,
                  familyId: familyId,
                  existingPerson: person,
                );
              },
            ),
            _QuickActionTile(
              icon: Icons.link,
              label: 'Link to Another Member',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RelationshipBuilderScreen(
                      familyId: familyId,
                      familyName: detail.family.name,
                    ),
                  ),
                );
              },
            ),
            _QuickActionTile(
              icon: Icons.route,
              label: 'Find Path',
              onTap: () {
                Navigator.pop(ctx);
                context.go('/family/$familyId/path-finder');
              },
            ),
            _QuickActionTile(
              icon: Icons.delete_outline,
              label: 'Delete',
              isDestructive: true,
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await deletePerson(
                    ref: ref,
                    personId: person.id,
                    familyId: familyId,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${person.name} removed'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to delete: ${e.toString().split('\n').first}',
                        ),
                        backgroundColor: KinrelColors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Members Tab ────────────────────────────────────────────────────

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab({required this.detail, required this.familyId});

  final FamilyDetail detail;
  final String familyId;

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  String _searchQuery = '';
  String _sortBy = 'name';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// Estimated item height for scroll-based precaching.
  static const double _itemHeight = 72.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Scroll listener that precaches avatar images for upcoming items.
  void _onScroll() {
    try {
      final combinedMembers = ref.read(combinedMembersProvider(widget.familyId));
      final activeMembers = combinedMembers.where((p) => p.deletedAt == null).toList();
      final imageUrls = activeMembers.map((p) => p.photoUrl).toList();
      SmartPreloader.precacheUpcomingImages(
        context: context,
        scrollController: _scrollController,
        imageUrls: imageUrls,
        itemHeight: _itemHeight,
        preloadCount: 3,
      );
    } catch (_) {
      // Silently ignore — preloading is best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use combined provider: real members + pending (optimistic) members
    final combinedMembers = ref.watch(combinedMembersProvider(widget.familyId));

    final activeMembers = combinedMembers
        .where((p) => p.deletedAt == null)
        .toList();

    var filtered = activeMembers;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                (p.gender?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    if (_sortBy == 'name') {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else {
      filtered.sort((a, b) => (a.gender ?? '').compareTo(b.gender ?? ''));
    }

    return Column(
      children: [
        // Search + sort bar
        Padding(
          padding: const EdgeInsets.all(KinrelSpacing.base),
          child: Row(
            children: [
              Expanded(
                child: DKSearchField(
                  hint: 'Search members...',
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.sort, color: KinrelColors.textSilver),
                  onSelected: (value) => setState(() => _sortBy = value),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'name',
                      child: Row(
                        children: [
                          Icon(
                            Icons.sort_by_alpha,
                            size: 18,
                            color: _sortBy == 'name'
                                ? KinrelColors.purple
                                : KinrelColors.textSilver,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Sort by Name',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              color: _sortBy == 'name'
                                  ? KinrelColors.purple
                                  : KinrelColors.textWhite,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'generation',
                      child: Row(
                        children: [
                          Icon(
                            Icons.family_restroom,
                            size: 18,
                            color: _sortBy == 'generation'
                                ? KinrelColors.purple
                                : KinrelColors.textSilver,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Sort by Relationship',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              color: _sortBy == 'generation'
                                  ? KinrelColors.purple
                                  : KinrelColors.textWhite,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Stats row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            children: [
              DKStatChip(
                icon: Icons.people,
                value: '${filtered.length}',
                label: filtered.length == 1 ? 'member' : 'members',
                color: KinrelColors.purple,
              ),
              const SizedBox(width: 10),
              DKStatChip(
                icon: Icons.link,
                value: '${widget.detail.relationships.length}',
                label: widget.detail.relationships.length == 1
                    ? 'link'
                    : 'links',
                color: KinrelColors.gold,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Member list
        Expanded(
          child: filtered.isEmpty
              ? DKEmptyState(
                  icon: Icons.person_search_outlined,
                  title: _searchQuery.isEmpty ? 'No Members' : 'No Match',
                  subtitle: _searchQuery.isEmpty
                      ? 'Add members to your family tree'
                      : 'No members match "$_searchQuery"',
                )
              : ListView.builder(
                  controller: _scrollController,
                  cacheExtent: 500,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final person = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MemberCard(
                        person: person,
                        familyId: widget.familyId,
                        relationships: widget.detail.relationships,
                        index: index,
                        onTap: () {
                          final kinshipAsync = ref.read(kinshipServiceProvider);
                          PersonDetailSheet.show(
                            context,
                            person: person,
                            familyId: widget.familyId,
                            kinshipService: kinshipAsync,
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Activity Tab ───────────────────────────────────────────────────

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.detail, required this.familyId});

  final FamilyDetail detail;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final activities = <_ActivityItem>[];

    for (final rel in detail.relationships) {
      final fromPerson = detail.members
          .where((p) => p.id == rel.fromPersonId)
          .firstOrNull;
      final toPerson = detail.members
          .where((p) => p.id == rel.toPersonId)
          .firstOrNull;

      activities.add(
        _ActivityItem(
          type: _ActivityType.link,
          description:
              '${fromPerson?.name ?? 'Unknown'} → ${toPerson?.name ?? 'Unknown'} (${rel.relationshipKey.replaceAll('_', ' ')})',
          timestamp: rel.createdAt,
        ),
      );
    }

    for (final member in detail.members) {
      activities.add(
        _ActivityItem(
          type: _ActivityType.memberAdded,
          description: '${member.name} was added',
          timestamp: member.createdAt,
        ),
      );
    }

    activities.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return b.timestamp!.compareTo(a.timestamp!);
    });

    if (activities.isEmpty) {
      return DKEmptyState(
        icon: Icons.history_rounded,
        title: 'No Activity Yet',
        subtitle:
            'Activity will appear here as you add\nmembers and create relationships.',
      );
    }

    return ListView.builder(
      cacheExtent: 500,
      padding: EdgeInsets.all(KinrelSpacing.base),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return Padding(
          padding: EdgeInsets.only(bottom: KinrelSpacing.sm),
          child: _ActivityTile(activity: activity, index: index),
        );
      },
    );
  }
}

// ── Bottom Action Bar ──────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.familyId,
    required this.familyName,
    required this.memberCount,
  });

  final String familyId;
  final String familyName;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return Container(
          margin: const EdgeInsets.all(KinrelSpacing.base),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Add Member
              DKButton(
                label: 'Add Member',
                variant: DKButtonVariant.secondary,
                icon: Icons.person_add,
                size: DKButtonSize.sm,
                onPressed: () =>
                    AddPersonSheet.show(context, familyId: familyId),
              ),
              const SizedBox(width: 8),
              // Share
              DKButton(
                label: 'Share',
                variant: DKButtonVariant.icon,
                icon: Icons.share,
                size: DKButtonSize.sm,
                onPressed: () => context.push('/family/$familyId/share'),
              ),
              SizedBox(width: 8),
              // Path Finder
              DKButton(
                label: 'Path',
                variant: DKButtonVariant.icon,
                icon: Icons.route,
                size: DKButtonSize.sm,
                onPressed: () => context.go('/family/$familyId/path-finder'),
              ),
            ],
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.2, end: 0, duration: 400.ms);
  }
}

// ── Shared sub-widgets ─────────────────────────────────────────────

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        border: Border.all(color: KinrelColors.purple.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: KinrelColors.purple, size: 20),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? KinrelColors.coral : KinrelColors.textSilver;
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: isDestructive ? KinrelColors.coral : KinrelColors.textWhite,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.person,
    required this.familyId,
    required this.relationships,
    required this.index,
    required this.onTap,
  });

  final Person person;
  final String familyId;
  final List<FamilyRelationship> relationships;
  final int index;
  final VoidCallback onTap;

  /// Whether this person is pending (optimistic UI).
  bool get _isPending => person is OptimisticPerson && (person as OptimisticPerson).isPending;

  @override
  Widget build(BuildContext context) {
    final personRels = relationships
        .where((r) => r.fromPersonId == person.id || r.toPersonId == person.id)
        .map((r) => r.relationshipKey)
        .toList();

    final cardContent = DKCard(
          borderColor: person.isDeceased
              ? KinrelColors.border
              : KinrelColors.purple.withValues(alpha: 0.15),
          onTap: _isPending ? null : onTap,
          padding: 12,
          child: Row(
            children: [
              // Avatar
              DKAvatar(
                initials: person.name.isNotEmpty
                    ? person.name[0].toUpperCase()
                    : '?',
                size: DKAvatarSize.md,
                backgroundColor: person.isDeceased
                    ? KinrelColors.textSilver.withValues(alpha: 0.3)
                    : KinrelColors.purple,
              ),
              SizedBox(width: 12),

              // Name and relationship
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: person.isDeceased
                                  ? KinrelColors.textSilver
                                  : KinrelColors.textWhite,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Pending indicator badge
                        if (_isPending) ...[
                          SizedBox(width: 6),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: KinrelColors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: KinrelColors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: KinrelColors.orange,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Saving',
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: KinrelColors.orange,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (person.gender != null) ...[
                      SizedBox(height: 2),
                      Text(
                        person.gender!.toUpperCase(),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.purple,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (personRels.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: personRels.take(3).map((rel) {
                          return DKSuggestionChip(
                            label: rel.replaceAll('_', ' '),
                            isSelected: false,
                            onTap: () {},
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),

              // Gender icon + deceased
              Column(
                children: [
                  Icon(
                    person.gender == 'female'
                        ? Icons.female
                        : person.gender == 'male'
                        ? Icons.male
                        : Icons.person,
                    size: 16,
                    color: KinrelColors.textSilver,
                  ),
                  if (person.isDeceased)
                    Text(
                      'Late',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 9,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

    // Wrap pending members in a subtle opacity to indicate they're not confirmed yet
    return Opacity(
      opacity: _isPending ? 0.7 : 1.0,
      child: cardContent
          .maybeAnimate(onPlay: (c) => c.forward())
          .fadeIn(
            duration: 300.ms,
            delay: Duration(milliseconds: index * 50),
          )
          .slideX(begin: 0.05, end: 0, duration: 300.ms),
    );
  }
}

// ── Activity data ──────────────────────────────────────────────────

enum _ActivityType { memberAdded, link, edit }

class _ActivityItem {
  const _ActivityItem({
    required this.type,
    required this.description,
    this.timestamp,
  });

  final _ActivityType type;
  final String description;
  final DateTime? timestamp;
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.index});

  final _ActivityItem activity;
  final int index;

  @override
  Widget build(BuildContext context) {
    final iconData = switch (activity.type) {
      _ActivityType.memberAdded => Icons.person_add,
      _ActivityType.link => Icons.link,
      _ActivityType.edit => Icons.edit,
    };

    final iconColor = switch (activity.type) {
      _ActivityType.memberAdded => KinrelColors.purple,
      _ActivityType.link => KinrelColors.gold,
      _ActivityType.edit => KinrelColors.brightViolet,
    };

    final timeAgo = _formatTimeAgo(activity.timestamp);

    return DKCard(
          padding: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              DKTimelineNode(icon: iconData, color: iconColor, size: 36),
              SizedBox(width: 10),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.description,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    if (timeAgo != null) ...[
                      SizedBox(height: 2),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textSilver,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: index * 40),
        );
  }

  String? _formatTimeAgo(DateTime? time) {
    if (time == null) return null;
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).round()}w ago';
    return '${(diff.inDays / 30).round()}mo ago';
  }
}
