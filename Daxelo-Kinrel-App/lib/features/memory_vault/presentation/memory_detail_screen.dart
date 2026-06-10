// lib/features/memory_vault/presentation/memory_detail_screen.dart
//
// DAXELO KINREL — Memory Detail Screen
//
// Full-screen viewer for a single memory photo.
// Hero animation on the photo, caption below, uploader info,
// tagged member avatar chips, and share action.
//
// Orange K-Graph DNA: #131416 bg, #191B2C cards, #E8612A accent.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../core/family/family_provider.dart';
import '../data/memory_model.dart';

// ═══════════════════════════════════════════════════════════════════════
// Memory Detail Screen
// ═══════════════════════════════════════════════════════════════════════

class MemoryDetailScreen extends ConsumerWidget {
  const MemoryDetailScreen({
    super.key,
    required this.memory,
  });

  final MemoryModel memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero photo
            _buildPhoto(context),

            // Details section
            Padding(
              padding: EdgeInsets.all(KinrelSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Caption
                  if (memory.caption != null &&
                      memory.caption!.isNotEmpty) ...[
                    _buildCaption(),
                    SizedBox(height: KinrelSpacing.md),
                  ],

                  // Date + Uploader
                  _buildMetaInfo(),
                  SizedBox(height: KinrelSpacing.lg),

                  // Tagged members
                  _buildTaggedMembers(ref),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // App Bar — transparent, overlaid on image
  // ═══════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.share_rounded,
                color: Colors.white, size: 20),
            onPressed: () {
              ShareHelper.shareProfile(
                memberId: memory.id,
                memberName: memory.caption ?? 'Family Memory',
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Hero Photo
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildPhoto(BuildContext context) {
    return Hero(
      tag: 'memory_${memory.id}',
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        child: CachedNetworkImage(
          imageUrl: memory.photoUrl,
          cacheManager: KinrelImageCacheManager.instance,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: MediaQuery.of(context).size.height * 0.55,
            color: KinrelColors.darkCard,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(KinrelColors.orange),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            height: 300,
            color: KinrelColors.darkCard,
            child: const Center(
              child: Icon(
                Icons.broken_image_rounded,
                color: KinrelColors.textDim,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Caption
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCaption() {
    return Text(
      memory.caption!,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: KinrelColors.textWhite,
        height: 1.5,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Meta Info (Date + Uploader)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildMetaInfo() {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: const Color(0xFF3A3A4A),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Date row
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                memory.formattedDate,
                style: KinrelTypography.labelMedium.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
              if (memory.yearsAgo != null && memory.yearsAgo! > 0) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.igniteGradient,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                  ),
                  child: Text(
                    '${memory.yearsAgo} ${memory.yearsAgo == 1 ? 'year' : 'years'} ago',
                    style: KinrelTypography.micro.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Divider
          const Divider(color: Color(0xFF2A2A3D), height: 1),

          const SizedBox(height: 10),

          // Uploader row
          Row(
            children: [
              CachedAvatar(
                radius: 16,
                backgroundColor:
                    KinrelColors.orange.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Uploaded by',
                      style: KinrelTypography.labelSmall.copyWith(
                        color: KinrelColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      memory.uploaderName.isNotEmpty
                          ? memory.uploaderName
                          : 'Unknown',
                      style: KinrelTypography.labelMedium.copyWith(
                        color: KinrelColors.textWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Tagged Members — Small circular avatar chips with names
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTaggedMembers(WidgetRef ref) {
    if (memory.taggedPersonIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.people_rounded,
              size: 16,
              color: KinrelColors.orange,
            ),
            const SizedBox(width: 6),
            Text(
              'Tagged in this photo',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Avatar chips — resolve names from family members
        Consumer(
          builder: (context, ref, _) {
            final familiesAsync = ref.watch(familyListProvider);
            final families = familiesAsync.valueOrNull;
            if (families == null || families.isEmpty) {
              return _buildTaggedIdChips(memory.taggedPersonIds);
            }

            final familyId = families.first.id;
            final membersAsync = ref.watch(familyMembersProvider(familyId));
            final members = membersAsync.valueOrNull ?? [];

            // Build a map of member IDs to names + photoUrls
            final memberMap = <String, ({String name, String? photoUrl})>{};
            for (final m in members) {
              memberMap[m.id] = (name: m.name, photoUrl: m.photoUrl);
            }

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: memory.taggedPersonIds.map((id) {
                final member = memberMap[id];
                final name = member?.name ?? 'Unknown';
                final photoUrl = member?.photoUrl;
                final initials = name
                    .split(' ')
                    .where((s) => s.isNotEmpty)
                    .take(2)
                    .map((s) => s[0].toUpperCase())
                    .join();

                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                    border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InitialsAvatar(
                        imageUrl: photoUrl,
                        initials: initials,
                        radius: 12,
                        backgroundColor:
                            KinrelColors.orange.withValues(alpha: 0.2),
                        foregroundColor: KinrelColors.orange,
                        fontSize: 10,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          style: KinrelTypography.labelSmall.copyWith(
                            color: KinrelColors.textWhite,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  /// Fallback: show ID chips when family members can't be resolved.
  Widget _buildTaggedIdChips(List<String> ids) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ids.map((id) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            border: Border.all(
              color: const Color(0xFF3A3A4A),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CachedAvatar(
                radius: 10,
                backgroundColor: KinrelColors.orange.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 6),
              Text(
                id.substring(0, id.length > 8 ? 8 : id.length),
                style: KinrelTypography.labelSmall.copyWith(
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
