import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import 'family_tree_canvas.dart';
import 'add_person_sheet.dart';
import 'person_detail_sheet.dart';
import 'relationship_builder_screen.dart';

class FamilyDetailScreen extends ConsumerStatefulWidget {
  final String familyId;

  const FamilyDetailScreen({super.key, required this.familyId});

  @override
  ConsumerState<FamilyDetailScreen> createState() =>
      _FamilyDetailScreenState();
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

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.when(
          loading: () => Text(
            'Family Tree',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          error: (_, __) => Text(
            'Family Tree',
            style: TextStyle(
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
          // Share family code
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Family',
            onPressed: () => _shareFamily(context),
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              // TODO: Navigate to family settings
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textDim,
          indicatorColor: KinrelColors.orange,
          labelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
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
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (error, _) => _ErrorState(
          message: 'Failed to load family data',
          onRetry: () =>
              ref.invalidate(familyDetailProvider(widget.familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return _ErrorState(
              message: 'Family not found',
              onRetry: () =>
                  ref.invalidate(familyDetailProvider(widget.familyId)),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Graph tab
              _GraphTab(
                detail: detail,
                familyId: widget.familyId,
              ),
              // Members tab
              _MembersTab(
                detail: detail,
                familyId: widget.familyId,
              ),
              // Activity tab
              _ActivityTab(
                detail: detail,
                familyId: widget.familyId,
              ),
            ],
          );
        },
      ),
      // Bottom action bar
      bottomNavigationBar: detailAsync.when(
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
    // TODO: Implement family code sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Family sharing coming soon!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Graph Tab ──────────────────────────────────────────────────────

class _GraphTab extends ConsumerWidget {
  final FamilyDetail detail;
  final String familyId;

  const _GraphTab({required this.detail, required this.familyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (detail.members.isEmpty) {
      return _EmptyTreeState(
        onAddMember: () => AddPersonSheet.show(context, familyId: familyId),
      );
    }

    return Stack(
      children: [
        FamilyTreeCanvas(
          members: detail.members,
          relationships: detail.relationships,
          onNodeTap: (person) {
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
      shape: const RoundedRectangleBorder(
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
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: KinrelColors.igniteGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        person.name.isNotEmpty
                            ? person.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
            const Divider(color: KinrelColors.darkSurface, height: 1),
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
                            'Failed to delete: ${e.toString().split('\n').first}'),
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
  final FamilyDetail detail;
  final String familyId;

  const _MembersTab({required this.detail, required this.familyId});

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name' or 'generation'
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeMembers =
        widget.detail.members.where((p) => p.deletedAt == null).toList();

    // Filter by search
    var filtered = activeMembers;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              (p.gender?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    // Sort
    if (_sortBy == 'name') {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else {
      // Sort by relationship key (rough generation proxy)
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
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textWhite,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search members...',
                    hintStyle: TextStyle(color: KinrelColors.textDim),
                    prefixIcon: Icon(Icons.search,
                        color: KinrelColors.orange, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                color: KinrelColors.textDim, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: KinrelColors.darkElevated,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(KinrelSpacing.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusSm),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.sort, color: KinrelColors.textDim),
                  onSelected: (value) => setState(() => _sortBy = value),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'name',
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha,
                              size: 18,
                              color: _sortBy == 'name'
                                  ? KinrelColors.orange
                                  : KinrelColors.textDim),
                          const SizedBox(width: 8),
                          Text(
                            'Sort by Name',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              color: _sortBy == 'name'
                                  ? KinrelColors.orange
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
                          Icon(Icons.family_restroom,
                              size: 18,
                              color: _sortBy == 'generation'
                                  ? KinrelColors.orange
                                  : KinrelColors.textDim),
                          const SizedBox(width: 8),
                          Text(
                            'Sort by Relationship',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              color: _sortBy == 'generation'
                                  ? KinrelColors.orange
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

        // Member count
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
          ),
          child: Row(
            children: [
              Text(
                '${filtered.length} member${filtered.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Member list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'No members yet'
                        : 'No members match "$_searchQuery"',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      color: KinrelColors.textDim,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final person = filtered[index];
                    return _MemberListTile(
                      person: person,
                      familyId: widget.familyId,
                      relationships: widget.detail.relationships,
                      onTap: () {
                        final kinshipAsync =
                            ref.read(kinshipServiceProvider);
                        PersonDetailSheet.show(
                          context,
                          person: person,
                          familyId: widget.familyId,
                          kinshipService: kinshipAsync,
                        );
                      },
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
  final FamilyDetail detail;
  final String familyId;

  const _ActivityTab({required this.detail, required this.familyId});

  @override
  Widget build(BuildContext context) {
    // Build activity list from relationships (most recent first)
    final activities = <_ActivityItem>[];

    for (final rel in detail.relationships) {
      final fromPerson = detail.members
          .where((p) => p.id == rel.fromPersonId)
          .firstOrNull;
      final toPerson = detail.members
          .where((p) => p.id == rel.toPersonId)
          .firstOrNull;

      activities.add(_ActivityItem(
        type: _ActivityType.link,
        description:
            '${fromPerson?.name ?? 'Unknown'} → ${toPerson?.name ?? 'Unknown'} (${rel.relationshipKey.replaceAll('_', ' ')})',
        timestamp: rel.createdAt,
      ));
    }

    for (final member in detail.members) {
      activities.add(_ActivityItem(
        type: _ActivityType.memberAdded,
        description: '${member.name} was added',
        timestamp: member.createdAt,
      ));
    }

    // Sort by timestamp (newest first)
    activities.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return b.timestamp!.compareTo(a.timestamp!);
    });

    if (activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            Text(
              'No Activity Yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Activity will appear here as you add\nmembers and create relationships.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return _ActivityTile(activity: activity);
      },
    );
  }
}

// ── Bottom Action Bar ──────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  final String familyId;
  final String familyName;
  final int memberCount;

  const _BottomActionBar({
    required this.familyId,
    required this.familyName,
    required this.memberCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          top: BorderSide(
            color: KinrelColors.darkSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Add Member
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    AddPersonSheet.show(context, familyId: familyId),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add Member'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.orange,
                  side: const BorderSide(color: KinrelColors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                  textStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Link Members
            Expanded(
              child: FilledButton.icon(
                onPressed: memberCount < 2
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RelationshipBuilderScreen(
                              familyId: familyId,
                              familyName: familyName,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Link Members'),
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      KinrelColors.orange.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                  textStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Share
            SizedBox(
              height: 40,
              width: 40,
              child: IconButton.outlined(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Family sharing coming soon!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.share, size: 18),
                color: KinrelColors.textSilver,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: KinrelColors.darkSurface.withValues(alpha: 0.5),
                  ),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ─────────────────────────────────────────────

class _EmptyTreeState extends StatelessWidget {
  final VoidCallback onAddMember;

  const _EmptyTreeState({required this.onAddMember});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: KinrelColors.textDim.withValues(alpha: 0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 48,
                  color: KinrelColors.textDim.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Members Yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add family members to start building your tree. '
              'Tap the + button below to add the first person.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
                height: 1.5,
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

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: KinrelColors.error.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.3),
        ),
      ),
      child: IconButton(
        icon: Icon(icon, color: KinrelColors.textSilver, size: 20),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? KinrelColors.error : KinrelColors.textSilver,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: isDestructive ? KinrelColors.error : KinrelColors.textWhite,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _MemberListTile extends StatelessWidget {
  final Person person;
  final String familyId;
  final List<FamilyRelationship> relationships;
  final VoidCallback onTap;

  const _MemberListTile({
    required this.person,
    required this.familyId,
    required this.relationships,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Find relationships for this person
    final personRels = relationships
        .where((r) =>
            r.fromPersonId == person.id || r.toPersonId == person.id)
        .map((r) => r.relationshipKey)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      child: Material(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: person.isDeceased
                        ? LinearGradient(
                            colors: [
                              KinrelColors.textDim,
                              KinrelColors.darkSurface,
                            ],
                          )
                        : KinrelColors.igniteGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: person.isDeceased
                        ? const Text('🕊️', style: TextStyle(fontSize: 16))
                        : Text(
                            person.name.isNotEmpty
                                ? person.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name and relationship
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: person.isDeceased
                              ? KinrelColors.textSilver
                              : KinrelColors.textWhite,
                        ),
                      ),
                      if (person.gender != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          person.gender!.toUpperCase(),
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ],
                      if (personRels.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: personRels.take(3).map((rel) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: KinrelColors.darkSurface
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                rel.replaceAll('_', ' '),
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 9,
                                  color: KinrelColors.textDim,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Gender + deceased
                Column(
                  children: [
                    Icon(
                      person.gender == 'female'
                          ? Icons.female
                          : person.gender == 'male'
                              ? Icons.male
                              : Icons.person,
                      size: 16,
                      color: KinrelColors.textDim,
                    ),
                    if (person.isDeceased)
                      Text(
                        'Late',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 9,
                          color: KinrelColors.textDim,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Activity data ──────────────────────────────────────────────────

enum _ActivityType { memberAdded, link, edit }

class _ActivityItem {
  final _ActivityType type;
  final String description;
  final DateTime? timestamp;

  const _ActivityItem({
    required this.type,
    required this.description,
    this.timestamp,
  });
}

class _ActivityTile extends StatelessWidget {
  final _ActivityItem activity;

  const _ActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final iconData = switch (activity.type) {
      _ActivityType.memberAdded => Icons.person_add,
      _ActivityType.link => Icons.link,
      _ActivityType.edit => Icons.edit,
    };

    final iconColor = switch (activity.type) {
      _ActivityType.memberAdded => KinrelColors.success,
      _ActivityType.link => KinrelColors.orange,
      _ActivityType.edit => KinrelColors.amber,
    };

    final timeAgo = _formatTimeAgo(activity.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),

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
                  const SizedBox(height: 2),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _formatTimeAgo(DateTime? timestamp) {
    if (timestamp == null) return null;

    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}
