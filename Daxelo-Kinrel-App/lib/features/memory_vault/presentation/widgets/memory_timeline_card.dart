// lib/features/memory_vault/presentation/widgets/memory_timeline_card.dart
//
// DAXELO KINREL — Redesigned Memory Timeline Card (v2)
//
// Production-ready timeline card that replaces the legacy text-heavy
// event card. Card layout per implementation prompt:
//
//   ┌───────────────────────┐
//   │ IMAGE                 │   ← CachedNetworkImage with lazy loading
//   ├───────────────────────┤       + shimmer placeholder + error fallback
//   │ FESTIVAL              │   ← memoryType label
//   │ Diwali Celebration    │   ← title
//   │ Story preview…       │   ← description (2-line max)
//   │ 📍 Jaipur             │   ← location (if set)
//   │ 👤 4 Members          │   ← member count
//   │ 1 Nov 2024            │   ← date
//   └───────────────────────┘
//
// When NO image is present, the card shows a memory-type icon
// placeholder instead of a blank space — never an empty rectangle.
//
// Performance:
//   - CachedNetworkImage with cacheManager + memCacheWidth/Height
//   - Skeleton shimmer while loading
//   - Image lazy-loads only when scrolled into view (ListView.builder
//     only builds visible items)
//
// Optional actions (passed via callbacks):
//   - onTap → opens memory detail screen
//   - onPin → toggles isPinnedToVault
//   - onViewOriginalPost → shown when sourcePostId is set

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/services/image_cache_manager.dart';
import '../../data/memory_model.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

/// Map of memory type labels to (icon, color) pairs.
/// Falls back to a generic bookmark when the type is unknown.
const _memoryTypeVisuals = <String, (IconData, Color)>{
  'Festival': (Icons.festival_rounded, KinrelColors.orange),
  'Birth': (Icons.child_care_rounded, KinrelColors.orange),
  'Marriage': (Icons.favorite_rounded, KinrelColors.amber),
  'Anniversary': (Icons.celebration_rounded, KinrelColors.gold),
  'Graduation': (Icons.school_rounded, KinrelColors.info),
  'Achievement': (Icons.emoji_events_rounded, KinrelColors.brightGold),
  'Migration': (Icons.flight_takeoff_rounded, KinrelColors.success),
  'Memorial': (Icons.auto_awesome_rounded, KinrelColors.textSilver),
  'Custom': (Icons.bookmark_rounded, KinrelColors.textDim),
};

(IconData, Color) _typeVisuals(String? type) {
  if (type == null) return (Icons.bookmark_rounded, KinrelColors.textDim);
  return _memoryTypeVisuals[type] ??
      (Icons.bookmark_rounded, KinrelColors.textDim);
}

class MemoryTimelineCard extends StatelessWidget {
  const MemoryTimelineCard({
    super.key,
    required this.memory,
    this.onTap,
    this.onPin,
    this.onViewOriginalPost,
    this.onViewAlbumInVault,
    this.albumPhotoCount,
    this.showPinButton = true,
  });

  /// The memory to render.
  final MemoryModel memory;

  /// Called when the user taps the card.
  final VoidCallback? onTap;

  /// Called when the user taps the pin toggle button.
  /// If null, no pin button is rendered.
  final VoidCallback? onPin;

  /// Called when the user taps "View Original Post".
  /// Only rendered when [MemoryModel.isFromPost] is true.
  final VoidCallback? onViewOriginalPost;

  /// Called when the user taps "View full album in Memory Vault →".
  /// Per the spec (Feature 3): "When a Timeline entry's photo
  /// corresponds to an event that also has additional photos stored in
  /// Memory Vault (e.g., tagged with the same date/event/category),
  /// show a 'View full album in Memory Vault →' link on that Timeline
  /// entry's detail view."
  ///
  /// Only rendered when [albumPhotoCount] is greater than 0 — the
  /// caller is responsible for computing the album size (see
  /// `MemoryVaultNotifier.albumForMemory` and the
  /// `memoryAlbumForMemoryProvider` derived provider).
  final VoidCallback? onViewAlbumInVault;

  /// Number of related photos in Memory Vault for this entry's event.
  /// When > 0 AND [onViewAlbumInVault] is non-null, the cross-link
  /// affordance is rendered. When 0 or null, the affordance is hidden
  /// (no related photos → no album to view).
  final int? albumPhotoCount;

  /// Whether to show the pin button (default true).
  /// Set false in contexts where pinning is not allowed (e.g. search results).
  final bool showPinButton;

  @override
  Widget build(BuildContext context) {
    final (typeIcon, typeColor) = _typeVisuals(memory.memoryType);
    final typeLabel = memory.memoryType?.toUpperCase() ?? 'MEMORY';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onPin,
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base, vertical: 6),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: memory.isPinnedToVault
                ? _cOrange.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.06),
            width: memory.isPinnedToVault ? 1.5 : 1,
          ),
          boxShadow: memory.isPinnedToVault
              ? [
                  BoxShadow(
                    color: _cOrange.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover image OR placeholder ────────────────────────────
            _buildCoverSection(typeIcon, typeColor),

            // ── Body content ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type label + pin button
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.full),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(typeIcon, size: 11, color: typeColor),
                            const SizedBox(width: 4),
                            Text(
                              typeLabel,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: typeColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (showPinButton && onPin != null)
                        _PinButton(
                          isPinned: memory.isPinnedToVault,
                          onTap: onPin!,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Title
                  Text(
                    memory.displayTitle,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _cTextPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Description (story preview)
                  if (memory.displayDescription != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      memory.displayDescription!,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: _cTextSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Meta row: location + members + date
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (memory.location != null &&
                          memory.location!.isNotEmpty)
                        _MetaChip(
                          icon: Icons.location_on_outlined,
                          text: memory.location!,
                        ),
                      if (memory.memberCount > 0)
                        _MetaChip(
                          icon: Icons.person_outline_rounded,
                          text: '${memory.memberCount} '
                              '${memory.memberCount == 1 ? 'Member' : 'Members'}',
                        ),
                      _MetaChip(
                        icon: Icons.calendar_today_outlined,
                        text: memory.formattedDate,
                      ),
                    ],
                  ),

                  // From-post badge + View Original Post button
                  if (memory.isFromPost) ...[
                    const SizedBox(height: 10),
                    if (onViewOriginalPost != null)
                      GestureDetector(
                        onTap: onViewOriginalPost,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _cOrange.withValues(alpha: 0.10),
                            borderRadius:
                                BorderRadius.circular(KinrelRadius.full),
                            border: Border.all(
                              color: _cOrange.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.article_outlined,
                                  size: 12, color: _cOrange),
                              const SizedBox(width: 4),
                              Text(
                                'View Original Post',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _cOrange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _cOrange.withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.full),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bookmark_rounded,
                                size: 10, color: _cOrange),
                            const SizedBox(width: 4),
                            Text(
                              'Created From Post',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _cOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],

                  // ── Feature 3: "View full album in Memory Vault →"
                  // Per the spec: "When a Timeline entry's photo corresponds
                  // to an event that also has additional photos stored in
                  // Memory Vault (e.g., tagged with the same date/event/
                  // category), show a 'View full album in Memory Vault →'
                  // link on that Timeline entry's detail view."
                  //
                  // The caller passes the album size + a callback. We
                  // render the affordance only when there are related
                  // photos (albumPhotoCount > 0) and a callback is wired.
                  if (onViewAlbumInVault != null &&
                      (albumPhotoCount ?? 0) > 0) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: onViewAlbumInVault,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _cOrange.withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.full),
                          border: Border.all(
                            color: _cOrange.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library_rounded,
                                size: 12, color: _cOrange),
                            const SizedBox(width: 4),
                            Text(
                              'View full album in Memory Vault →',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _cOrange,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: _cOrange.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(
                                    KinrelRadius.full),
                              ),
                              child: Text(
                                '+${albumPhotoCount}',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.monoFont,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _cOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: 250.ms)
          .slideY(begin: 0.03, end: 0),
    );
  }

  // ── Cover Section ──────────────────────────────────────────────

  Widget _buildCoverSection(IconData typeIcon, Color typeColor) {
    final hasImage = memory.hasImage;

    if (!hasImage) {
      // Placeholder: memory type icon on a subtle gradient background.
      // NEVER show a blank rectangle.
      return Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(17),
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              typeColor.withValues(alpha: 0.18),
              _cElevated,
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: typeColor.withValues(alpha: 0.18),
              border: Border.all(
                color: typeColor.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Icon(typeIcon, size: 28, color: typeColor),
          ),
        ),
      );
    }

    // Image cover with lazy loading + shimmer + error fallback
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(17),
      ),
      child: CachedNetworkImage(
        imageUrl: memory.displayImageUrl,
        cacheManager: KinrelImageCacheManager.instance,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
        memCacheWidth: 600, // bound decode size for performance
        memCacheHeight: 400,
        placeholder: (context, url) => _buildImageShimmer(),
        errorWidget: (context, url, error) => Container(
          height: 200,
          color: _cElevated,
          child: Center(
            child: Icon(typeIcon, size: 32, color: _cTextDim),
          ),
        ),
      ),
    );
  }

  Widget _buildImageShimmer() {
    return Shimmer.fromColors(
      baseColor: _cElevated,
      highlightColor: _cCard,
      child: Container(
        height: 200,
        width: double.infinity,
        color: _cElevated,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════════════════════

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _cTextDim),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: _cTextDim,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.isPinned, required this.onTap});

  final bool isPinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isPinned
              ? _cOrange.withValues(alpha: 0.15)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          size: 16,
          color: isPinned ? _cOrange : _cTextDim,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Skeleton card for loading state (Feature 3 — skeleton loaders)
// ═══════════════════════════════════════════════════════════════════════

class MemoryTimelineCardSkeleton extends StatelessWidget {
  const MemoryTimelineCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: 6),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Shimmer.fromColors(
        baseColor: _cElevated,
        highlightColor: _cCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Container(
              height: 200,
              width: double.infinity,
              color: _cElevated,
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type chip + pin
                  Row(
                    children: [
                      Container(
                        width: 70,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _cElevated,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: _cElevated,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Title
                  Container(
                    width: double.infinity,
                    height: 18,
                    color: _cElevated,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 200,
                    height: 14,
                    color: _cElevated,
                  ),
                  const SizedBox(height: 12),
                  // Meta row
                  Row(
                    children: [
                      Container(
                        width: 70,
                        height: 12,
                        color: _cElevated,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 80,
                        height: 12,
                        color: _cElevated,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 70,
                        height: 12,
                        color: _cElevated,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
