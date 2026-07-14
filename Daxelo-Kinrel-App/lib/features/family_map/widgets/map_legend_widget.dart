// lib/features/family_map/widgets/map_legend_widget.dart
//
// DAXELO KINREL — Map Legend Widget.
//
// Semi-transparent legend overlay in the bottom-left corner of the
// map. Shows pinned and unpinned counts. Tapping opens the unpinned
// members bottom sheet.
//
// Extracted from `family_map_screen.dart` (originally the private
// `_MapLegend` widget) as part of the file decomposition. The public
// class is named [MapLegendWidget].

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/family_map_provider.dart';
import 'map_initials.dart';

/// Semi-transparent legend overlay in the bottom-left corner of the
/// map. Shows pinned and unpinned counts. Tapping opens the unpinned
/// members bottom sheet.
class MapLegendWidget extends StatelessWidget {
  const MapLegendWidget({super.key, required this.result});

  final FamilyMapResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return GestureDetector(
      onTap: result.unpinnedCount > 0
          ? () => _showUnpinnedSheetFromLegend(context)
          : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md,
          vertical: KinrelSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: KinrelColors.darkElevated,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pinned count
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange,
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.orangeGlow,
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: KinrelSpacing.sm),
                Text(
                  l10n?.familyMapPinned(result.pins.length) ??
                      '${result.pins.length} pinned',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ],
            ),

            // Unpinned count (only if there are unpinned members)
            if (result.unpinnedCount > 0) ...[
              SizedBox(height: KinrelSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkElevated,
                      border: Border.all(
                        color: KinrelColors.textDim,
                        width: 1,
                      ),
                    ),
                  ),
                  SizedBox(width: KinrelSpacing.sm),
                  Text(
                    l10n?.familyMapNotPinned(result.unpinnedCount) ??
                        '${result.unpinnedCount} not pinned',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: KinrelColors.textDim,
                    ),
                  ),
                  SizedBox(width: KinrelSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: KinrelColors.textDim,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 500.ms, delay: 300.ms)
        .slideY(begin: 0.2, end: 0, duration: 400.ms);
  }

  void _showUnpinnedSheetFromLegend(BuildContext context) {
    // MapLegendWidget is rebuilt whenever the parent's familyMapProvider
    // emits a new result, so [result] is already the freshest value —
    // no need to re-read the (now family-scoped) provider here.
    // [FamilyMapResult.familyId] is preserved on the field for any
    // downstream sheet consumer that needs it.
    if (result.unpinnedCount == 0) return;
    final l10n = S.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(KinrelSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: EdgeInsets.only(bottom: KinrelSpacing.lg),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.location_off_rounded,
                        size: 20,
                        color: KinrelColors.textDim,
                      ),
                      SizedBox(width: KinrelSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n?.familyMapUnpinnedCount(
                                  result.unpinnedCount) ??
                              '${result.unpinnedCount} member${result.unpinnedCount == 1 ? '' : 's'} without map pin',
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
                  SizedBox(height: KinrelSpacing.sm),
                  Text(
                    l10n?.familyMapAddCityPrompt ??
                        'Add a city to these members to see them on the map.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.xl,
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: result.unpinnedMembers.length,
                separatorBuilder: (_, __) => Divider(
                  color: KinrelColors.darkElevated,
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final member = result.unpinnedMembers[index];
                  return ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: KinrelSpacing.xs,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KinrelColors.darkElevated,
                      ),
                      child: member.photoUrl != null &&
                              member.photoUrl!.isNotEmpty
                          ? ClipOval(
                              child: CachedAvatar(
                                imageUrl: member.photoUrl,
                                radius: 17,
                              ),
                            )
                          : Center(
                              child: Text(
                                initials(member.name),
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: KinrelColors.textSilver,
                                  height: 1,
                                ),
                              ),
                            ),
                    ),
                    title: Text(
                      member.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    subtitle: Text(
                      member.city.isEmpty
                          ? (l10n?.familyMapNoCitySet ?? 'No city set')
                          : (l10n?.familyMapCityNotFound(member.city) ??
                              '${member.city} (not found)'),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: KinrelColors.textDim,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/member/${member.personId}');
                    },
                  );
                },
              ),
            ),
            SizedBox(height: KinrelSpacing.xl),
          ],
        ),
      ),
    );
  }
}
