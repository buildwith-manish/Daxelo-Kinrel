import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_actions.dart';
import '../../../core/family/drift_stream_providers.dart';
import '../../../core/family/pagination_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../presentation/widgets/skeletons/family_list_skeleton.dart';
import 'join_family_screen.dart';
import 'qr_scanner_screen.dart';

class FamilyListScreen extends ConsumerStatefulWidget {
  FamilyListScreen({super.key});

  @override
  ConsumerState<FamilyListScreen> createState() => _FamilyListScreenState();
}

class _FamilyListScreenState extends ConsumerState<FamilyListScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll listener for cursor-based pagination loadMore.
  /// Triggers when the user scrolls within 500px of the bottom.
  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (maxScroll - currentScroll <= 500) {
        final state = ref.read(paginatedFamilyProvider);
        if (state.hasMore && !state.isLoadingMore) {
          ref.read(paginatedFamilyProvider.notifier).loadMore();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final familiesAsync = ref.watch(hybridFamilyListProvider);

    return DKScaffold(
      body: familiesAsync.when(
        loading: () => const _FamilyListLoadingWidget(),
        error: (error, _) => DKErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(familyListProvider),
        ),
        data: (families) {
          return CustomScrollView(
            controller: _scrollController,
            scrollCacheExtent: ScrollCacheExtent.pixels(500),
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: _Header(
                  familyCount: families.length,
                  onArchivedTap: () => _showArchivedFamilies(context),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Join Family card
              SliverToBoxAdapter(
                child: _JoinFamilyCard(
                  onJoin: () => _showJoinFamilyDialog(context),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 20)),

              // Family cards or empty state
              if (families.isEmpty)
                SliverToBoxAdapter(
                  child: DKEmptyState(
                    icon: Icons.family_restroom_rounded,
                    title: 'No Families Yet',
                    subtitle:
                        'Create your first family tree to start exploring relationships and kinship terms.',
                    actionLabel: 'Create Family',
                    onAction: () => context.push('/families/create'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      // Last item: loading indicator for pagination
                      if (index == families.length) {
                        final pagState = ref.watch(paginatedFamilyProvider);
                        if (pagState.isLoadingMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      final family = families[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FamilyCard(
                          family: family,
                          index: index,
                          onTap: () => context.push('/family/${family.id}/graph?name=${Uri.encodeComponent(family.name)}'),
                        ),
                      );
                    }, childCount: families.length + 1),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton:
          Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: DKColors.brandGold, width: 2.5),
                  color: DKColors.brandPurple.withValues(alpha: 0.1),
                ),
                child: IconButton(
                  onPressed: () => context.push('/families/create'),
                  icon: Icon(Icons.add_rounded, size: 28),
                  color: DKColors.brandPurple,
                  tooltip: 'Create family',
                ),
              )
              .animate(onPlay: (c) => c.forward())
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
    );
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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DKColors.brandPurple.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.link_rounded,
                color: DKColors.brandPurple,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Join Family',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                color: DKColors.textPrimary(context),
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
                color: DKColors.textSecondary(context),
                height: 1.5,
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
                hintStyle: TextStyle(
                  color: DKColors.textSecondary(context).withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: DKColors.elevatedColor(context),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: DKColors.textSecondary(context),
                  size: 20,
                ),
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
            child: Text(
              'Cancel',
              style: TextStyle(color: DKColors.textSecondary(context)),
            ),
          ),
          DKButton(
            label: 'Join',
            variant: DKButtonVariant.primary,
            size: DKButtonSize.sm,
            onPressed: () {
              Navigator.pop(ctx);
              // 1K: Join Family — gated behind kEnableQrJoin
              if (kEnableQrJoin) {
                _showJoinOptionsBottomSheet(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Join family coming soon!')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// 1K: Shows a bottom sheet with "Scan QR" and "Enter ID manually" options.
  void _showJoinOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DKColors.cardColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.qr_code_scanner_rounded,
                  color: KinrelColors.orange, size: 28),
              title: Text('Scan QR Code',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  )),
              subtitle: Text('Scan a family QR code to join instantly',
                  style: TextStyle(
                    fontSize: 13,
                    color: KinrelColors.textSilver,
                  )),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const QrScannerScreen(),
                  ),
                ).then((familyId) {
                  if (familyId != null && familyId.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => JoinFamilyScreen(kinFamilyId: familyId),
                      ),
                    );
                  }
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.keyboard_rounded,
                  color: KinrelColors.textSilver, size: 28),
              title: Text('Enter Family ID',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  )),
              subtitle: Text('Enter a family code manually',
                  style: TextStyle(
                    fontSize: 13,
                    color: KinrelColors.textSilver,
                  )),
              onTap: () {
                Navigator.pop(ctx);
                _showManualFamilyIdDialog(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 1K: Dialog to enter a family ID manually.
  void _showManualFamilyIdDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: Text('Enter Family ID',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              color: KinrelColors.textWhite,
            )),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'e.g., kin-family-abc123',
            hintStyle: TextStyle(color: KinrelColors.textDim),
            filled: true,
            fillColor: KinrelColors.darkElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: KinrelColors.orange),
            ),
          ),
          style: TextStyle(color: KinrelColors.textWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: KinrelColors.textSilver)),
          ),
          DKButton(
            label: 'Join',
            variant: DKButtonVariant.primary,
            size: DKButtonSize.sm,
            onPressed: () {
              final id = controller.text.trim();
              Navigator.pop(ctx);
              if (id.isNotEmpty) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => JoinFamilyScreen(kinFamilyId: id),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showArchivedFamilies(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DKColors.cardColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => const _ArchivedFamiliesSheet(),
    );
  }
}

// ── Loading Widget (extracted for zero-rebuild optimization) ─────

class _FamilyListLoadingWidget extends ConsumerWidget {
  const _FamilyListLoadingWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const FamilyListSkeleton(itemCount: 4);
  }
}

// ── Header ───────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.familyCount, required this.onArchivedTap});

  final int familyCount;
  final VoidCallback onArchivedTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: KinrelSpacing.md,
          ),
          child: Row(
            children: [
              Text(
                'My Families',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: DKColors.textPrimary(context),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: DKColors.brandPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$familyCount',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DKColors.brandPurple,
                  ),
                ),
              ),
              const Spacer(),
              // Archived Families button
              GestureDetector(
                onTap: onArchivedTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: DKColors.brandPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: DKColors.brandPurple.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.archive_outlined,
                        size: 16,
                        color: DKColors.brandPurple,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Archived',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DKColors.brandPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 300.ms)
        .slideX(begin: -0.1, end: 0, duration: 300.ms);
  }
}

// ── Join Family Card ─────────────────────────────────────────────

class _JoinFamilyCard extends StatelessWidget {
  const _JoinFamilyCard({required this.onJoin});

  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: DKCard(
            borderColor: DKColors.brandGold.withValues(alpha: 0.3),
            backgroundColor: DKColors.brandGold.withValues(alpha: 0.06),
            onTap: onJoin,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DKColors.brandGold.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    color: DKColors.brandGold,
                    size: 20,
                  ),
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
                          color: DKColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Enter a family code to join an existing family',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: DKColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: DKColors.brandGold,
                ),
              ],
            ),
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms, delay: 100.ms);
  }
}

// ── Family Card ──────────────────────────────────────────────────

class _FamilyCard extends ConsumerWidget {
  const _FamilyCard({
    required this.family,
    required this.index,
    required this.onTap,
  });

  final Family family;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // familyMemberCountProvider now returns int directly (not AsyncValue)
    final memberCount = ref.watch(familyMemberCountProvider(family.id));
    final languageName = family.primaryLanguage != null
        ? SupportedLanguage.fromCode(family.primaryLanguage!).name
        : 'English';

    final slug = family.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final idSuffix = family.id.length >= 4
        ? family.id.substring(0, 4)
        : family.id;
    // Show @username if available, otherwise fallback to slug
    final familyCode = family.username != null
        ? '@${family.username}'
        : 'kinrel.co/f/$slug-$idSuffix';

    return DKCard(
          borderColor: DKColors.brandPurple.withValues(alpha: 0.2),
          onTap: onTap,
          onLongPress: () => _showFamilyQuickActions(context, ref),
          child: Row(
            children: [
              // v62.5: Show family avatar if available, otherwise initials.
              family.avatarUrl != null && family.avatarUrl!.isNotEmpty
                  ? CachedAvatar(
                      imageUrl: family.avatarUrl,
                      radius: 28,
                      backgroundColor: DKColors.brandPurple,
                      border: Border.all(
                        color: DKColors.brandGold.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    )
                  : DKAvatar(
                      initials: family.name.isNotEmpty
                          ? family.name[0].toUpperCase()
                          : 'F',
                      size: DKAvatarSize.lg,
                      backgroundColor: DKColors.brandPurple,
                      borderColor: DKColors.brandGold.withValues(alpha: 0.4),
                    ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            family.name,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: DKColors.textPrimary(context),
                            ),
                          ),
                        ),
                        // Creator badge
                        if (_isCreator(ref))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: KinrelColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: KinrelColors.gold.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: 10,
                                  color: KinrelColors.gold,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Creator',
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: KinrelColors.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      familyCode,
                      style: TextStyle(
                        fontFamily: family.username != null
                            ? KinrelTypography.bodyFont
                            : KinrelTypography.monoFont,
                        fontSize: 10,
                        color: family.username != null
                            ? DKColors.brandPurple
                            : DKColors.textSecondary(
                                context,
                              ).withValues(alpha: 0.7),
                        fontWeight: family.username != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Member count — familyMemberCountProvider returns int directly
                        DKStatChip(
                          icon: Icons.people_outline_rounded,
                          value: '$memberCount',
                          label: 'members',
                          color: DKColors.brandPurple,
                        ),
                        const SizedBox(width: 10),
                        // Language
                        Icon(
                          Icons.translate_rounded,
                          size: 13,
                          color: DKColors.textSecondary(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          languageName,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: DKColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right,
                color: DKColors.brandPurple.withValues(alpha: 0.6),
              ),
            ],
          ),
        )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: 100 + index * 60),
        )
        .slideX(begin: 0.1, end: 0, duration: 400.ms);
  }

  bool _isCreator(WidgetRef ref) {
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    return family.createdBy != null && family.createdBy == currentUserId;
  }

  void _showFamilyQuickActions(BuildContext context, WidgetRef ref) {
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
                    initials: family.name.isNotEmpty
                        ? family.name[0].toUpperCase()
                        : 'F',
                    size: DKAvatarSize.md,
                    backgroundColor: DKColors.brandPurple,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      family.name,
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
            ListTile(
              leading: Icon(
                Icons.visibility_outlined,
                color: DKColors.textSecondary(context),
                size: 20,
              ),
              title: Text(
                'View Family',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: DKColors.textPrimary(context),
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/${family.id}');
              },
            ),
            // Delete option — moves family to archive
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: KinrelColors.error,
                size: 20,
              ),
              title: Text(
                'Delete Family',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.error,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteFamily(context, ref);
              },
            ),
            // Info: deleted families go to archive where they can be restored or permanently deleted
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFamily(BuildContext context, WidgetRef ref) {
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
                'Delete "${family.name}"?',
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
              await _performDeleteFamily(context, ref);
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

  Future<void> _performDeleteFamily(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Capture messenger AND container BEFORE async gap — the widget may be
    // disposed after deleteFamily invalidates providers and the list rebuilds.
    // ProviderContainer survives widget disposal, so the API call and
    // provider invalidation can safely continue in the background.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context);

    try {
      // v62.5: Add timeout so delete doesn't hang indefinitely.
      await deleteFamilyOptimistic(container: container, familyId: family.id)
          .timeout(const Duration(seconds: 15));
      messenger.showSnackBar(
        SnackBar(
          content: Text('${family.name} moved to archive'),
          backgroundColor: KinrelColors.success,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            textColor: Colors.white,
            onPressed: () =>
                restoreFamilyOptimistic(container: container, familyId: family.id),
          ),
        ),
      );
    } catch (e) {
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


}

// ── Archived Families Bottom Sheet ────────────────────────────────

class _ArchivedFamiliesSheet extends ConsumerStatefulWidget {
  const _ArchivedFamiliesSheet();

  @override
  ConsumerState<_ArchivedFamiliesSheet> createState() =>
      _ArchivedFamiliesSheetState();
}

class _ArchivedFamiliesSheetState
    extends ConsumerState<_ArchivedFamiliesSheet> {
  @override
  void initState() {
    super.initState();
    // FIXED: Use addPostFrameCallback to ensure the provider is invalidated
    // AFTER the widget tree is built. This forces a fresh API fetch every
    // time the sheet opens, so deleted families always appear immediately.
    // Previously, Future.microtask could fire before the sheet was mounted,
    // and the Drift cache path would return early with stale data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(archivedFamiliesProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final archivedAsync = ref.watch(archivedFamiliesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DKColors.textSecondary(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: KinrelSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.archive_outlined,
                    color: DKColors.brandPurple,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Archived Families',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: DKColors.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close,
                      color: DKColors.textSecondary(context),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: DKColors.borderColor(context), height: 1),
            // Content
            Expanded(
              child: archivedAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: DKColors.brandPurple,
                    strokeWidth: 2,
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(KinrelSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 40,
                          color: KinrelColors.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load archived families',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            color: DKColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DKButton(
                          label: 'Retry',
                          variant: DKButtonVariant.secondary,
                          size: DKButtonSize.sm,
                          onPressed: () =>
                              ref.invalidate(archivedFamiliesProvider),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (archivedFamilies) {
                  if (archivedFamilies.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(KinrelSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.archive_outlined,
                              size: 48,
                              color: DKColors.textSecondary(context)
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Archived Families',
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: DKColors.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Archived families will appear here.\nThey are automatically deleted after 30 days.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                color: DKColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base,
                      vertical: KinrelSpacing.sm,
                    ),
                    itemCount: archivedFamilies.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final archived = archivedFamilies[index];
                      return _ArchivedFamilyCard(archivedFamily: archived);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Archived Family Card ─────────────────────────────────────────

class _ArchivedFamilyCard extends ConsumerWidget {
  const _ArchivedFamilyCard({required this.archivedFamily});

  final ArchivedFamily archivedFamily;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysLeft = archivedFamily.daysRemaining;
    final isUrgent = daysLeft <= 7;
    final family = archivedFamily.family;

    // Per-family loading state from Riverpod — survives widget rebuilds
    final deletingIds = ref.watch(deletingFamilyIdsProvider);
    final restoringIds = ref.watch(restoringFamilyIdsProvider);
    final isDeleting = deletingIds.contains(family.id);
    final isRestoring = restoringIds.contains(family.id);

    return DKCard(
      borderColor: isUrgent
          ? KinrelColors.error.withValues(alpha: 0.3)
          : DKColors.brandPurple.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Family info row
          Row(
            children: [
              DKAvatar(
                initials: family.name.isNotEmpty
                    ? family.name[0].toUpperCase()
                    : 'F',
                size: DKAvatarSize.md,
                backgroundColor: DKColors.brandPurple.withValues(alpha: 0.5),
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
                        color: DKColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Archived date
                    if (archivedFamily.archivedAt != null)
                      Text(
                        'Archived ${_formatDate(archivedFamily.archivedAt!)}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: DKColors.textSecondary(context),
                        ),
                      ),
                  ],
                ),
              ),
              // Days remaining badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isUrgent
                      ? KinrelColors.error.withValues(alpha: 0.15)
                      : KinrelColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isUrgent
                        ? KinrelColors.error.withValues(alpha: 0.3)
                        : KinrelColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isUrgent ? KinrelColors.error : KinrelColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              // Restore button
              Expanded(
                child: DKButton(
                  label: 'Restore',
                  variant: DKButtonVariant.primary,
                  size: DKButtonSize.sm,
                  icon: Icons.restore,
                  isLoading: isRestoring,
                  onPressed: isRestoring ? null : () => _handleRestore(context, ref),
                ),
              ),
              const SizedBox(width: 10),
              // Permanent delete button
              Expanded(
                child: DKButton(
                  label: 'Delete Forever',
                  variant: DKButtonVariant.secondary,
                  size: DKButtonSize.sm,
                  icon: Icons.delete_forever,
                  isLoading: isDeleting,
                  onPressed: isDeleting ? null : () => _handlePermanentDelete(context, ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleRestore(BuildContext context, WidgetRef ref) async {
    // Capture container BEFORE async gap — the widget may be disposed
    // after restoreFamilyOptimistic invalidates providers.
    final container = ProviderScope.containerOf(context);

    try {
      await restoreFamilyOptimistic(container: container, familyId: archivedFamily.family.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${archivedFamily.family.name} restored'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to restore: ${e.toString().split('\n').first}',
            ),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handlePermanentDelete(BuildContext context, WidgetRef ref) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
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
                'Delete "${archivedFamily.family.name}" permanently?',
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
              'This will permanently delete this family and all its members, relationships, and data.',
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
              'Delete Forever',
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

    if (confirmed != true) return;

    // Capture container BEFORE async gap — the widget may be disposed
    // after permanentDeleteFamily invalidates providers.
    final container = ProviderScope.containerOf(context);

    try {
      await permanentDeleteFamily(container: container, familyId: archivedFamily.family.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${archivedFamily.family.name} permanently deleted'),
            backgroundColor: KinrelColors.success,
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
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
