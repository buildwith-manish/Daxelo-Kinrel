import 'dart:async';

import 'package:dio/dio.dart';
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
import '../../../core/utils/error_boundary.dart';
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
          // ── Invite Members button (only for OWNER/ADMIN) ───────────
          Consumer(builder: (context, ref, _) {
            final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
            final family = ref.read(familyDetailProvider(widget.familyId)).valueOrNull?.family;
            final isCreator = family != null &&
                family.createdBy != null &&
                family.createdBy == currentUserId;
            // For now, creator = OWNER/ADMIN. In future, check role field.
            if (isCreator) {
              return IconButton(
                icon: Icon(Icons.person_add_outlined, color: KinrelColors.purple),
                tooltip: 'Invite Members',
                onPressed: () => context.push('/families/${widget.familyId}/invite?familyName=${Uri.encodeComponent(family.name)}'),
              );
            }
            return const SizedBox.shrink();
          }),
          IconButton(
            icon: Icon(Icons.share_outlined),
            tooltip: 'Share Family',
            onPressed: () => _shareFamily(context),
          ),
          // ── Leave Family option in overflow menu ──────────────────
          Consumer(builder: (context, ref, _) {
            final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
            final family = ref.read(familyDetailProvider(widget.familyId)).valueOrNull?.family;
            final isCreator = family != null &&
                family.createdBy != null &&
                family.createdBy == currentUserId;
            // Only show overflow menu for non-owners
            if (!isCreator) {
              return PopupMenuButton<String>(
                icon: Icon(Icons.settings_outlined),
                onSelected: (value) {
                  if (value == 'leave') {
                    _showLeaveFamilyDialog(context);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'leave',
                    child: Row(
                      children: [
                        Icon(Icons.exit_to_app, size: 18, color: KinrelColors.error),
                        SizedBox(width: 8),
                        Text(
                          'Leave Family',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            color: KinrelColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return IconButton(
              icon: Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => _showFamilySettings(context),
            );
          }),
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
        error: (error, _) => ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: DKErrorState(
            message: 'Failed to load family data',
            onRetry: () {
              ref.invalidate(familyListProvider);
              ref.invalidate(familyDetailProvider(widget.familyId));
              ref.invalidate(familyMembersProvider(widget.familyId));
              ref.invalidate(familyRelationshipsProvider(widget.familyId));
            },
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: DKErrorState(
                message: 'Family not found',
                onRetry: () {
                  ref.invalidate(familyListProvider);
                  ref.invalidate(familyDetailProvider(widget.familyId));
                  ref.invalidate(familyMembersProvider(widget.familyId));
                  ref.invalidate(familyRelationshipsProvider(widget.familyId));
                },
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // P4-F7: Wrap high-risk graph tab with ErrorBoundary
              ErrorBoundary(
                child: _GraphTab(detail: detail, familyId: widget.familyId),
              ),
              // P4-F7: Wrap member list with ErrorBoundary
              ErrorBoundary(
                child: _MembersTab(detail: detail, familyId: widget.familyId),
              ),
              _ActivityTab(detail: detail, familyId: widget.familyId),
            ],
          );
        },
      ),
      // Bottom action bar — centered at bottom
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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

            // Delete option (available to creator only — moves family to deleted/archive)
            if (isCreator) ...[
              Divider(color: KinrelColors.border, height: 1),
              _QuickActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete Family',
                iconColor: KinrelColors.error,
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteFamily(context, family?.name ?? 'Family');
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

  void _showLeaveFamilyDialog(BuildContext context) {
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
              Icons.exit_to_app,
              color: KinrelColors.error,
              size: 24,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Leave Family?',
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
        content: Text(
          'You will no longer be a member of this family. You can rejoin if invited again.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: DKColors.textSecondary(context),
          ),
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _performLeaveFamily(context);
            },
            child: Text(
              'Leave Family',
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

  /// Perform leave family — removes the user's FamilyMember record
  /// without deleting the family itself.
  Future<void> _performLeaveFamily(BuildContext context) async {
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
      final client = ref.read(supabaseProvider);
      final userId = client?.auth.currentUser?.id;
      if (client == null || userId == null) {
        throw Exception('Not authenticated');
      }

      // Try NestJS API first
      bool left = false;
      try {
        final dio = ref.read(dioProvider);
        final response = await dio.delete('/api/families/${widget.familyId}/members/leave');
        if (response.statusCode == 200) {
          left = true;
        }
      } on DioException catch (_) {
        // Fall through to Supabase fallback
      }

      // Fallback: Delete FamilyMember record directly
      if (!left) {
        await client
            .from('FamilyMember')
            .delete()
            .eq('familyId', widget.familyId)
            .eq('userId', userId);
      }

      // Invalidate providers to refresh UI
      ref.invalidate(familyListProvider);
      ref.invalidate(archivedFamiliesProvider);

      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You left the family'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/families');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to leave: ${e.toString().split('\n').first}',
            ),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Confirm Delete Family dialog — soft-deletes (moves to archive/deleted)
  /// where it can be restored within 30 days or permanently deleted.
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
              'This family will be moved to deleted and hidden from your active list.',
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
                      'You can restore it from deleted families within 30 days. After that, it will be permanently deleted.',
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
              Navigator.of(ctx).pop(); // Close dialog
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

  /// Perform delete family — soft-deletes (moves to archive).
  /// Can be restored from "Deleted Families" within 30 days.
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
            content: Text('Family moved to deleted. Restore within 30 days.'),
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
              'Failed to delete: ${e.toString().split('\n').first}',
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
    final detail = widget.detail;
    final familyId = widget.familyId;

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

        // Full-screen graph button
        Positioned(
          top: 60,
          right: 12,
          child: _ToolbarButton(
            icon: Icons.fullscreen_rounded,
            tooltip: 'Full Screen Graph',
            onTap: () => context.push('/family/$familyId/graph'),
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
                  await deletePerson(
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
                onTap: () => context.push('/family/$familyId/graph'),
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
