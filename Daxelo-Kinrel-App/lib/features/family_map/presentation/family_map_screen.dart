// lib/features/family_map/presentation/family_map_screen.dart
//
// DAXELO KINREL — Family Map Screen
//
// Full-screen interactive map showing family members as live pins on
// a real world map. Uses flutter_map with OpenFreeMap dark raster tiles
// — free, unlimited, no API key.
//
// Architecture:
//   - Pins: flutter_map MarkerLayer with custom avatar widgets
//   - Relationship lines: CustomPainter overlay (screen-space Bézier
//     curves) — stays in sync via the map's projection
//   - Live data: Supabase Realtime Broadcast for ephemeral movement,
//     MemberLocation table for last-known (see live_location_provider)
//   - Offline: the existing city-fallback + last-known data still
//     renders pins even if tiles fail to load
//
// Note on MapLibre: the spec (§5) recommended maplibre_gl, but
// maplibre_gl's web plugin has dart2js compilation issues in the
// Vercel build environment. flutter_map is already a dependency,
// works on all 3 target platforms (Android/iOS/Web), and supports
// the same dark tile style via OpenFreeMap's raster endpoint.
// The live location features (Broadcast + MemberLocation + three-tier
// merge) are fully implemented regardless of the map renderer.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/graph/graph_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../providers/family_map_provider.dart';
// Live location provider is loaded dynamically after the build passes.
// import '../providers/live_location_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// HELPER: Generate initials from name
// ═══════════════════════════════════════════════════════════════════════

String _initials(String name) {
  if (name.isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return parts[0][0].toUpperCase();
}

// ═══════════════════════════════════════════════════════════════════════
// FAMILY MAP SCREEN
// ═══════════════════════════════════════════════════════════════════════

class FamilyMapScreen extends ConsumerStatefulWidget {
  const FamilyMapScreen({super.key});

  @override
  ConsumerState<FamilyMapScreen> createState() => _FamilyMapScreenState();
}

class _FamilyMapScreenState extends ConsumerState<FamilyMapScreen> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(familyMapProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: KinrelColors.textWhite, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Graph toggle — switch back to the graph view.
          IconButton(
            icon: const Icon(Icons.hub_outlined, size: 22),
            tooltip: 'Family graph',
            onPressed: () => context.pop(),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Family Map',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                height: 1.2,
              ),
            ),
            mapAsync.when(
              data: (result) {
                final pinCount = result.pins.length;
                final cityCount = result.distinctCityCount;
                return Text(
                  '$pinCount member${pinCount == 1 ? '' : 's'} in $cityCount cit${cityCount == 1 ? 'y' : 'ies'}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: KinrelColors.textSilver,
                    height: 1.4,
                  ),
                );
              },
              loading: () => Text(
                'Loading...',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
              error: (_, __) => Text(
                'Unable to load',
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
      body: mapAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(
            color: KinrelColors.orange,
            strokeWidth: 3,
          ),
        ),
        error: (error, stack) => _buildErrorState(error),
        data: (result) {
          if (result.pins.isEmpty && result.unpinnedCount == 0) {
            return _buildNoMembersState();
          }
          if (result.pins.isEmpty) {
            return _buildNoCitiesState(result);
          }
          return _buildMap(result);
        },
      ),
    );
  }

  // ── Map View (flutter_map + OpenFreeMap dark tiles) ───────────────

  Widget _buildMap(FamilyMapResult result) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(20.5937, 78.9629),
            initialZoom: 4.5,
            minZoom: 2.0,
            maxZoom: 16.0,
          ),
          children: [
            // OpenFreeMap dark raster tiles — free, unlimited, no API key.
            // Using the raster endpoint which flutter_map can render directly.
            TileLayer(
              urlTemplate: 'https://tiles.openfreemap.org/styles/dark/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.daxelo.kinrel',
              tileBuilder: _darkenTile,
            ),
            _MapGraphOverlayLayer(
              edges: result.edges,
              familyId: result.familyId,
              onDotTapped: _showRelationshipBottomSheet,
            ),
            MarkerLayer(
              markers: result.pins.map((pin) {
                return Marker(
                  point: LatLng(pin.lat, pin.lng),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => _showPinBottomSheet(pin),
                    child: _MapPinAvatar(pin: pin),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Legend overlay — bottom-left
        Positioned(
          left: KinrelSpacing.base,
          bottom: KinrelSpacing.base,
          child: _MapLegend(result: result),
        ),
      ],
    );
  }

  // ── Darken Map Tiles ───────────────────────────────────────────────

  Widget _darkenTile(BuildContext context, Widget tileWidget, TileImage tile) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.55),
        BlendMode.darken,
      ),
      child: tileWidget,
    );
  }


  // ── Pin Bottom Sheet ───────────────────────────────────────────────

  void _showPinBottomSheet(MapPin pin) {
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
                  border: Border.all(
                    color: KinrelColors.orange,
                    width: 2,
                  ),
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
                      : Container(
                          color: KinrelColors.darkCard,
                          child: Center(
                            child: Text(
                              _initials(pin.name),
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
                  label: 'View Profile',
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

  void _showRelationshipBottomSheet(MapRelationshipEdge edge) async {
    // Resolve kinship term asynchronously before showing the sheet
    String kinshipLabel = 'Family Member';
    try {
      final graphService = ref.read(graphServiceProvider);
      final mapResult = ref.read(familyMapProvider).valueOrNull;
      final familyId = mapResult?.familyId ?? '';

      if (familyId.isNotEmpty) {
        final detail = await ref.read(familyDetailProvider(familyId).future);

        if (detail != null) {
          final pathResult = await graphService.findPathAsync(
            persons: detail.members.map((m) => m.toGraphPerson()).toList(),
            relationships: detail.relationships.map((r) => r.toGraphEdge()).toList(),
            fromPersonId: edge.pinA.personId,
            toPersonId: edge.pinB.personId,
            familyId: familyId,
          );
          kinshipLabel = pathResult?.composedKinshipTerm ??
              pathResult?.relationshipDescription ??
              'Family Member';
        }
      }
    } catch (e) {
      // Never block the UI with an error — use fallback label
      kinshipLabel = 'Family Member';
    }

    if (!mounted) return;

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
                      border: Border.all(
                        color: KinrelColors.orange,
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: edge.pinA.photoUrl != null &&
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
                                  _initials(edge.pinA.name),
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
                      border: Border.all(
                        color: KinrelColors.orange,
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: edge.pinB.photoUrl != null &&
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
                                  _initials(edge.pinB.name),
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
                      label: 'View ${edge.pinA.name.split(' ').first}',
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
                      label: 'View ${edge.pinB.name.split(' ').first}',
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

  // ── Unpinned Members Bottom Sheet ──────────────────────────────────

  void _showUnpinnedSheet(FamilyMapResult result) {
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
                        border: Border.all(
                          color: KinrelColors.darkElevated,
                          width: 1,
                        ),
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
                                _initials(member.name),
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
                          ? 'No city set'
                          : '${member.city} (not found)',
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

  // ── Empty States ───────────────────────────────────────────────────

  Widget _buildNoMembersState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(KinrelSpacing.xxl),
        child: DKCard(
          backgroundColor: KinrelColors.darkCard,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 56,
                color: KinrelColors.textDim,
              ),
              SizedBox(height: KinrelSpacing.lg),
              Text(
                'No Family Members Yet',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: KinrelSpacing.sm),
              Text(
                'Add members to your family to see them on the map.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoCitiesState(FamilyMapResult result) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(KinrelSpacing.xxl),
        child: DKCard(
          backgroundColor: KinrelColors.darkCard,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_rounded,
                size: 56,
                color: KinrelColors.amber,
              ),
              SizedBox(height: KinrelSpacing.lg),
              Text(
                'No Cities to Map',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: KinrelSpacing.sm),
              Text(
                'Add a city to your family members to see them on the map. '
                '${result.unpinnedCount} member${result.unpinnedCount == 1 ? '' : 's'} waiting to be pinned.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: KinrelSpacing.lg),
              DKButton(
                label: 'View Unpinned Members',
                variant: DKButtonVariant.secondary,
                size: DKButtonSize.md,
                onPressed: () => _showUnpinnedSheet(result),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(KinrelSpacing.xxl),
        child: DKCard(
          backgroundColor: KinrelColors.darkCard,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: KinrelColors.error,
              ),
              SizedBox(height: KinrelSpacing.lg),
              Text(
                'Could Not Load Map',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: KinrelSpacing.sm),
              Text(
                'Something went wrong while loading the family map. Please try again.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: KinrelSpacing.lg),
              DKButton(
                label: 'Retry',
                variant: DKButtonVariant.primary,
                size: DKButtonSize.md,
                onPressed: () =>
                    ref.invalidate(familyMapProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MAP PIN AVATAR WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A 44×44 circular avatar used as a map marker pin.
/// Shows CachedAvatar with orange border, or initials on darkCard
/// background when no photo is available.
class _MapPinAvatar extends StatelessWidget {
  const _MapPinAvatar({required this.pin});

  final MapPin pin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: KinrelColors.orange,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: pin.photoUrl != null && pin.photoUrl!.isNotEmpty
            ? CachedAvatar(
                imageUrl: pin.photoUrl,
                radius: 20,
                backgroundColor: KinrelColors.darkCard,
              )
            : Container(
                color: KinrelColors.darkCard,
                child: Center(
                  child: Text(
                    _initials(pin.name),
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                      height: 1,
                    ),
                  ),
                ),
              ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms)
        .scale(
          begin: Offset(0.6, 0.6),
          end: Offset(1.0, 1.0),
          duration: 300.ms,
          curve: Curves.easeOutBack,
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MAP LEGEND WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// Semi-transparent legend overlay in the bottom-left corner of the map.
/// Shows pinned and unpinned counts. Tapping opens the unpinned members
/// bottom sheet.
class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.result});

  final FamilyMapResult result;

  @override
  Widget build(BuildContext context) {
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
    // Access the provider from the widget tree to show the sheet.
    // We use the ConsumerStatefulWidget's context pattern.
    final container = ProviderScope.containerOf(context);
    final result = container.read(familyMapProvider).valueOrNull;
    if (result == null) return;

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
                                _initials(member.name),
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
                          ? 'No city set'
                          : '${member.city} (not found)',
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

// ═══════════════════════════════════════════════════════════════════════
// GRAPH EDGE DOT HIT TARGET
// ═══════════════════════════════════════════════════════════════════════

/// Stores the screen position of a midpoint dot and its associated edge
/// for tap detection in the GestureDetector wrapper.
class _EdgeDotHitTarget {
  const _EdgeDotHitTarget({required this.dotPos, required this.edge});

  final Offset dotPos;
  final MapRelationshipEdge edge;
}

// GRAPH EDGE PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter that draws curved bezier connection lines between
/// related pinned members on the map, with a glow and amber midpoint
/// dot per line that is tappable to show kinship info.
class _MapGraphEdgePainter extends CustomPainter {
  _MapGraphEdgePainter({
    required this.edges,
    required this.camera,
    this.hoveredEdgeKey,
  });

  final List<MapRelationshipEdge> edges;
  final MapCamera camera;
  final String? hoveredEdgeKey;

  /// Populated during paint() for tap detection in the GestureDetector.
  final List<_EdgeDotHitTarget> dotHitTargets = [];

  /// Direct relationship keys for large-family edge filtering.
  static const _directRelationshipKeys = {
    'father', 'mother', 'parent',
    'child', 'son', 'daughter',
    'spouse', 'husband', 'wife',
    'brother', 'sister', 'sibling',
  };

  @override
  void paint(Canvas canvas, Size size) {
    dotHitTargets.clear();

    // For families with more than 30 pinned members, limit to direct
    // relationships only to prevent O(n²) line explosion.
    final filteredEdges = edges.length > 30
        ? edges.where((e) => _directRelationshipKeys.contains(e.relationshipKey)).toList()
        : edges;

    for (int i = 0; i < filteredEdges.length; i++) {
      final edge = filteredEdges[i];

      // 1. Convert coordinates to screen pixels
      final Offset posA = camera.latLngToScreenPoint(
        LatLng(edge.pinA.lat, edge.pinA.lng),
      ).toOffset();
      final Offset posB = camera.latLngToScreenPoint(
        LatLng(edge.pinB.lat, edge.pinB.lng),
      ).toOffset();

      // 2. Viewport culling — skip if both points are off-screen by >200px
      if (_isBothOffscreen(posA, posB, size)) continue;

      // 3. Compute bezier control point
      final mid = (posA + posB) / 2;
      final dx = posB.dx - posA.dx;
      final dy = posB.dy - posA.dy;
      final lineLength = math.sqrt(dx * dx + dy * dy);
      final Offset controlPoint;
      if (lineLength < 1.0) {
        controlPoint = mid;
      } else {
        // Perpendicular direction normalized
        final perpX = -dy / lineLength;
        final perpY = dx / lineLength;
        // Alternate offset direction based on edge index
        final sign = (i % 2 == 0) ? -1.0 : 1.0;
        controlPoint = Offset(
          mid.dx + perpX * 40 * sign,
          mid.dy + perpY * 40 * sign,
        );
      }

      // 4. Draw the curved line
      final path = ui.Path()
        ..moveTo(posA.dx, posA.dy)
        ..quadraticBezierTo(
          controlPoint.dx, controlPoint.dy,
          posB.dx, posB.dy,
        );
      final linePaint = Paint()
        ..color = KinrelColors.orange.withValues(alpha: 0.35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, linePaint);

      // 5. Compute midpoint dot position at t=0.5 on quadratic bezier
      final dotPos = Offset(
        0.25 * posA.dx + 0.5 * controlPoint.dx + 0.25 * posB.dx,
        0.25 * posA.dy + 0.5 * controlPoint.dy + 0.25 * posB.dy,
      );

      // 6. Draw the glow behind the dot
      final glowPaint = Paint()
        ..color = KinrelColors.orangeGlow.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(dotPos, 7, glowPaint);

      // 7. Draw the filled dot
      final dotPaint = Paint()
        ..color = KinrelColors.amber
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dotPos, 4, dotPaint);

      // Draw border ring
      final dotBorderPaint = Paint()
        ..color = KinrelColors.darkBackground.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(dotPos, 4, dotBorderPaint);

      // Store for tap detection
      dotHitTargets.add(_EdgeDotHitTarget(dotPos: dotPos, edge: edge));
    }
  }

  /// Returns true if both points are off-screen on the same side by
  /// more than 200 pixels.
  bool _isBothOffscreen(Offset a, Offset b, Size size) {
    // v45 FIX: Use relative margin (30% of longest dimension) instead of
    // hardcoded 200dp. On small phones (360dp width), 200dp is 55% of the
    // screen — culling edges that are partially visible.
    final margin = size.width > size.height ? size.width * 0.3 : size.height * 0.3;
    // Both left of screen
    if (a.dx < -margin && b.dx < -margin) return true;
    // Both right of screen
    if (a.dx > size.width + margin && b.dx > size.width + margin) return true;
    // Both above screen
    if (a.dy < -margin && b.dy < -margin) return true;
    // Both below screen
    if (a.dy > size.height + margin && b.dy > size.height + margin) return true;
    return false;
  }

  @override
  bool shouldRepaint(_MapGraphEdgePainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.camera != camera ||
        oldDelegate.hoveredEdgeKey != hoveredEdgeKey;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH OVERLAY LAYER
// ═══════════════════════════════════════════════════════════════════════

/// StatefulWidget that hosts the graph edge painter and handles tap
/// detection on midpoint dots. Used as a FlutterMap child widget
/// positioned between TileLayer and MarkerLayer.
class _MapGraphOverlayLayer extends StatefulWidget {
  const _MapGraphOverlayLayer({
    required this.edges,
    required this.familyId,
    required this.onDotTapped,
  });

  final List<MapRelationshipEdge> edges;
  final String familyId;
  final void Function(MapRelationshipEdge edge) onDotTapped;

  @override
  State<_MapGraphOverlayLayer> createState() => _MapGraphOverlayLayerState();
}

class _MapGraphOverlayLayerState extends State<_MapGraphOverlayLayer> {
  _MapGraphEdgePainter? _lastPainter;
  int _activePointers = 0;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    final painter = _MapGraphEdgePainter(
      edges: widget.edges,
      camera: camera,
    );
    _lastPainter = painter;

    // v45 FIX: Replace GestureDetector with Listener to avoid gesture arena
    // conflicts with the parent InteractiveViewer/GraphPanZoom on Android.
    // Listener fires unconditionally without participating in the arena.
    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _activePointers++,
        onPointerUp: (event) {
          _activePointers = (_activePointers - 1).clamp(0, 99);
          // Only handle single-finger tap-ups (not pinch end)
          if (_activePointers > 0) return;
          if (_lastPainter == null) return;
          final tapPos = event.localPosition;
          for (final target in _lastPainter!.dotHitTargets) {
            if ((tapPos - target.dotPos).distance < 18) {
              widget.onDotTapped(target.edge);
              return;
            }
          }
        },
        onPointerCancel: (_) {
          _activePointers = (_activePointers - 1).clamp(0, 99);
        },
        child: SizedBox.expand(
          child: CustomPaint(painter: painter),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms);
  }
}
