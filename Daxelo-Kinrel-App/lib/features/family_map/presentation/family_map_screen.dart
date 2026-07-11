// lib/features/family_map/presentation/family_map_screen.dart
//
// DAXELO KINREL — Family Map Screen (MapLibre 0.3.5 — 3D Buildings)
//
// Full-screen interactive map using the modern maplibre package (0.3.5)
// with OpenFreeMap dark vector tiles. Features:
//   - Native 3D building extrusion at street-level zoom (15+)
//   - Tilted camera support (45° pitch for 3D perspective)
//   - Dark premium style matching Kinrel's art direction
//   - Family member pins as GeoJSON source + circle layers
//   - Map is ALWAYS rendered — empty data = empty pins, NOT no map
//
// Package: maplibre ^0.3.5 (modern rewrite, FFI/JNI native)
//   API verified from installed package source:
//     - MapLibreMap(options: MapOptions(...), onMapCreated, onStyleLoaded)
//     - MapOptions(initStyle, initCenter: Geographic(lon, lat), initZoom, initPitch)
//     - MapController.animateCamera(center, zoom, pitch)
//     - StyleController.addSource(GeoJsonSource(id, data))
//     - StyleController.addLayer(FillExtrusionStyleLayer(id, sourceId, paint, sourceLayerId))
//     - StyleController.addLayer(CircleStyleLayer(id, sourceId, paint))
//     - MapController.featuresAtPoint(Offset, layerIds: [...])
//   Web: requires MapLibre GL JS ^5.0 in index.html (per package docs)
// Style: https://tiles.openfreemap.org/styles/dark (free, no API key)

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../providers/family_map_provider.dart';
import '../providers/live_location_provider.dart';

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
  MapController? _mapController;
  bool _styleLoaded = false;
  bool _buildingsAdded = false;
  FamilyMapResult? _lastResult;
  Timer? _broadcastTimer;
  Timer? _dbUpsertTimer;
  DateTime? _lastDbUpsert;

  /// OpenFreeMap dark vector style — free, unlimited, no API key.
  /// Already dark-themed with building height data for 3D extrusion.
  static const _kStyleUrl = 'https://tiles.openfreemap.org/styles/dark';

  @override
  void initState() {
    super.initState();
    // Start the live location provider when the map screen mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final familyId = ref.read(familyListProvider).valueOrNull?.first.id;
      if (familyId != null) {
        ref.read(liveLocationProvider.notifier).start(familyId);
      }
    });
  }

  @override
  void dispose() {
    _stopBroadcastLoop();
    ref.read(liveLocationProvider.notifier).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(familyMapProvider);

    // Watch live location state — start/stop the broadcast loop based
    // on the current user's sharing preference.
    final liveState = ref.watch(liveLocationProvider);
    if (liveState.isSharing && _broadcastTimer == null) {
      _startBroadcastLoop();
    } else if (!liveState.isSharing && _broadcastTimer != null) {
      _stopBroadcastLoop();
    }

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
          // Dev test: fly to Bengaluru at zoom 16, tilt 45° to verify 3D buildings.
          IconButton(
            icon: const Icon(Icons.location_city, size: 20),
            tooltip: 'Test 3D: Bengaluru',
            onPressed: _flyToBengaluru3D,
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

  // ── Map View ───────────────────────────────────────────────────────
  // ── Map View (MapLibre Native — 3D buildings + tilted camera) ──────

  // ── Map View (MapLibre 0.3.5 — 3D buildings + tilted camera) ──────

  Widget _buildMap(FamilyMapResult result) {
    _lastResult = result;

    return Stack(
      children: [
        // ── MapLibre map — permanent background ─────────────────────
        // Uses OpenFreeMap dark vector style with building height data.
        // Initial camera is flat (India overview). 3D buildings appear
        // when the user zooms in to street level (zoom 15+).
        MapLibreMap(
          options: MapOptions(
            initStyle: _kStyleUrl,
            initCenter: Geographic(lon: 78.9629, lat: 20.5937),
            initZoom: 4.5,
            initPitch: 0, // flat at India level — 3D kicks in on zoom
            minZoom: 2,
            maxZoom: 18,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoaded: _onStyleLoaded,
        ),

        // ── Legend overlay — bottom-left ───────────────────────────
        // The map is ALWAYS fully visible and interactive — no empty-state
        // card replaces it. The header subtitle "0 members located" is the
        // only indicator of empty data.
        Positioned(
          left: KinrelSpacing.base,
          bottom: KinrelSpacing.base,
          child: _MapLegend(result: result),
        ),
      ],
    );
  }

  // ── MapLibre lifecycle ─────────────────────────────────────────────

  void _onMapCreated(MapController controller) {
    _mapController = controller;
  }

  /// Called when the OpenFreeMap dark style finishes loading.
  /// This is where we add the 3D building extrusion layer + family pins.
  void _onStyleLoaded(StyleController style) async {
    _styleLoaded = true;
    final controller = _mapController;
    if (controller == null) return;

    // Add 3D building extrusion layer.
    // OpenFreeMap uses the OpenMapTiles vector schema:
    //   source: "openmaptiles" (the vector tile source in the style)
    //   source-layer: "building"
    //   height property: "render_height" (NOT "height" — OpenMapTiles
    //     uses render_height for the extruded height value)
    //   base property: "render_min_height" (NOT "min_height")
    try {
      await style.addLayer(FillExtrusionStyleLayer(
        id: 'kinrel-3d-buildings',
        sourceId: 'openmaptiles',
        sourceLayerId: 'building',
        minZoom: 15, // only show 3D buildings at street level
        maxZoom: 18,
        paint: {
          'fill-extrusion-color': '#1a1a2e',
          'fill-extrusion-height': ['get', 'render_height'],
          'fill-extrusion-base': ['get', 'render_min_height'],
          'fill-extrusion-opacity': 0.8,
          'fill-extrusion-vertical-gradient': true,
        },
      ));
      _buildingsAdded = true;
      debugPrint('✅ 3D building extrusion layer added successfully');
      debugPrint('   Using render_height / render_min_height (OpenMapTiles schema)');
    } catch (e) {
      debugPrint('❌ Failed to add 3D building extrusion: $e');
      debugPrint('   Expected source: "openmaptiles", source-layer: "building"');
      debugPrint('   Expected properties: "render_height", "render_min_height"');
    }

    // Add family member pins as a GeoJSON source + circle layers.
    if (_lastResult != null) {
      _addFamilyPins(style, _lastResult!);
    }
  }

  /// Add family member pins using GeoJSON source + circle layers.
  void _addFamilyPins(StyleController style, FamilyMapResult result) async {
    if (result.pins.isEmpty) return;

    // Build GeoJSON FeatureCollection of Points.
    final features = result.pins.map((pin) {
      return {
        'type': 'Feature',
        'id': pin.personId,
        'geometry': {
          'type': 'Point',
          'coordinates': [pin.lng, pin.lat],
        },
        'properties': {
          'personId': pin.personId,
          'name': pin.name,
        },
      };
    }).toList();

    final geojson = jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });

    try {
      await style.addSource(GeoJsonSource(id: 'family-members', data: geojson));

      await style.addLayer(CircleStyleLayer(
        id: 'kinrel-pin-glow',
        sourceId: 'family-members',
        paint: {
          'circle-color': '#E8612A',
          'circle-radius': 22,
          'circle-opacity': 0.15,
          'circle-blur': 1.0,
        },
      ));

      await style.addLayer(CircleStyleLayer(
        id: 'kinrel-pin-ring',
        sourceId: 'family-members',
        paint: {
          'circle-color': '#191B2C',
          'circle-radius': 16,
          'circle-stroke-color': '#E8612A',
          'circle-stroke-width': 2.5,
          'circle-opacity': 0.9,
        },
      ));
    } catch (e) {
      debugPrint('⚠️ Failed to add family pins: $e');
    }
  }

  /// Dev test: animate the camera to Bengaluru at zoom 16, tilt 45°
  /// to visually verify 3D building extrusion.
  void _flyToBengaluru3D() {
    final controller = _mapController;
    if (controller == null) {
      debugPrint('❌ Map controller not ready');
      return;
    }

    debugPrint('🚀 Flying to Bengaluru: zoom=16.5, pitch=45° for 3D building test');
    debugPrint('   3D buildings layer added: $_buildingsAdded');
    controller.animateCamera(
      center: Geographic(lon: 77.5946, lat: 12.9716), // Bengaluru
      zoom: 16.5,
      pitch: 45, // 45° pitch — shows 3D building extrusion
      bearing: 0,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Flying to Bengaluru — 3D buildings should appear at this zoom level'),
        duration: Duration(seconds: 4),
      ),
    );

    // ── Runtime feature query ───────────────────────────────────────
    // After the camera animation completes, query the rendered building
    // features at the screen center to verify that the "render_height"
    // property is actually present and non-zero.
    Future.delayed(const Duration(seconds: 5), () {
      _queryBengaluruBuildingProperties();
    });
  }

  /// Query rendered building features at the map center and log their
  /// available property keys + render_height value.
  void _queryBengaluruBuildingProperties() async {
    final controller = _mapController;
    if (controller == null || !_buildingsAdded) {
      debugPrint('⚠️ Cannot query buildings — controller null or layer not added');
      return;
    }

    try {
      final size = MediaQuery.of(context).size;
      final centerPoint = Offset(size.width / 2, size.height / 2);

      final features = controller.featuresAtPoint(
        centerPoint,
        layerIds: ['kinrel-3d-buildings'],
      );

      if (features.isEmpty) {
        debugPrint('⚠️ No building features found at Bengaluru center.');
        debugPrint('   Possible causes:');
        debugPrint('   - Zoom level too low (need 15+ for the minzoom filter)');
        debugPrint('   - Source "openmaptiles" or source-layer "building" not in style');
        debugPrint('   - Camera animation not yet complete');
        return;
      }

      debugPrint('✅ Found ${features.length} building feature(s) at Bengaluru center');

      final firstFeature = features.first;
      final props = firstFeature.properties;
      if (props == null || props.isEmpty) {
        debugPrint('   ⚠️ Feature has no properties — cannot verify render_height');
        return;
      }

      debugPrint('   Available property keys: ${props.keys.toList()}');
      debugPrint('   render_height = ${props['render_height']}');
      debugPrint('   render_min_height = ${props['render_min_height']}');

      final rh = props['render_height'];
      if (rh != null && rh is num && rh > 0) {
        debugPrint('✅ render_height is present and non-zero ($rh) — 3D extrusion should be visible');
      } else {
        debugPrint('❌ render_height is null or zero — buildings will appear flat!');
      }
    } catch (e) {
      debugPrint('❌ queryRenderedFeatures failed: $e');
    }
  }

  // ── Live location broadcast loop ────────────────────────────────────
  //
  // When the user has sharing enabled (toggled in Settings), the map
  // screen captures GPS every 5s and broadcasts to the family channel,
  // and upserts to MemberLocation at most once per 30s.

  void _startBroadcastLoop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _captureAndBroadcast();
    });
  }

  void _stopBroadcastLoop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _dbUpsertTimer?.cancel();
    _dbUpsertTimer = null;
  }

  Future<void> _captureAndBroadcast() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      final familyId = ref.read(familyListProvider).valueOrNull?.first.id ?? '';
      if (familyId.isEmpty) return;

      // We need the current user's personId. Get it from the family
      // members list — the Person whose linkedUserId matches the
      // current Supabase auth user.
      final members = ref.read(familyMembersProvider(familyId)).valueOrNull;
      final userId = ref.read(supabaseProvider)?.auth.currentUser?.id;
      if (members == null || userId == null) return;
      final myPerson = members.where((p) => p.linkedUserId == userId).firstOrNull;
      if (myPerson == null) return;

      ref.read(liveLocationProvider.notifier).broadcastMyLocation(
            familyId: familyId,
            personId: myPerson.id,
            lat: pos.latitude,
            lng: pos.longitude,
          );

      // Throttle DB writes to once per 30s.
      final now = DateTime.now();
      if (_lastDbUpsert == null || now.difference(_lastDbUpsert!).inSeconds >= 30) {
        await ref.read(liveLocationProvider.notifier).upsertMyLocation(
              familyId: familyId,
              personId: myPerson.id,
              lat: pos.latitude,
              lng: pos.longitude,
            );
        _lastDbUpsert = now;
      }
    } catch (e) {
      debugPrint('⚠️ Broadcast capture failed: $e');
    }
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

