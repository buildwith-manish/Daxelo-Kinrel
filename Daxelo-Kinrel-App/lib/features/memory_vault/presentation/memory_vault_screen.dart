// lib/features/memory_vault/presentation/memory_vault_screen.dart
//
// DAXELO KINREL — Memory Vault Screen
//
// Full-screen photo vault for family memories.
// Two tabs: "All Photos" (grid) and "On This Day" (list).
// Upload flow via bottom sheet with camera/gallery picker,
// caption, date picker, member tagger.
//
// TIER GATING (per the tier revision pass):
// Free users may upload up to 50 photos per calendar month (soft
// cap — storage has real marginal cost, unlike member/family
// counts). The cap is tracked per-device via SharedPreferences in
// PremiumService. When a free user hits the cap, they see a
// non-alarming in-context paywall framed as "remove the limit"
// (PaywallTrigger.memoryVaultLimit), NOT as "unlock this feature"
// — uploads already work for free, the upsell just removes
// friction. An informational "running low" banner appears as the
// user approaches the cap (>= 80% used) so they're not surprised.
// Kinrel Plus users have unlimited uploads.
//
// IMPORTANT: Razorpay payment capture remains STUBBED — tapping
// "Subscribe" grants Premium without real payment. See
// paywall_screen.dart and the tier-structure commit message.
//
// Orange K-Graph DNA: #131416 bg, #191B2C cards, #E8612A accent,
// KinrelGradients.igniteGradient CTA.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../shared/widgets/kinrel_skeleton.dart';
import '../../../shared/widgets/paywall_sheet.dart';
import '../providers/memory_vault_provider.dart';
import '../data/memory_model.dart';
import 'memory_detail_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
// Memory Vault Screen
// ═══════════════════════════════════════════════════════════════════════

class MemoryVaultScreen extends ConsumerStatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  ConsumerState<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends ConsumerState<MemoryVaultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memoryVaultProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: _buildAppBar(state),
      body: Column(
        children: [
          // Custom tab chips
          _buildTabChips(),

          // Tab content
          Expanded(
            child: state.isLoading && !state.hasMemories
                ? _buildLoadingGrid()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // All Photos tab
                      _buildAllPhotosTab(state),
                      // On This Day tab
                      _buildOnThisDayTab(state),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // App Bar
  // ═══════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(MemoryVaultState state) {
    return AppBar(
      backgroundColor: KinrelColors.darkBackground,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: KinrelColors.textWhite, size: 20),
        onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Memory Vault',
            style: KinrelTypography.headlineMedium.copyWith(
              color: KinrelColors.textWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: KinrelColors.amber,
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        _buildUploadButton(state),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildUploadButton(MemoryVaultState state) {
    return Container(
      decoration: BoxDecoration(
        gradient: KinrelGradients.igniteGradient,
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        boxShadow: [
          const BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          onTap: state.isUploading ? null : () => _handleUploadTap(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.isUploading
                      ? Icons.hourglass_top_rounded
                      : Icons.add_photo_alternate_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  state.isUploading ? 'Uploading...' : 'Upload',
                  style: KinrelTypography.labelMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Tab Chips (Custom — NOT default TabBar)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTabChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      child: Row(
        children: [
          _buildChip(
            label: 'All Photos',
            index: 0,
            icon: Icons.photo_library_rounded,
          ),
          const SizedBox(width: 10),
          _buildChip(
            label: 'On This Day',
            index: 1,
            icon: Icons.today_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required int index,
    required IconData icon,
  }) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() => _selectedTab = index);
      },
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelColors.orange.withValues(alpha: 0.15)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange.withValues(alpha: 0.5)
                : const Color(0xFF3A3A4A),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? KinrelColors.orange : KinrelColors.textDim,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: KinrelTypography.labelMedium.copyWith(
                color: isSelected ? KinrelColors.orange : KinrelColors.textSilver,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (index == 1 && isSelected) ...[
              const SizedBox(width: 6),
              Consumer(
                builder: (context, ref, _) {
                  final count = ref.watch(onThisDayMemoriesProvider).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: KinrelGradients.igniteGradient,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                    ),
                    child: Text(
                      '$count',
                      style: KinrelTypography.micro.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // All Photos Tab — GridView with 3 columns
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAllPhotosTab(MemoryVaultState state) {
    if (!state.isLoading && state.memories.isEmpty) {
      return _buildEmptyState();
    }

    // Feature 8: use vault-sorted memories (pinned first, then newest)
    final sortedMemories = state.vaultSortedMemories;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.xl,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: sortedMemories.length,
      itemBuilder: (context, index) {
        final memory = sortedMemories[index];
        return _buildPhotoTile(memory);
      },
    );
  }

  Widget _buildPhotoTile(MemoryModel memory) {
    return GestureDetector(
      onTap: () => _navigateToDetail(memory),
      onLongPress: () => _showContextMenu(memory),
      child: Hero(
        tag: 'memory_${memory.id}',
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: memory.displayImageUrl,
                cacheManager: KinrelImageCacheManager.instance,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                memCacheHeight: 300,
                placeholder: (context, url) => _buildShimmerTile(),
                errorWidget: (context, url, error) => Container(
                  color: KinrelColors.darkCard,
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: KinrelColors.textDim,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            // Feature 8: Pin badge on pinned memories
            if (memory.isPinnedToVault)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.push_pin_rounded,
                    size: 12,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            // Feature 6: From-post badge
            if (memory.isFromPost)
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.article_outlined,
                    size: 10,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerTile() {
    return Shimmer.fromColors(
      baseColor: KinrelColors.darkElevated,
      highlightColor: KinrelColors.darkCard,
      child: Container(
        color: KinrelColors.darkCard,
      ),
    );
  }

  Widget _buildLoadingGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.xl,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: 12,
      itemBuilder: (context, index) => _buildShimmerTile(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // On This Day Tab — Vertical list of DKCard items
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildOnThisDayTab(MemoryVaultState state) {
    final onThisDay = state.onThisDayMemories;

    if (onThisDay.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.today_rounded,
                size: 40,
                color: KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No memories on this day',
              style: KinrelTypography.headlineSmall.copyWith(
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Memories from this date in past years\nwill appear here.',
              textAlign: TextAlign.center,
              style: KinrelTypography.bodyMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.xxl,
      ),
      itemCount: onThisDay.length,
      separatorBuilder: (_, __) => const SizedBox(height: KinrelSpacing.md),
      itemBuilder: (context, index) {
        return _OnThisDayCard(memory: onThisDay[index]);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Empty State
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.photo_album_rounded,
                size: 48,
                color: KinrelColors.orange,
              ),
            )
                .animate(onPlay: (c) => c.forward())
                .fadeIn(duration: KinrelMotion.normal)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  duration: KinrelMotion.slow,
                  curve: KinrelMotion.spring,
                ),
            const SizedBox(height: 24),
            Text(
              'Your Memory Vault is empty',
              style: KinrelTypography.headlineMedium.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Upload your first family photo to\nstart building your vault!',
              textAlign: TextAlign.center,
              style: KinrelTypography.bodyMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 28),
            DKButton(
              label: 'Upload First Photo',
              variant: DKButtonVariant.gradient,
              icon: Icons.add_photo_alternate_rounded,
              size: DKButtonSize.lg,
              onPressed: () => _handleUploadTap(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Upload Flow
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _handleUploadTap() async {
    // ── Soft cap check (per the tier revision pass) ────────────────
    // Free users may upload up to 50 photos per calendar month
    // (storage has real marginal cost). When the cap is hit, show a
    // non-alarming in-context paywall framed as "remove the limit"
    // (PaywallTrigger.memoryVaultLimit), NOT as "unlock this
    // feature" — uploads already work for free; the upsell just
    // removes friction. Premium (Kinrel Plus) users have unlimited
    // uploads and bypass this check entirely.
    //
    // When APPROACHING the cap (>= 80% used but not yet at the cap),
    // show a non-alarming informational SnackBar so the user isn't
    // surprised when they hit it. This is the "clear in-context
    // message when approaching" half of the requirement.
    final canUpload = await PremiumService.canUploadMemoryVaultPhoto();
    final used = await PremiumService.getMemoryVaultUploadsThisMonth();
    final cap = PremiumService.memoryVaultFreeMonthlyCap;
    if (!canUpload && mounted) {
      // Hit the cap — show the soft-cap paywall (not a hard block
      // on the feature; the upload sheet itself never opens here).
      PaywallSheet.show(
        context: context,
        trigger: PaywallTrigger.memoryVaultLimit,
        currentCount: used,
        maxFree: cap,
      );
      return;
    }
    // Approaching the cap (>= 80% used, but still under). Show a
    // non-alarming SnackBar before opening the upload sheet. The
    // SnackBar is dismissible and does NOT block the upload.
    if (mounted && used >= (cap * 0.8).round() && used < cap) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Running low on uploads this month — $used of $cap used. '
            'Kinrel Plus removes this limit.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // Feature 1 + 2: open the new structured memory create screen
    // (image picker → crop editor → compression → preview → upload)
    // instead of the legacy gallery-only upload sheet.
    context.push('/memory/create');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Context Menu (Long Press)
  // ═══════════════════════════════════════════════════════════════════

  void _showContextMenu(MemoryModel memory) {
    final client = ref.read(supabaseProvider);
    final currentUserId = client?.auth.currentUser?.id;
    final isOwner = currentUserId == memory.uploaderId;

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_rounded,
                    color: KinrelColors.orange),
                title: Text(
                  'View',
                  style: KinrelTypography.bodyLarge.copyWith(
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToDetail(memory);
                },
              ),
              // Feature 8: Pin / Unpin memory to vault
              ListTile(
                leading: Icon(
                  memory.isPinnedToVault
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: memory.isPinnedToVault
                      ? KinrelColors.orange
                      : KinrelColors.textSilver,
                ),
                title: Text(
                  memory.isPinnedToVault ? 'Unpin From Vault' : 'Pin To Vault',
                  style: KinrelTypography.bodyLarge.copyWith(
                    color: memory.isPinnedToVault
                        ? KinrelColors.orange
                        : KinrelColors.textWhite,
                    fontWeight: memory.isPinnedToVault
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(memoryVaultProvider.notifier)
                      .togglePinToVault(memory.id);
                },
              ),
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: KinrelColors.error),
                  title: Text(
                    'Delete',
                    style: KinrelTypography.bodyLarge.copyWith(
                      color: KinrelColors.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(memory);
                  },
                ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(MemoryModel memory) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: KinrelColors.darkElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
          title: Text(
            'Delete Memory?',
            style: KinrelTypography.headlineSmall.copyWith(
              color: KinrelColors.textWhite,
            ),
          ),
          content: Text(
            'This photo will be permanently removed from the Memory Vault.',
            style: KinrelTypography.bodyMedium.copyWith(
              color: KinrelColors.textSilver,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: KinrelTypography.labelLarge.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ref
                    .read(memoryVaultProvider.notifier)
                    .deleteMemory(memory.id);
              },
              child: Text(
                'Delete',
                style: KinrelTypography.labelLarge.copyWith(
                  color: KinrelColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Navigation
  // ═══════════════════════════════════════════════════════════════════

  void _navigateToDetail(MemoryModel memory) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) {
          return MemoryDetailScreen(memory: memory);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// On This Day Card — DKCard with 16:9 photo, caption, date, uploader
// ═══════════════════════════════════════════════════════════════════════

class _OnThisDayCard extends StatelessWidget {
  const _OnThisDayCard({required this.memory});

  final MemoryModel memory;

  @override
  Widget build(BuildContext context) {
    return DKCard(
      padding: 0,
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, animation, __) {
              return FadeTransition(
                opacity: animation,
                child: MemoryDetailScreen(memory: memory),
              );
            },
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 16:9 photo
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(KinrelRadius.lg),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: memory.displayImageUrl,
                cacheManager: KinrelImageCacheManager.instance,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: KinrelColors.darkElevated,
                  child: const Center(
                    child: KinrelSkeletonBox(width: 40, height: 40),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: KinrelColors.darkElevated,
                  child: const Icon(
                    Icons.broken_image_rounded,
                    color: KinrelColors.textDim,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),

          // Content below photo
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Caption
                if (memory.caption != null && memory.caption!.isNotEmpty) ...[
                  Text(
                    memory.caption!,
                    style: KinrelTypography.bodyMedium.copyWith(
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],

                // Date + Years ago badge
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: KinrelColors.textDim,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      memory.formattedDate,
                      style: KinrelTypography.labelSmall.copyWith(
                        color: KinrelColors.textSilver,
                      ),
                    ),
                    if (memory.yearsAgo != null && memory.yearsAgo! > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: KinrelGradients.igniteGradient,
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.full),
                        ),
                        child: Text(
                          '${memory.yearsAgo}y ago',
                          style: KinrelTypography.micro.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Uploader name
                Row(
                  children: [
                    CachedAvatar(
                      radius: 12,
                      backgroundColor: KinrelColors.orange.withValues(alpha: 0.2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      memory.uploaderName.isNotEmpty
                          ? memory.uploaderName
                          : 'Unknown',
                      style: KinrelTypography.labelSmall.copyWith(
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
