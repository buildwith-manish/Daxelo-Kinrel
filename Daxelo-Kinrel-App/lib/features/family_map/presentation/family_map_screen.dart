// lib/features/family_map/presentation/family_map_screen.dart
//
// DAXELO KINREL — Family Map Screen
//
// Full-screen interactive map showing family members pinned by city.
// Uses flutter_map with OpenStreetMap tiles (no API key needed).
// Each pin is a 44×44 circular avatar with orange border.
// Tapping a pin opens a bottom sheet with member details.
// Curved connecting lines between related members with tappable
// midpoint dots that show the kinship term between two people.

import 'dart:math' as math;
import 'dart:ui' as ui;
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
import '../providers/graphics_tier_provider.dart';

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
  void initState() {
    super.initState();
    // Start adaptive graphics monitoring — the FPS monitor will
    // auto-downgrade the tier if sustained frame performance is poor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(graphicsTierProvider.notifier).startMonitoring();
    });
  }

  @override
  void dispose() {
    ref.read(graphicsTierProvider.notifier).stopMonitoring();
    super.dispose();
  }

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
                final locatedCount = result.pins.length;
                return Text(
                  '$locatedCount member${locatedCount == 1 ? '' : 's'} located',
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
        actions: [
          // Graphics settings — opens the Auto/High/Balanced/Low picker.
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'Map graphics settings',
            onPressed: () => _showGraphicsSettingsSheet(),
          ),
        ],
      ),
      body: mapAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(
            color: KinrelColors.orange,
            strokeWidth: 3,
          ),
        ),
        error: (error, stack) => _buildErrorState(error),
        // The map is ALWAYS rendered — even with 0 members, 0 cities,
        // or 0 located pins. The map is the feature; pins are layers
        // placed on top. Empty data = empty GeoJSON source = zero pins,
        // NOT zero map. A small non-blocking overlay is shown on top
        // when there are no located members.
        data: (result) => _buildMap(result),
      ),
    );
  }

  // ── Graphics Settings Sheet ────────────────────────────────────────

  void _showGraphicsSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final tierState = ref.watch(graphicsTierProvider);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Map Graphics',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Auto adjusts quality based on performance. Lower tiers improve fps on older devices.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textSilver,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Current tier + FPS indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 16,
                      color: KinrelColors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active: ${_tierLabel(tierState.activeTier)}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const Spacer(),
                    if (tierState.preference == GraphicsTierPreference.auto)
                      Text(
                        '${tierState.currentFps.toStringAsFixed(0)} fps',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textSilver,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Preference options
              _GraphicsOption(
                label: 'Auto',
                subtitle: 'Adapts quality to maintain smooth fps',
                icon: Icons.auto_awesome_rounded,
                isSelected: tierState.preference == GraphicsTierPreference.auto,
                onTap: () {
                  ref.read(graphicsTierProvider.notifier).setPreference(GraphicsTierPreference.auto);
                  ref.read(graphicsTierProvider.notifier).startMonitoring();
                  Navigator.pop(ctx);
                },
              ),
              _GraphicsOption(
                label: 'High',
                subtitle: 'Full glow, premium shadows, animated effects',
                icon: Icons.bolt_rounded,
                isSelected: tierState.preference == GraphicsTierPreference.high,
                onTap: () {
                  ref.read(graphicsTierProvider.notifier).setPreference(GraphicsTierPreference.high);
                  Navigator.pop(ctx);
                },
              ),
              _GraphicsOption(
                label: 'Balanced',
                subtitle: 'Reduced glow, simpler shadows, static lines',
                icon: Icons.balance_rounded,
                isSelected: tierState.preference == GraphicsTierPreference.balanced,
                onTap: () {
                  ref.read(graphicsTierProvider.notifier).setPreference(GraphicsTierPreference.balanced);
                  Navigator.pop(ctx);
                },
              ),
              _GraphicsOption(
                label: 'Low',
                subtitle: 'No effects, flat pins, best for older devices',
                icon: Icons.speed_rounded,
                isSelected: tierState.preference == GraphicsTierPreference.low,
                onTap: () {
                  ref.read(graphicsTierProvider.notifier).setPreference(GraphicsTierPreference.low);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _tierLabel(GraphicsTier tier) {
    switch (tier) {
      case GraphicsTier.high:
        return 'High';
      case GraphicsTier.balanced:
        return 'Balanced';
      case GraphicsTier.low:
        return 'Low';
    }
  }

  // ── Map View ───────────────────────────────────────────────────────

  Widget _buildMap(FamilyMapResult result) {
    // Watch the graphics tier — drives tile URL, glow, shadows, animations.
    final tierState = ref.watch(graphicsTierProvider);
    final tierConfig = tierState.config;

    return Stack(
      children: [
        // ── Permanent map background ───────────────────────────────
        // The map is ALWAYS rendered — even with 0 members, 0 cities,
        // or 0 located pins. Empty data = empty MarkerLayer, NOT no map.
        //
        // Tile URL is tier-aware:
        //   HIGH/BALANCED: CartoDB Dark Matter (already dark, premium look)
        //   LOW: CartoDB Dark Matter no-labels (lighter, faster to load)
        // No darkening filter needed — CartoDB Dark is already dark-themed.
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(20.5937, 78.9629),
            initialZoom: 4.5,
            minZoom: 2.0,
            maxZoom: tierConfig.maxTileZoom.toDouble(),
          ),
          children: [
            TileLayer(
              urlTemplate: tierConfig.tileUrl,
              userAgentPackageName: 'com.daxelo.kinrel',
              // CartoDB Dark Matter is already dark — no darkening filter needed.
              // This gives a cleaner, more premium look than OSM+darken.
              maxZoom: tierConfig.maxTileZoom.toDouble(),
              maxNativeZoom: tierConfig.maxTileZoom.toDouble(),
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

        // ── Non-blocking empty-locations overlay ───────────────────
        // Shown when no members have coordinates. Does NOT replace the
        // map — the map is still fully interactive behind this card.
        // The card is centered but small, so the user can still pan/
        // zoom/rotate the map around it.
        if (result.pins.isEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: KinrelSpacing.base,
            right: KinrelSpacing.base,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_off_outlined,
                        size: 32,
                        color: KinrelColors.orange.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No family locations yet',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Family members will appear here when a location becomes available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textSilver,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── Legend overlay — bottom-left ───────────────────────────
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

  // ── Error State ────────────────────────────────────────────────────
  // Note: The map is always rendered — there is no "no members" or
  // "no cities" full-page empty state. When there are no located
  // members, the map shows with a small non-blocking overlay card.
  // The only full-page replacement state is the error state below.

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

// ═══════════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════════
// GRAPHICS OPTION WIDGET
// ═══════════════════════════════════════════════════════════════════════

class _GraphicsOption extends StatelessWidget {
  const _GraphicsOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelColors.orange.withValues(alpha: 0.12)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? KinrelColors.orange : KinrelColors.textSilver,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? KinrelColors.textWhite : KinrelColors.textSilver,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 20, color: KinrelColors.orange),
          ],
        ),
      ),
    );
  }
}
