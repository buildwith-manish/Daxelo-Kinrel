// lib/features/family_map/widgets/map_bottom_sheets.dart
//
// DAXELO KINREL — Map Bottom Sheets helper.
//
// Static helpers that build the various bottom sheets shown from the
// Family Map screen:
//   • [showPinBottomSheet]              — pin tap
//   • [showRelationshipBottomSheet]     — relationship edge tap
//   • [showFamilyBuildingBottomSheet]   — family building tap
//   • [showHouseholdBottomSheet]        — household cluster tap
//   • [showUnpinnedSheet]               — unpinned members list
//
// Extracted from `family_map_screen.dart` (originally the private
// `_showXxxBottomSheet` methods on `_FamilyMapScreenState`) as part
// of the file decomposition. Each method is now a public static
// function on the [MapBottomSheets] class.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/place_models.dart';
import '../providers/family_map_provider.dart';
import 'family_building_layer.dart' show FamilyBuildingBottomSheet;
import 'map_initials.dart';
// P12.7 — Kinrel Cameo fallback avatar
import '../../../core/constants/feature_flags.dart';
import '../../cameo/cameo.dart';

/// Static helpers that build the bottom sheets shown from the Family
/// Map screen.
///
/// Each method takes the [BuildContext] (and any extra data needed
/// to populate the sheet) and calls `showModalBottomSheet` directly.
/// Callbacks (e.g. [showHouseholdBottomSheet]'s `onMemberTap`) are
/// forwarded to the caller so the screen can keep its gesture
/// handling in one place.
class MapBottomSheets {
  MapBottomSheets._();

  // ── Pin Bottom Sheet ───────────────────────────────────────────────

  /// Shows the family member pin bottom sheet (avatar, name, city,
  /// "View Profile" button).
  static void showPinBottomSheet(BuildContext context, MapPin pin) {
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
        child: Padding(
          padding: EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: KinrelSpacing.lg),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: KinrelColors.orange, width: 2),
                ),
                child: ClipOval(
                  child: pin.photoUrl != null && pin.photoUrl!.isNotEmpty
                      ? CachedAvatar(
                          imageUrl: pin.photoUrl,
                          radius: 38,
                          border: Border.all(
                            color: KinrelColors.orange,
                            width: 2,
                          ),
                        )
                      : kEnableCameoFallback
                      ? ClipOval(
                          child: CameoAvatar(
                            personName: pin.name,
                            ageBand: CameoAgeBand.adult,
                            skinToneIndex: 5,
                            surfaceId: 'map_marker',
                            isDeceased: false,
                          ),
                        )
                      : Container(
                          color: KinrelColors.darkCard,
                          child: Center(
                            child: Text(
                              initials(pin.name),
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.orange,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                ),
              ),

              SizedBox(height: KinrelSpacing.md),

              // Name
              Text(
                pin.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: KinrelSpacing.xs),

              // City with pin icon
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 16,
                    color: KinrelColors.amber,
                  ),
                  SizedBox(width: KinrelSpacing.xs),
                  Flexible(
                    child: Text(
                      pin.city,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: KinrelColors.amber,
                        height: 1.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              SizedBox(height: KinrelSpacing.xl),

              // View Profile button
              SizedBox(
                width: double.infinity,
                child: DKButton(
                  label: l10n?.familyMapViewProfile ?? 'View Profile',
                  variant: DKButtonVariant.primary,
                  size: DKButtonSize.md,
                  fullWidth: true,
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/member/${pin.personId}');
                  },
                ),
              ),

              SizedBox(height: KinrelSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  // ── Relationship Bottom Sheet ──────────────────────────────────────

  /// Shows the relationship bottom sheet for a [MapRelationshipEdge].
  ///
  /// Resolves the kinship term asynchronously (via the
  /// [graphServiceProvider] + [familyDetailProvider]) before showing
  /// the sheet. Falls back to "Family Member" on any error so the UI
  /// is never blocked.
  static Future<void> showRelationshipBottomSheet(
    BuildContext context,
    WidgetRef ref,
    String familyId,
    MapRelationshipEdge edge,
  ) async {
    // Capture l10n before the async gap so we don't use BuildContext
    // across it.
    final l10n = S.of(context);
    final fallbackLabel = l10n?.familyMapFamilyMember ?? 'Family Member';
    // Resolve kinship term asynchronously before showing the sheet
    String kinshipLabel = fallbackLabel;
    try {
      final graphService = ref.read(graphServiceProvider);
      final mapResult = ref.read(familyMapProvider(familyId)).valueOrNull;
      final resolvedFamilyId = mapResult?.familyId ?? familyId;

      if (resolvedFamilyId.isNotEmpty) {
        final detail = await ref.read(
          familyDetailProvider(resolvedFamilyId).future,
        );

        if (detail != null) {
          final pathResult = await graphService.findPathAsync(
            persons: detail.members.map((m) => m.toGraphPerson()).toList(),
            relationships: detail.relationships
                .map((r) => r.toGraphEdge())
                .toList(),
            fromPersonId: edge.pinA.personId,
            toPersonId: edge.pinB.personId,
            familyId: resolvedFamilyId,
          );
          kinshipLabel =
              pathResult?.composedKinshipTerm ??
              pathResult?.relationshipDescription ??
              fallbackLabel;
        }
      }
    } catch (e) {
      // Never block the UI with an error — use fallback label
      kinshipLabel = fallbackLabel;
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: KinrelSpacing.lg),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Avatars row with connection line and heart
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left avatar — pinA (48×48)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: KinrelColors.orange, width: 2),
                    ),
                    child: ClipOval(
                      child:
                          edge.pinA.photoUrl != null &&
                              edge.pinA.photoUrl!.isNotEmpty
                          ? CachedAvatar(
                              imageUrl: edge.pinA.photoUrl,
                              radius: 22,
                              backgroundColor: KinrelColors.darkCard,
                            )
                          : Container(
                              color: KinrelColors.darkCard,
                              child: Center(
                                child: Text(
                                  initials(edge.pinA.name),
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.displayFont,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: KinrelColors.orange,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),

                  // Connection line with heart overlay
                  SizedBox(
                    width: 48,
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Horizontal line
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 11.25,
                          child: Container(
                            height: 1.5,
                            color: KinrelColors.amber,
                          ),
                        ),
                        // Heart icon at center
                        Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: KinrelColors.amber,
                        ),
                      ],
                    ),
                  ),

                  // Right avatar — pinB (48×48)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: KinrelColors.orange, width: 2),
                    ),
                    child: ClipOval(
                      child:
                          edge.pinB.photoUrl != null &&
                              edge.pinB.photoUrl!.isNotEmpty
                          ? CachedAvatar(
                              imageUrl: edge.pinB.photoUrl,
                              radius: 22,
                              backgroundColor: KinrelColors.darkCard,
                            )
                          : Container(
                              color: KinrelColors.darkCard,
                              child: Center(
                                child: Text(
                                  initials(edge.pinB.name),
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.displayFont,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: KinrelColors.orange,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: KinrelSpacing.md),

              // Names row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      edge.pinA.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
                    child: Text(
                      '&',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      edge.pinB.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ],
              ),

              SizedBox(height: KinrelSpacing.sm),

              // Kinship label pill
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  kinshipLabel,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.orange,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              SizedBox(height: KinrelSpacing.xl),

              // View Profile buttons
              Row(
                children: [
                  Expanded(
                    child: DKButton(
                      label:
                          l10n?.familyMapViewMember(
                            edge.pinA.name.split(' ').first,
                          ) ??
                          'View ${edge.pinA.name.split(' ').first}',
                      variant: DKButtonVariant.secondary,
                      size: DKButtonSize.md,
                      fullWidth: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/member/${edge.pinA.personId}');
                      },
                    ),
                  ),
                  SizedBox(width: KinrelSpacing.sm),
                  Expanded(
                    child: DKButton(
                      label:
                          l10n?.familyMapViewMember(
                            edge.pinB.name.split(' ').first,
                          ) ??
                          'View ${edge.pinB.name.split(' ').first}',
                      variant: DKButtonVariant.primary,
                      size: DKButtonSize.md,
                      fullWidth: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/member/${edge.pinB.personId}');
                      },
                    ),
                  ),
                ],
              ),

              SizedBox(height: KinrelSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  // ── Family Building Bottom Sheet ───────────────────────────────────

  /// Shows the family building bottom sheet (reuses the
  /// [FamilyBuildingBottomSheet] widget from `family_building_layer.dart`).
  static void showFamilyBuildingBottomSheet(
    BuildContext context,
    FamilyPlace place,
    String? linkedPersonName,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (context) => FamilyBuildingBottomSheet(
        place: place,
        linkedPersonName: linkedPersonName,
      ),
    );
  }

  // ── Household Bottom Sheet ─────────────────────────────────────────

  /// Shows the household members bottom sheet. [onMemberTap] is
  /// invoked (after popping the sheet) when the user taps a member
  /// row — typically the screen's pin-tap handler.
  static void showHouseholdBottomSheet(
    BuildContext context,
    Household household,
    void Function(MapPin) onMemberTap,
  ) {
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.familyMapHouseholdMembers(household.size) ??
                    'Household — ${household.size} members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 12),
              ...household.members.map(
                (pin) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: KinrelColors.darkElevated,
                    child: Text(
                      initials(pin.name),
                      style: TextStyle(color: KinrelColors.orange),
                    ),
                  ),
                  title: Text(
                    pin.name,
                    style: TextStyle(color: KinrelColors.textWhite),
                  ),
                  subtitle: Text(
                    pin.city,
                    style: TextStyle(color: KinrelColors.textSilver),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    onMemberTap(pin);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Unpinned Members Bottom Sheet ──────────────────────────────────

  /// Shows the unpinned members list (members whose city could not be
  /// resolved to coordinates).
  static void showUnpinnedSheet(BuildContext context, FamilyMapResult result) {
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
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: EdgeInsets.only(bottom: KinrelSpacing.lg),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Title
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
                          l10n?.familyMapUnpinnedCount(result.unpinnedCount) ??
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

            // List of unpinned members
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: result.unpinnedMembers.length,
                separatorBuilder: (_, __) =>
                    Divider(color: KinrelColors.darkElevated, height: 1),
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
                        border: Border.all(
                          color: KinrelColors.darkElevated,
                          width: 1,
                        ),
                      ),
                      child:
                          member.photoUrl != null && member.photoUrl!.isNotEmpty
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
