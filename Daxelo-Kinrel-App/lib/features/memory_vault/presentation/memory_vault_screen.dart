// lib/features/memory_vault/presentation/memory_vault_screen.dart
//
// DAXELO KINREL — Memory Vault Screen
//
// Full-screen photo vault for family memories.
// Two tabs: "All Photos" (grid) and "On This Day" (list).
// Upload flow via bottom sheet with camera/gallery picker,
// caption, date picker, member tagger.
// Premium gating: upload requires PremiumService.isPremium().
//
// Orange K-Graph DNA: #131416 bg, #191B2C cards, #E8612A accent,
// KinrelGradients.igniteGradient CTA.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/memory_vault_provider.dart';
import '../data/memory_model.dart';

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
        onPressed: () => context.pop(),
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
          Icon(
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
          BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 8,
            offset: const Offset(0, 2),
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
      padding: EdgeInsets.symmetric(
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

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
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
      itemCount: state.memories.length,
      itemBuilder: (context, index) {
        final memory = state.memories[index];
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: memory.photoUrl,
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
      padding: EdgeInsets.fromLTRB(
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
      padding: EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.xxl,
      ),
      itemCount: onThisDay.length,
      separatorBuilder: (_, __) => SizedBox(height: KinrelSpacing.md),
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
        padding: EdgeInsets.all(KinrelSpacing.xl),
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
    final isPremium = await PremiumService.isPremium();
    if (!isPremium) {
      _showPaywallCard();
      return;
    }
    _showUploadSheet();
  }

  void _showPaywallCard() {
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
          child: Padding(
            padding: EdgeInsets.all(KinrelSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KinrelGradients.achievementGradient,
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Premium Feature',
                  style: KinrelTypography.headlineMedium.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload photos to the Memory Vault is available\nfor Kinrel Premium members.',
                  textAlign: TextAlign.center,
                  style: KinrelTypography.bodyMedium.copyWith(
                    color: KinrelColors.textSilver,
                  ),
                ),
                const SizedBox(height: 24),
                DKButton(
                  label: 'Upgrade to Premium',
                  variant: DKButtonVariant.gradient,
                  icon: Icons.auto_awesome_rounded,
                  fullWidth: true,
                  size: DKButtonSize.lg,
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/premium');
                  },
                ),
                const SizedBox(height: 12),
                DKButton(
                  label: 'Maybe Later',
                  variant: DKButtonVariant.secondary,
                  fullWidth: true,
                  size: DKButtonSize.md,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return _UploadMemorySheet();
      },
    );
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
              if (isOwner)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
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
                imageUrl: memory.photoUrl,
                cacheManager: KinrelImageCacheManager.instance,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: KinrelColors.darkElevated,
                  child: Center(
                    child: DKLoadingShimmer(),
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
                    Icon(
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

// ═══════════════════════════════════════════════════════════════════════
// Upload Memory Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════

class _UploadMemorySheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_UploadMemorySheet> createState() =>
      _UploadMemorySheetState();
}

class _UploadMemorySheetState extends ConsumerState<_UploadMemorySheet> {
  final _captionController = TextEditingController();
  DateTime _takenAt = DateTime.now();
  final Set<String> _selectedMemberIds = {};
  XFile? _selectedFile;
  bool _isPicking = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memoryVaultProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          KinrelSpacing.base,
          KinrelSpacing.base,
          KinrelSpacing.base,
          MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.base,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Upload Memory',
                style: KinrelTypography.headlineMedium.copyWith(
                  color: KinrelColors.textWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),

              // Camera / Gallery picker row
              _buildImagePickerRow(),
              const SizedBox(height: 16),

              // Caption TextField
              _buildCaptionField(),
              const SizedBox(height: 16),

              // Date picker
              _buildDatePicker(),
              const SizedBox(height: 16),

              // Member tag picker
              _buildMemberTagger(),
              const SizedBox(height: 24),

              // Upload progress
              if (state.isUploading) ...[
                _buildUploadProgress(state),
                const SizedBox(height: 16),
              ],

              // Confirm button
              DKButton(
                label: state.isUploading
                    ? state.uploadProgress ?? 'Uploading...'
                    : 'Upload Memory',
                variant: DKButtonVariant.gradient,
                icon: state.isUploading ? null : Icons.cloud_upload_rounded,
                fullWidth: true,
                size: DKButtonSize.lg,
                isLoading: state.isUploading,
                onPressed: state.isUploading || _selectedFile == null
                    ? null
                    : _handleUpload,
              ),

              // Error display
              if (state.error != null) ...[
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
                      const Icon(Icons.error_outline_rounded,
                          color: KinrelColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!,
                          style: KinrelTypography.bodySmall.copyWith(
                            color: KinrelColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePickerRow() {
    return Row(
      children: [
        // Camera
        Expanded(
          child: GestureDetector(
            onTap: _isPicking ? null : () => _pickImage(ImageSource.camera),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: _selectedFile != null
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : const Color(0xFF3A3A4A),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.camera_alt_rounded,
                    color: _selectedFile != null
                        ? KinrelColors.orange
                        : KinrelColors.textDim,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Camera',
                    style: KinrelTypography.labelSmall.copyWith(
                      color: _selectedFile != null
                          ? KinrelColors.orange
                          : KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Gallery
        Expanded(
          child: GestureDetector(
            onTap: _isPicking ? null : () => _pickImage(ImageSource.gallery),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: _selectedFile != null
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : const Color(0xFF3A3A4A),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.photo_library_rounded,
                    color: _selectedFile != null
                        ? KinrelColors.orange
                        : KinrelColors.textDim,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Gallery',
                    style: KinrelTypography.labelSmall.copyWith(
                      color: _selectedFile != null
                          ? KinrelColors.orange
                          : KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Caption',
          style: KinrelTypography.labelMedium.copyWith(
            color: KinrelColors.textSilver,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _captionController,
          maxLength: 200,
          maxLines: 3,
          style: KinrelTypography.bodyMedium.copyWith(
            color: KinrelColors.textWhite,
          ),
          decoration: InputDecoration(
            hintText: 'What makes this memory special?',
            hintStyle: KinrelTypography.bodyMedium.copyWith(
              color: KinrelColors.textDim,
            ),
            filled: true,
            fillColor: KinrelColors.darkElevated,
            counterStyle: KinrelTypography.labelSmall.copyWith(
              color: KinrelColors.textDim,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide: const BorderSide(color: Color(0xFF3A3A4A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide: const BorderSide(color: Color(0xFF3A3A4A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide:
                  BorderSide(color: KinrelColors.orange, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _takenAt,
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: KinrelColors.orange,
                  surface: KinrelColors.darkCard,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() => _takenAt = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: const Color(0xFF3A3A4A)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: KinrelColors.orange,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'When was this taken?',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textDim,
              ),
            ),
            const Spacer(),
            Text(
              _formatDate(_takenAt),
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: KinrelColors.textDim,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTagger() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tag Family Members',
          style: KinrelTypography.labelMedium.copyWith(
            color: KinrelColors.textSilver,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Consumer(
          builder: (context, ref, _) {
            final familiesAsync = ref.watch(familyListProvider);
            final families = familiesAsync.valueOrNull;
            if (families == null || families.isEmpty) {
              return Text(
                'No family members found',
                style: KinrelTypography.bodySmall.copyWith(
                  color: KinrelColors.textDim,
                ),
              );
            }

            // Load members for the first family
            final familyId = families.first.id;
            final membersAsync = ref.watch(familyMembersProvider(familyId));
            final members = membersAsync.valueOrNull ?? [];

            if (members.isEmpty) {
              return Text(
                'No family members found',
                style: KinrelTypography.bodySmall.copyWith(
                  color: KinrelColors.textDim,
                ),
              );
            }

            return SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: members.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final member = members[index];
                  final isSelected =
                      _selectedMemberIds.contains(member.id);
                  final initials = member.name
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .take(2)
                      .map((s) => s[0].toUpperCase())
                      .join();

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedMemberIds.remove(member.id);
                        } else {
                          _selectedMemberIds.add(member.id);
                        }
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: KinrelColors.orange,
                                    width: 2.5,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          KinrelColors.orangeGlow,
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: InitialsAvatar(
                            imageUrl: member.photoUrl,
                            initials: initials,
                            radius: 22,
                            backgroundColor: isSelected
                                ? KinrelColors.orange
                                    .withValues(alpha: 0.3)
                                : KinrelColors.darkElevated,
                            foregroundColor: isSelected
                                ? KinrelColors.orange
                                : KinrelColors.textSilver,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 56,
                          child: Text(
                            member.name.split(' ').first,
                            style: KinrelTypography.micro.copyWith(
                              color: isSelected
                                  ? KinrelColors.orange
                                  : KinrelColors.textDim,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUploadProgress(MemoryVaultState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(KinrelColors.orange),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.uploadProgress ?? 'Processing...',
                  style: KinrelTypography.labelMedium.copyWith(
                    color: KinrelColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  backgroundColor: KinrelColors.darkElevated,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      KinrelColors.orange),
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isPicking = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (file != null) {
        setState(() => _selectedFile = file);
      }
    } catch (e) {
      debugPrint('⚠️ Image picker error: $e');
    } finally {
      setState(() => _isPicking = false);
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFile == null) return;

    await ref.read(memoryVaultProvider.notifier).uploadMemory(
          _selectedFile!,
          caption: _captionController.text.trim().isEmpty
              ? null
              : _captionController.text.trim(),
          takenAt: _takenAt,
          taggedPersonIds: _selectedMemberIds.toList(),
        );

    final state = ref.read(memoryVaultProvider);
    if (!state.isUploading && state.error == null) {
      Navigator.pop(context);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }
}
