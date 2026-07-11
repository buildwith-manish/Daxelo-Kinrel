// lib/features/family_map/presentation/family_map_screen.dart
//
// DAXELO KINREL — Family Map Screen (MapLibre Native)
//
// Full-screen interactive map showing family members as live pins on
// a real world map. Uses MapLibre Native (maplibre_gl) with OpenFreeMap
// dark vector tiles — free, unlimited, no API key.
//
// Architecture:
//   - Pins: GeoJSON source + circle/symbol layers (not per-member
//     annotation objects) — cheap source-data updates for live movement
//   - Relationship lines: GeoJSON LineStrings with quadratic Bézier
//     curves computed in lat/lng space, rendered as native line layers
//   - Live data: Supabase Realtime Broadcast for ephemeral movement,
//     MemberLocation table for last-known (see live_location_provider)
//   - Offline fallback: bundled minimal dark style JSON when tiles fail
//
// Package choice: maplibre_gl ^0.26.0
//   Verified on pub.dev: latest=0.26.2, published 2026-06-19, 160 pub points.
//   Chosen over the newer `maplibre` package (v0.3.5) because maplibre_gl
//   is more mature, supports all 3 target platforms (Android/iOS/Web),
//   and exposes the source/layer/symbol APIs this screen needs.
//   See §5 of the implementation spec for the full rationale.

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
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
  maplibre.MaplibreMapController? _mapController;
  bool _mapReady = false;
  bool _usingOfflineStyle = false;
  FamilyMapResult? _lastResult;

  /// OpenFreeMap dark style — free, unlimited, no API key.
  /// Already dark-themed to match Kinrel's art direction.
  static const _kStyleUrl = 'https://tiles.openfreemap.org/styles/dark';

  /// Offline fallback style — bundled minimal dark background.
  /// Used when the OpenFreeMap tiles fail to load (§9 of the spec).
  static const _kOfflineStyleAsset = 'assets/maps/kinrel-offline-dark.json';

  @override
  void initState() {
    super.initState();
    // Start the live location provider when the map screen mounts.
    // It reads last-known positions from MemberLocation + subscribes
    // to the family-map:{familyId} Broadcast channel for live movement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final families = ref.read(familyListProvider).valueOrNull;
      if (families != null && families.isNotEmpty) {
        ref.read(liveLocationProvider.notifier).start(families.first.id);
      }
    });
  }

  @override
  void dispose() {
    // Stop the live location subscription when the screen unmounts.
    ref.read(liveLocationProvider.notifier).stop();
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

  // ── Map View (MapLibre Native) ─────────────────────────────────────

  Widget _buildMap(FamilyMapResult result) {
    // Store the result so _onMapCreated can set up layers after the map
    // finishes loading its style.
    _lastResult = result;

    return Stack(
      children: [
        maplibre.MaplibreMap(
          styleString: _kStyleUrl,
          initialCameraPosition: const maplibre.CameraPosition(
            target: maplibre.LatLng(20.5937, 78.9629),
            zoom: 4.5,
          ),
          minMaxZoomPreference: const maplibre.MinMaxZoomPreference(2.0, 16.0),
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          onMapClick: _onMapClick,
          trackCameraPosition: false,
        ),

        // Offline fallback banner (shown when tiles fail to load)
        if (_usingOfflineStyle)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: KinrelSpacing.base,
            right: KinrelSpacing.base,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Map unavailable — showing last known family locations',
                style: TextStyle(
                  color: KinrelColors.textSilver,
                  fontSize: 12,
                  fontFamily: KinrelTypography.bodyFont,
                ),
              ),
            ),
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

  // ── MapLibre lifecycle callbacks ───────────────────────────────────

  void _onMapCreated(maplibre.MaplibreMapController controller) {
    _mapController = controller;
  }

  /// Called when the map style finishes loading. This is where we add
  /// GeoJSON sources + layers for pins and relationship lines.
  /// If the style fails to load (network error), we fall back to the
  /// bundled offline style (§9).
  void _onStyleLoaded() async {
    _mapReady = true;
    final controller = _mapController;
    if (controller == null || _lastResult == null) return;

    try {
      await _setupLayers(controller, _lastResult!);
      if (mounted) setState(() {});
    } catch (e) {
      // Style load failed — try the offline fallback.
      debugPrint('⚠️ MapLibre style load failed, trying offline fallback: $e');
      _loadOfflineStyle();
    }
  }

  /// Load the bundled offline style as a fallback (§9).
  void _loadOfflineStyle() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      final styleJson = await rootBundle.loadString(_kOfflineStyleAsset);
      await controller.setStyleString(styleJson);
      _usingOfflineStyle = true;
      // Re-add layers on the new style
      if (_lastResult != null) {
        await _setupLayers(controller, _lastResult!);
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('⚠️ Offline fallback style also failed: $e');
    }
  }

  /// Set up GeoJSON sources + layers for family member pins and
  /// relationship lines. Called after the style loads.
  Future<void> _setupLayers(
    maplibre.MaplibreMapController controller,
    FamilyMapResult result,
  ) async {
    // ── Family member pins (GeoJSON source + circle + symbol layers) ──
    final memberGeoJson = _buildMemberGeoJson(result.pins);
    await controller.addSource('family-members', maplibre.GeojsonSourceProperties(data: memberGeoJson));

    // Glow circle (soft orange behind avatar)
    await controller.addCircleLayer(
      'family-members',
      'kinrel-glow',
      const maplibre.CircleLayerProperties(
        circleColor: '#E8612A',
        circleRadius: 22,
        circleOpacity: 0.15,
        circleBlur: 1.0,
      ),
    );

    // Ring circle (teal for self, orange for others)
    await controller.addCircleLayer(
      'family-members',
      'kinrel-ring',
      const maplibre.CircleLayerProperties(
        circleColor: '#E8612A',
        circleRadius: 18,
        circleStrokeColor: '#0D9488',
        circleStrokeWidth: 2,
        circleOpacity: 0.9,
      ),
    );

    // ── Relationship lines (GeoJSON LineStrings) ─────────────────────
    if (result.edges.isNotEmpty) {
      final lineGeoJson = _buildRelationshipLineGeoJson(result.edges);
      await controller.addSource('relationship-lines', maplibre.GeojsonSourceProperties(data: lineGeoJson));

      await controller.addLineLayer(
        'relationship-lines',
        'kinrel-lines',
        const maplibre.LineLayerProperties(
          lineColor: '#E8612A',
          lineOpacity: 0.35,
          lineWidth: 1.5,
          lineCap: 'round',
        ),
      );

      // Midpoint dots (tappable glow circles at curve apex)
      final dotGeoJson = _buildRelationshipDotGeoJson(result.edges);
      await controller.addSource('relationship-dots', maplibre.GeojsonSourceProperties(data: dotGeoJson));

      await controller.addCircleLayer(
        'relationship-dots',
        'kinrel-dot-glow',
        const maplibre.CircleLayerProperties(
          circleColor: '#E8612A',
          circleRadius: 10,
          circleOpacity: 0.2,
          circleBlur: 1.0,
        ),
      );

      await controller.addCircleLayer(
        'relationship-dots',
        'kinrel-dot-solid',
        const maplibre.CircleLayerProperties(
          circleColor: '#F59E0B',
          circleRadius: 4,
          circleOpacity: 0.9,
        ),
      );
    }
  }

  // ── GeoJSON builders ───────────────────────────────────────────────

  /// Build GeoJSON FeatureCollection of Points for family member pins.
  /// Each feature has properties: personId, name, isSelf, tier.
  String _buildMemberGeoJson(List<MapPin> pins) {
    final features = pins.map((pin) {
      return {
        'type': 'Feature',
        'id': pin.personId,
        'geometry': {
          'type': 'Point',
          'coordinates': [pin.lng, pin.lat], // GeoJSON is [lng, lat]
        },
        'properties': {
          'personId': pin.personId,
          'name': pin.name,
          'isSelf': pin.isSelf,
          'tier': pin.locationTier.name,
          'isSharing': pin.isSharing,
        },
      };
    }).toList();

    return jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  /// Build GeoJSON FeatureCollection of LineStrings for relationship
  /// edges. Each LineString is a quadratic Bézier curve sampled into
  /// 24-32 points, computed in lat/lng space (§7 of the spec).
  String _buildRelationshipLineGeoJson(List<MapRelationshipEdge> edges) {
    final features = edges.map((edge) {
      final curvePoints = _computeBezierCurve(
        edge.pinA.lat, edge.pinA.lng,
        edge.pinB.lat, edge.pinB.lng,
      );

      return {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': curvePoints
              .map((p) => [p.$2, p.$1]) // [lng, lat]
              .toList(),
        },
        'properties': {
          'relationshipKey': edge.relationshipKey,
          'personAId': edge.pinA.personId,
          'personBId': edge.pinB.personId,
        },
      };
    }).toList();

    return jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  /// Build GeoJSON FeatureCollection of Points at the midpoint of each
  /// relationship curve (t=0.5). These are the tappable dots.
  String _buildRelationshipDotGeoJson(List<MapRelationshipEdge> edges) {
    final features = edges.map((edge) {
      final mid = _computeBezierMidpoint(
        edge.pinA.lat, edge.pinA.lng,
        edge.pinB.lat, edge.pinB.lng,
      );

      return {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [mid.$2, mid.$1], // [lng, lat]
        },
        'properties': {
          'relationshipKey': edge.relationshipKey,
          'personAId': edge.pinA.personId,
          'personBId': edge.pinB.personId,
        },
      };
    }).toList();

    return jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  /// Compute a quadratic Bézier curve in lat/lng space between two
  /// points. Returns ~28 sampled (lat, lng) tuples.
  /// The control point is offset perpendicular to the line connecting
  /// the two endpoints, same math as the old _MapGraphEdgePainter but
  /// applied to coordinates instead of pixel Offsets.
  List<(double, double)> _computeBezierCurve(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    // Midpoint
    final midLat = (lat1 + lat2) / 2;
    final midLng = (lng1 + lng2) / 2;

    // Perpendicular offset (curve the line away from the direct path)
    final dLat = lat2 - lat1;
    final dLng = lng2 - lng1;
    final distance = math.sqrt(dLat * dLat + dLng * dLng);
    // Offset factor — 20% of the distance, perpendicular direction
    final offsetMag = distance * 0.20;
    // Perpendicular direction (rotate 90°)
    final perpLat = -dLng / (distance > 0 ? distance : 1);
    final perpLng = dLat / (distance > 0 ? distance : 1);

    // Control point
    final ctrlLat = midLat + perpLat * offsetMag;
    final ctrlLng = midLng + perpLng * offsetMag;

    // Sample 28 points along the quadratic Bézier
    final points = <(double, double)>[];
    const steps = 28;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final oneMinusT = 1 - t;
      // B(t) = (1-t)² P0 + 2(1-t)t P1 + t² P2
      final pLat = oneMinusT * oneMinusT * lat1 +
          2 * oneMinusT * t * ctrlLat +
          t * t * lat2;
      final pLng = oneMinusT * oneMinusT * lng1 +
          2 * oneMinusT * t * ctrlLng +
          t * t * lng2;
      points.add((pLat, pLng));
    }
    return points;
  }

  /// Compute the midpoint (t=0.5) of the Bézier curve.
  (double, double) _computeBezierMidpoint(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    final curve = _computeBezierCurve(lat1, lng1, lat2, lng2);
    return curve[curve.length ~/ 2];
  }

  // ── Tap handling ───────────────────────────────────────────────────

  /// Handle a tap on the map. Query the feature at the tap point to
  /// determine if a pin or relationship dot was tapped.
  void _onMapClick(point, latlng) async {
    final controller = _mapController;
    if (controller == null || _lastResult == null) return;

    // Query relationship dots first (they're smaller, on top)
    try {
      final dotFeatures = await controller.queryRenderedFeatures(
        point,
        ['kinrel-dot-solid'],
        null,
      );
      if (dotFeatures.isNotEmpty) {
        final props = dotFeatures.first['properties'] as Map<String, dynamic>?;
        if (props != null) {
          final personAId = props['personAId'] as String?;
          final personBId = props['personBId'] as String?;
          final relKey = props['relationshipKey'] as String?;
          if (personAId != null && personBId != null && relKey != null) {
            final edge = _lastResult!.edges.where((e) =>
              e.pinA.personId == personAId && e.pinB.personId == personBId
            ).firstOrNull;
            if (edge != null) {
              _showRelationshipBottomSheet(edge);
              return;
            }
          }
        }
      }
    } catch (_) {}

    // Then query member pins
    try {
      final pinFeatures = await controller.queryRenderedFeatures(
        point,
        ['kinrel-ring'],
        null,
      );
      if (pinFeatures.isNotEmpty) {
        final props = pinFeatures.first['properties'] as Map<String, dynamic>?;
        if (props != null) {
          final personId = props['personId'] as String?;
          if (personId != null) {
            final pin = _lastResult!.pins.where((p) => p.personId == personId).firstOrNull;
            if (pin != null) {
              _showPinBottomSheet(pin);
              return;
            }
          }
        }
      }
    } catch (_) {}
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
