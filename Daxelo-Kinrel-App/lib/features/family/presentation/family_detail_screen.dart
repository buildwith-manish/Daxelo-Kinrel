import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_actions.dart';
import '../../../core/family/optimistic_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../presentation/widgets/skeletons/member_list_skeleton.dart';
import 'family_tree_canvas.dart';
import 'add_person_sheet.dart';
import 'person_detail_sheet.dart';
import 'relationship_builder_screen.dart';
import 'add_member_options_sheet.dart';

import '../../../core/utils/error_boundary.dart';
import '../../../core/utils/smart_preloader.dart';
import '../../../core/utils/share_helper.dart';
import '../../profile/data/profile_provider.dart';
import '../../truth_streak/presentation/truth_streak_card.dart';
import '../../hot_seat/presentation/hot_seat_card.dart';
import '../../relation_riddles/presentation/relation_riddle_card.dart';

class FamilyDetailScreen extends ConsumerStatefulWidget {
  FamilyDetailScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends ConsumerState<FamilyDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));

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
          // Family chat — opens the real-time group chat for this family.
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Family Chat',
            onPressed: () {
              final detail = ref.read(familyDetailProvider(widget.familyId)).valueOrNull;
              final familyName = detail?.family.name ?? 'Family';
              context.push(
                '/family/${widget.familyId}/chat?name=${Uri.encodeComponent(familyName)}',
              );
            },
          ),
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
      ),
      body: detailAsync.when(
        loading: () => const _FamilyDetailLoadingWidget(),
        error: (error, _) => DKErrorState(
          message: 'Failed to load family data',
          onRetry: () {
            ref.invalidate(familyListProvider);
            ref.invalidate(familyDetailProvider(widget.familyId));
            ref.invalidate(familyMembersProvider(widget.familyId));
            ref.invalidate(familyRelationshipsProvider(widget.familyId));
          },
        ),
        data: (detail) {
          if (detail == null) {
            return DKErrorState(
              message: 'Family not found',
              onRetry: () {
                ref.invalidate(familyListProvider);
                ref.invalidate(familyDetailProvider(widget.familyId));
                ref.invalidate(familyMembersProvider(widget.familyId));
                ref.invalidate(familyRelationshipsProvider(widget.familyId));
              },
            );
          }

          // ── Scrollable feed (replaces TabBarView) ──────────────
          // Feed order: Truth Streak (hero) → Games → Graph → Members → Activity
          return CustomScrollView(
            slivers: [
              // 1. Header section — family name, avatar, stats
              SliverToBoxAdapter(child: _FeedHeader(detail: detail)),

              // 2. Truth Streak — the visual HERO (largest, most prominent)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TruthStreakCard(familyId: widget.familyId),
                ),
              ),

              // 3. Hot Seat game
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: HotSeatCard(familyId: widget.familyId),
                ),
              ),

              // 4. Relation Riddles game
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: RelationRiddleCard(familyId: widget.familyId),
                ),
              ),

              // 5. Graph preview card (quieter supporting card)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _GraphPreviewCard(
                    detail: detail,
                    familyId: widget.familyId,
                  ),
                ),
              ),

              // 6. Members preview row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _MembersPreviewRow(
                    detail: detail,
                    familyId: widget.familyId,
                  ),
                ),
              ),

              // 7. Activity preview
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _ActivityPreviewCard(
                    detail: detail,
                    familyId: widget.familyId,
                  ),
                ),
              ),

              // 8. More Games placeholder
              SliverToBoxAdapter(child: _MoreGamesCard()),

              // Bottom padding for FAB
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
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

    // Determine current user's role from FamilyMember table
    final membershipsAsync = ref.read(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull ?? [];
    final currentUserMembership = memberships
        .where((m) => m.userId == currentUserId)
        .firstOrNull;
    final currentUserRole = currentUserMembership?.role;
    final isAdminOrOwner = isCreator ||
        currentUserRole == 'admin' ||
        currentUserRole == 'owner';

    // Count how many admins are in the family (to prevent sole admin from leaving)
    final adminCount = memberships.where((m) => m.isAdmin).length;
    final isOnlyAdmin = (currentUserMembership?.isAdmin ?? false) && adminCount <= 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: DKColors.cardColor(context),
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
                      color: DKColors.textPrimary(context),
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
                          if (family.kinFamilyId != null) ...[
                            SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: family.kinFamilyId!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Family ID copied: ${family.kinFamilyId}'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy, size: 12, color: KinrelColors.purple),
                                  SizedBox(width: 4),
                                  Text(
                                    family.kinFamilyId!,
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.monoFont,
                                      fontSize: 12,
                                      color: KinrelColors.purple,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
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

            // Invite Members option (admin/owner only)
            if (isAdminOrOwner) ...[
              _QuickActionTile(
                icon: Icons.person_add_outlined,
                label: 'Invite Members',
                iconColor: KinrelColors.purple,
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/family/${widget.familyId}/invite');
                },
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

            // Copy Family ID option
            if (family?.kinFamilyId != null) ...[
              Divider(color: KinrelColors.border, height: 1),
              _QuickActionTile(
                icon: Icons.copy_rounded,
                label: 'Copy Family ID (${family!.kinFamilyId})',
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: family.kinFamilyId!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Family ID copied: ${family.kinFamilyId}'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],

            // Family Map option
            _QuickActionTile(
              icon: Icons.public,
              label: 'Family Map',
              iconColor: KinrelColors.orange,
              onTap: () { Navigator.pop(ctx); context.push('/family-map'); },
            ),
            Divider(color: KinrelColors.border, height: 1),

            // Memory Vault option
            _QuickActionTile(
              icon: Icons.photo_library_outlined,
              label: 'Memory Vault',
              iconColor: KinrelColors.gold,
              onTap: () { Navigator.pop(ctx); context.push('/memory-vault'); },
            ),
            Divider(color: KinrelColors.border, height: 1),

            // Delete option — moves family to archive (available to all members)
            Divider(color: KinrelColors.border, height: 1),
            _QuickActionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete Family',
              iconColor: KinrelColors.error,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteFamily(context, family?.name ?? 'Family');
              },
            ),

            // Info: deleted families go to archive
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
                      'Deleted families are moved to archive. You can restore or permanently delete them from there.',
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

            // Leave Family option (not available if user is the only admin)
            if (!isOnlyAdmin) ...[
              Divider(color: KinrelColors.border, height: 1),
              _QuickActionTile(
                icon: Icons.exit_to_app_outlined,
                label: 'Leave Family',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmLeaveFamily(context, family?.name ?? 'Family');
                },
              ),
            ] else ...[
              // Show info that sole admin must transfer role first
              Divider(color: KinrelColors.border, height: 1),
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
                        'Transfer your admin role to another member before leaving',
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
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
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
                  color: DKColors.textPrimary(context),
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
              'This family will be moved to archive. You can restore it or permanently delete it from the archive section.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: DKColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: KinrelColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Archived families are automatically deleted after 30 days if not restored.',
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
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _performDeleteFamily(context);
            },
            child: Text(
              'Delete',
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
    // Capture navigator, messenger, and container BEFORE async gap — the
    // widget may be disposed after deleteFamily invalidates providers and
    // the list rebuilds. ProviderContainer survives widget disposal.
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final container = ProviderScope.containerOf(context);

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => Center(
          child: CircularProgressIndicator(color: KinrelColors.purple),
        ),
      ),
    );

    try {
      await deleteFamilyOptimistic(container: container, familyId: widget.familyId);

      // Use captured references — the original context may be unmounted now
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text('Family moved to archive. You can restore it from the Archived section.'),
          backgroundColor: KinrelColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      router.go('/families');
    } catch (e) {
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
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

  void _confirmLeaveFamily(BuildContext context, String familyName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            Icon(
              Icons.exit_to_app_outlined,
              color: KinrelColors.warning,
              size: 24,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Leave "$familyName"?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: DKColors.textPrimary(context),
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
              'You will no longer have access to this family tree. Other members will still be able to view and edit it.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: DKColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: KinrelColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. You will need a new invitation to rejoin.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.warning,
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
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // Close dialog
              await _performLeaveFamily(context);
            },
            child: Text(
              'Leave Family',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w600,
                color: KinrelColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performLeaveFamily(BuildContext context) async {
    // Capture navigator and messenger BEFORE async gap — the widget may be
    // disposed after provider invalidation and navigation.
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => Center(
          child: CircularProgressIndicator(color: KinrelColors.warning),
        ),
      ),
    );

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/api/families/${widget.familyId}/leave');

      // Invalidate providers
      ref.invalidate(familyListProvider);
      ref.invalidate(familyMembershipsProvider(widget.familyId));

      // Use captured references — the original context may be unmounted now
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text('You have left the family'),
          backgroundColor: KinrelColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      router.go('/');
    } catch (e) {
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to leave family: ${e.toString().split('\n').first}',
          ),
          backgroundColor: KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

class _GraphTab extends ConsumerStatefulWidget {
  const _GraphTab({required this.detail, required this.familyId});

  final FamilyDetail detail;
  final String familyId;

  @override
  ConsumerState<_GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends ConsumerState<_GraphTab> {
  bool _showHierarchy = true; // Default to new hierarchy view

  @override
  Widget build(BuildContext context) {
    // ✅ FIX: Re-watch familyDetailProvider to get LIVE member data.
    // Previously we used widget.detail (stale snapshot from parent),
    // which meant newly added members wouldn't appear until the
    // user navigated away and came back.
    final liveDetailAsync = ref.watch(familyDetailProvider(widget.familyId));
    final detail = liveDetailAsync.valueOrNull ?? widget.detail;
    final familyId = widget.familyId;

    if (detail.members.isEmpty) {
      return DKEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No Members Yet',
        subtitle:
            'Add family members to start building your tree. '
            'Tap the + button below to add the first person.',
        actionLabel: 'Add Member',
        onAction: () => showAddMemberOptions(context, familyId: familyId),
      );
    }

    return Stack(
      children: [
        // Primary graph view
        if (_showHierarchy)
          // Embedded relationship graph — navigates to full screen on tap
          _EmbeddedHierarchyGraph(
            detail: detail,
            familyId: familyId,
          )
        else
          FamilyTreeCanvas(
            members: detail.members,
            relationships: detail.relationships,
            anchorPersonId: detail.members.firstWhere(
              (p) => p.isAnchor,
              orElse: () => detail.members.first,
            ).id,
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

        // View toggle button (top-left)
        Positioned(
          top: 12,
          left: 12,
          child: _ViewTogglePill(
            isHierarchy: _showHierarchy,
            onToggle: () => setState(() => _showHierarchy = !_showHierarchy),
          ),
        ),

        // Find path toolbar button
        Positioned(
          top: 12,
          right: 12,
          child: _ToolbarButton(
            icon: Icons.route,
            tooltip: 'Find Path',
            onTap: () => context.push('/family/$familyId/path-finder'),
          ),
        ),

        // ✅ FIX: Add Member button in top-right so users can add members
        // even when the graph is already populated.
        Positioned(
          top: 12,
          right: 56,
          child: _ToolbarButton(
            icon: Icons.person_add_rounded,
            tooltip: 'Add Member',
            onTap: () => showAddMemberOptions(context, familyId: familyId),
          ),
        ),

        // Full-screen graph button
        Positioned(
          top: 60,
          right: 56,
          child: _ToolbarButton(
            icon: Icons.fullscreen_rounded,
            tooltip: 'Full Screen Graph',
            onTap: () {
              final name = ref.read(familyDetailProvider(widget.familyId)).valueOrNull?.family.name;
              context.push('/family/${widget.familyId}/graph${name != null ? '?name=${Uri.encodeComponent(name)}' : ''}');
            },
          ),
        ),
      ],
    );
  }

  void _showQuickActions(BuildContext context, WidgetRef ref, Person person) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DKColors.cardColor(context),
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
                        color: DKColors.textPrimary(context),
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
                  familyId: widget.familyId,
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
                      familyId: widget.familyId,
                      familyName: widget.detail.family.name,
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
                context.push('/family/${widget.familyId}/path-finder');
              },
            ),
            _QuickActionTile(
              icon: Icons.delete_outline,
              label: 'Delete',
              isDestructive: true,
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await deletePersonOptimistic(
                    ref: ref,
                    personId: person.id,
                    familyId: widget.familyId,
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

    // Watch memberships provider to get collaborator info with user profiles
    final membershipsAsync = ref.watch(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull ?? [];
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final family = widget.detail.family;
    final isCreator = family.createdBy != null && family.createdBy == currentUserId;

    // Determine if current user is admin
    final currentUserMembership = memberships
        .where((m) => m.userId == currentUserId)
        .firstOrNull;
    final isAdmin = isCreator || (currentUserMembership?.isAdmin ?? false);

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
              const SizedBox(width: 10),
              DKStatChip(
                icon: Icons.group_outlined,
                value: '${memberships.length}',
                label: memberships.length == 1 ? 'collaborator' : 'collaborators',
                color: KinrelColors.blue,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Collaborators Section ────────────────────────────────────
        if (memberships.isNotEmpty) ...[
          _CollaboratorsHeader(
            count: memberships.length,
            isAdmin: isAdmin,
            onInviteTap: () => context.push('/family/${widget.familyId}/invite'),
          ),
          const SizedBox(height: 8),
          ...memberships.map((membership) => _CollaboratorCard(
            membership: membership,
            isCurrentUser: membership.userId == currentUserId,
            canManage: isAdmin && membership.userId != currentUserId,
            familyId: widget.familyId,
            isCreator: isCreator,
            onRoleChanged: () {
              ref.invalidate(familyMembershipsProvider(widget.familyId));
            },
            onRemoved: () {
              ref.invalidate(familyMembershipsProvider(widget.familyId));
              ref.invalidate(familyDetailProvider(widget.familyId));
            },
          )),
          Divider(
            color: KinrelColors.border,
            height: 24,
            indent: KinrelSpacing.base,
            endIndent: KinrelSpacing.base,
          ),
        ] else ...[
          // No collaborators yet — show invite CTA
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            child: _InviteCollaboratorCTA(
              onTap: () => context.push('/family/${widget.familyId}/invite'),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Tree members section label
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 14,
                color: KinrelColors.textSilver,
              ),
              const SizedBox(width: 6),
              Text(
                'Family Tree Members',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textSilver,
                ),
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
                  scrollCacheExtent: ScrollCacheExtent.pixels(500),
                  padding: const EdgeInsets.only(
                    left: KinrelSpacing.base,
                    right: KinrelSpacing.base,
                    bottom: 88, // Clear the bottom action bar
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

// ── Collaborators Header ──────────────────────────────────────────

class _CollaboratorsHeader extends StatelessWidget {
  const _CollaboratorsHeader({
    required this.count,
    required this.isAdmin,
    required this.onInviteTap,
  });

  final int count;
  final bool isAdmin;
  final VoidCallback onInviteTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        children: [
          Icon(
            Icons.group_outlined,
            size: 14,
            color: KinrelColors.textSilver,
          ),
          const SizedBox(width: 6),
          Text(
            'Collaborators',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const Spacer(),
          if (isAdmin)
            GestureDetector(
              onTap: onInviteTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    size: 14,
                    color: KinrelColors.purple,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Invite',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.purple,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Collaborator Card ────────────────────────────────────────────

class _CollaboratorCard extends ConsumerWidget {
  const _CollaboratorCard({
    required this.membership,
    required this.isCurrentUser,
    required this.canManage,
    required this.familyId,
    required this.isCreator,
    required this.onRoleChanged,
    required this.onRemoved,
  });

  final FamilyMembership membership;
  final bool isCurrentUser;
  final bool canManage;
  final String familyId;
  final bool isCreator;
  final VoidCallback onRoleChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = membership.user;
    final displayName = user?.displayName ?? 'User';
    final initials = user?.initials ?? '?';
    final avatarUrl = user?.avatarUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 2,
      ),
      child: InkWell(
        onTap: canManage ? () => _showMemberActions(context, ref) : null,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: DKColors.cardColor(context),
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            border: Border.all(
              color: isCurrentUser
                  ? KinrelColors.purple.withValues(alpha: 0.3)
                  : KinrelColors.border,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              DKAvatar(
                initials: initials,
                size: DKAvatarSize.md,
                backgroundColor: _roleColor(membership.role),
                imageUrl: avatarUrl,
              ),
              const SizedBox(width: 12),

              // Name + role
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DKColors.textPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: KinrelColors.purple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'You',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.purple,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _RoleBadge(role: membership.role),
                        if (user?.username != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '@${user!.username}',
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

              // Manage button (admin only, not for self)
              if (canManage)
                Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: KinrelColors.textSilver,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'owner':
        return KinrelColors.purple;
      case 'editor':
        return const Color(0xFF2196F3); // Blue
      case 'viewer':
        return KinrelColors.textSilver;
      case 'member':
      default:
        return KinrelColors.blue;
    }
  }

  void _showMemberActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DKColors.cardColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              child: Row(
                children: [
                  DKAvatar(
                    initials: membership.user?.initials ?? '?',
                    size: DKAvatarSize.md,
                    backgroundColor: _roleColor(membership.role),
                    imageUrl: membership.user?.avatarUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          membership.user?.displayName ?? 'User',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: DKColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          membership.displayRole,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: KinrelColors.border, height: 1),

            // Change Role section
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Change Role',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: ['admin', 'editor', 'member', 'viewer'].map((role) {
                      final isSelected = membership.role.toLowerCase() == role;
                      return GestureDetector(
                        onTap: isSelected
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _changeRole(context, ref, role);
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? KinrelColors.purple.withValues(alpha: 0.15)
                                : KinrelColors.darkElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? KinrelColors.purple
                                  : KinrelColors.border,
                            ),
                          ),
                          child: Text(
                            role[0].toUpperCase() + role.substring(1),
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? KinrelColors.purple
                                  : KinrelColors.textSilver,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            Divider(color: KinrelColors.border, height: 1),

            // Remove member option (only for admins, not for other admins unless creator)
            if (membership.role.toLowerCase() != 'admin' || isCreator) ...[
              _QuickActionTile(
                icon: Icons.person_remove_outlined,
                label: 'Remove from Family',
                isDestructive: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _removeMember(context, ref);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(BuildContext context, WidgetRef ref, String newRole) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(
        '/api/families/$familyId/members/${membership.id}/role',
        data: {'role': newRole},
      );
      onRoleChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Role updated to ${newRole[0].toUpperCase()}${newRole.substring(1)}'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update role: ${e.toString().split('\n').first}'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref) async {
    // Confirm before removing
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Text(
          'Remove ${membership.user?.displayName ?? 'Member'}?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: DKColors.textPrimary(context),
          ),
        ),
        content: Text(
          'They will lose access to this family tree. They can rejoin with a new invite.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: DKColors.textSecondary(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w600,
                color: KinrelColors.warning,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/api/families/$familyId/members/${membership.id}');
      onRemoved();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${membership.user?.displayName ?? 'Member'} removed'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove: ${e.toString().split('\n').first}'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ── Role Badge ──────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String get _label {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'owner':
        return 'Admin';
      case 'editor':
        return 'Editor';
      case 'viewer':
        return 'Viewer';
      case 'member':
      default:
        return 'Member';
    }
  }

  Color get _color {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'owner':
        return KinrelColors.purple;
      case 'editor':
        return const Color(0xFF2196F3);
      case 'viewer':
        return KinrelColors.textSilver;
      case 'member':
      default:
        return KinrelColors.blue;
    }
  }
}

// ── Invite Collaborator CTA ──────────────────────────────────────

class _InviteCollaboratorCTA extends StatelessWidget {
  const _InviteCollaboratorCTA({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.purple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: KinrelColors.purple.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: KinrelColors.purple.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_add_outlined,
                size: 18,
                color: KinrelColors.purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invite Collaborators',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.purple,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Share access with family members to build the tree together',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: KinrelColors.purple.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
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
              '${fromPerson?.name ?? 'Someone'} added ${toPerson?.name ?? 'a family member'} as ${rel.relationshipKey.replaceAll('_', ' ')}',
          timestamp: rel.createdAt,
        ),
      );
    }

    for (final member in detail.members) {
      activities.add(
        _ActivityItem(
          type: _ActivityType.memberAdded,
          description: '${member.name} joined the family',
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
      scrollCacheExtent: ScrollCacheExtent.pixels(500),
      padding: const EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: KinrelSpacing.base,
        bottom: 88, // Clear the bottom action bar
      ),
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

// ═══════════════════════════════════════════════════════════════════════
// FEED WIDGETS (scrollable home feed sections)
// ═══════════════════════════════════════════════════════════════════════

/// Section 1: Header — family avatar, name, stats
class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.detail});
  final FamilyDetail detail;

  @override
  Widget build(BuildContext context) {
    final family = detail.family;
    return Padding(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
            child: Text(
              family.name.isNotEmpty ? family.name[0].toUpperCase() : 'F',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  family.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${detail.members.length} members · ${detail.relationships.length} links',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section 2: Graph preview card — compact, pushes to full graph
class _GraphPreviewCard extends StatelessWidget {
  const _GraphPreviewCard({required this.detail, required this.familyId});
  final FamilyDetail detail;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(
            '/family/$familyId/graph?name=${Uri.encodeComponent(detail.family.name)}',
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.account_tree_outlined,
                    color: KinrelColors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Family Graph',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${detail.members.length} members · ${detail.relationships.length} relationships',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: KinrelColors.textDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section 4: Members preview row — horizontal scrollable avatars
class _MembersPreviewRow extends StatelessWidget {
  const _MembersPreviewRow({required this.detail, required this.familyId});
  final FamilyDetail detail;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final members = detail.members.where((p) => p.deletedAt == null).take(10).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    context.push('/family/$familyId/members'),
                child: Text(
                  'View All',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: members.length,
              itemBuilder: (context, index) {
                final person = members[index];
                return Container(
                  width: 56,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: KinrelColors.orange.withValues(alpha: 0.12),
                        backgroundImage: person.photoUrl != null
                            ? NetworkImage(person.photoUrl!)
                            : null,
                        child: person.photoUrl == null
                            ? Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      KinrelColors.orange.withValues(alpha: 0.25),
                                      KinrelColors.amber.withValues(alpha: 0.1),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    person.name.isNotEmpty
                                        ? person.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.displayFont,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: KinrelColors.orange,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        person.name.split(' ').first,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          color: KinrelColors.textDim,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Section 5: Activity preview — recent 3-5 items
class _ActivityPreviewCard extends StatelessWidget {
  const _ActivityPreviewCard({required this.detail, required this.familyId});
  final FamilyDetail detail;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final activities = <_ActivityItem>[];

    for (final rel in detail.relationships) {
      final fromPerson =
          detail.members.where((p) => p.id == rel.fromPersonId).firstOrNull;
      final toPerson =
          detail.members.where((p) => p.id == rel.toPersonId).firstOrNull;
      activities.add(_ActivityItem(
        type: _ActivityType.link,
        description:
            '${fromPerson?.name ?? "Someone"} added ${toPerson?.name ?? "a family member"} as ${rel.relationshipKey.replaceAll("_", " ")}',
        timestamp: rel.createdAt,
      ));
    }
    for (final member in detail.members) {
      activities.add(_ActivityItem(
        type: _ActivityType.memberAdded,
        description: '${member.name} joined the family',
        timestamp: member.createdAt,
      ));
    }
    activities.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return b.timestamp!.compareTo(a.timestamp!);
    });

    final recent = activities.take(4).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent Activity',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    context.push('/family/$familyId/activity'),
                child: Text(
                  'View All',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recent.map((activity) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      activity.type == _ActivityType.link
                          ? Icons.link_rounded
                          : Icons.person_add_alt_1_rounded,
                      size: 18,
                      color: activity.type == _ActivityType.link
                          ? KinrelColors.orange
                          : KinrelColors.purple,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activity.description,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: KinrelColors.textSilver,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// Section 6: More Games placeholder
class _MoreGamesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: KinrelColors.textDim.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.videogame_asset_outlined,
            size: 32,
            color: KinrelColors.textDim.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'More family games coming soon',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Hot Seat · Relation Riddles · and more',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
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
    // ✅ FIX (BUG-08): Wrap in IntrinsicWidth to prevent full-width stretching
    // when rendered as a floating action bar
    return IntrinsicWidth(
      child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: 6,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: DKColors.cardColor(context).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
            border: Border.all(
              color: KinrelColors.purple.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Add Member
              DKButton(
                label: 'Add Member',
                variant: DKButtonVariant.secondary,
                icon: Icons.person_add,
                size: DKButtonSize.sm,
                onPressed: () =>
                    showAddMemberOptions(context, familyId: familyId),
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
                onPressed: () => context.push('/family/$familyId/path-finder'),
              ),
            ],
          ),
        ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.2, end: 0, duration: 400.ms);
  }
}

// ── Embedded Hierarchy Graph (opens full-screen on tap) ─────────────

class _EmbeddedHierarchyGraph extends StatelessWidget {
  const _EmbeddedHierarchyGraph({
    required this.detail,
    required this.familyId,
  });

  final FamilyDetail detail;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final memberCount = detail.members.where((p) => p.deletedAt == null).length;
    final relCount = detail.relationships.where((r) => r.isActive).length;

    return Container(
      color: DKColors.isLight(context) ? DKColors.lightBg : KinrelColors.darkBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Graph preview card
              GestureDetector(
                onTap: () => context.push('/family/$familyId/graph?name=${Uri.encodeComponent(detail.family.name)}'),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: DKColors.cardColor(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.orange.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Graph icon with glow
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.orange.withValues(alpha: 0.12),
                          border: Border.all(
                            color: KinrelColors.orange.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.account_tree_rounded,
                          size: 36,
                          color: KinrelColors.orange,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Relationship Graph',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: DKColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'View the hierarchical family relationship\ngraph with color-coded generations',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: DKColors.textSecondary(context),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Stats row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _StatBadge(
                            icon: Icons.people_outline_rounded,
                            value: '$memberCount',
                            label: 'Members',
                            color: KinrelColors.orange,
                          ),
                          const SizedBox(width: 16),
                          _StatBadge(
                            icon: Icons.link_rounded,
                            value: '$relCount',
                            label: 'Connections',
                            color: KinrelColors.amber,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Open button
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE8612A), Color(0xFFF59240)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open Full Graph',
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: DKColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── View Toggle Pill ─────────────────────────────────────────────────

class _ViewTogglePill extends StatelessWidget {
  const _ViewTogglePill({
    required this.isHierarchy,
    required this.onToggle,
  });

  final bool isHierarchy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: DKColors.cardColor(context).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleOption(
            icon: Icons.account_tree_rounded,
            label: 'Tree',
            isActive: isHierarchy,
            onTap: isHierarchy ? null : onToggle,
          ),
          const SizedBox(width: 2),
          _ToggleOption(
            icon: Icons.hub_outlined,
            label: 'Constellation',
            isActive: !isHierarchy,
            onTap: !isHierarchy ? null : onToggle,
          ),
        ],
      ),
    )
    .animate(onPlay: (c) => c.forward())
    .fadeIn(duration: 300.ms);
  }
}

class _ToggleOption extends StatelessWidget {
  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? KinrelColors.orange.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? Border.all(color: KinrelColors.orange.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? KinrelColors.orange : KinrelColors.textSilver,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? KinrelColors.orange : KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
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
    this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? (isDestructive ? KinrelColors.coral : KinrelColors.textSilver);
    final textColor = iconColor ?? (isDestructive ? KinrelColors.coral : KinrelColors.textWhite);
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: textColor,
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
          .animate(onPlay: (c) => c.forward())
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
        .animate(onPlay: (c) => c.forward())
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
