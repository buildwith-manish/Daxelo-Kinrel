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
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
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
import '../../../core/kinship/heart_shape.dart';
import '../../../core/utils/device_tier.dart';
import '../../../graph/interaction/graph_focus_state.dart';
import '../../family_journey/providers/journey_provider.dart';
import '../config/map_visual_constants.dart';
import '../data/place_models.dart';
import '../widgets/family_building_layer.dart';
import '../widgets/avatar_marker_generator.dart';
import '../widgets/avatar_marker_overlay.dart';
import '../widgets/household_cluster_marker.dart';
import '../widgets/animated_relationship_path.dart';
import '../widgets/map_focus_controller.dart';
import '../widgets/map_timeline_scrubber.dart';
import '../widgets/family_journey_animation.dart';
import '../widgets/map_polish_overlay.dart';
import '../widgets/ambient_motion_controller.dart';
import '../widgets/map_skeleton.dart';
import '../data/map_state_persistence.dart';
import '../data/poi_filter.dart';
import '../data/progressive_loading.dart';
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

class _FamilyMapScreenState extends ConsumerState<FamilyMapScreen>
    with TickerProviderStateMixin {
  MapController? _mapController;
  bool _styleLoaded = false;
  bool _buildingsAdded = false;
  FamilyMapResult? _lastResult;
  Timer? _broadcastTimer;
  Timer? _dbUpsertTimer;
  DateTime? _lastDbUpsert;

  /// P10.2 — Family buildings (semantic types + emotional lighting).
  /// Initialized on first style load; updated whenever familyMapProvider
  /// emits a new place list.
  final FamilyBuildingLayer _familyBuildings = FamilyBuildingLayer();

  /// P10.3 — Premium avatar markers. Owns the SymbolLayer vs Flutter
  /// overlay decision (Rule 12 fallback) and the marker image cache.
  final AvatarMarkerLayer _avatarLayer = AvatarMarkerLayer();

  /// P10.5 — Animated relationship paths. Owns the line-gradient vs
  /// Flutter overlay decision (Rule 12 fallback) and the flow animation.
  AnimatedRelationshipPath? _relationshipPaths;

  /// P10.6 — Map Focus Mode controller. Drives camera + opacity changes
  /// when the user taps a family member marker.
  final MapFocusController _focusController = MapFocusController();

  /// P10.8 — Progressive loading state machine. Drives the loading
  /// indicator text + advance through 8 phases.
  MapLoadState _loadState = const MapLoadState();

  /// P10.9 — Debounced session-state saver. familyId is set in initState
  /// once the family list resolves. flushNow() is called on dispose.
  DebouncedMapStateSaver? _stateSaver;

  /// P10.9 — Restored session state (camera + selection + timeline year).
  /// Null until the async load completes; the map reads it on init.
  MapSessionState? _restoredState;

  /// P10.4 — Currently-expanded household. Null when no cluster expanded.
  String? _expandedHouseholdId;

  /// P10.7 — Family Journey animation. Null when no person selected for
  /// journey replay. Set via long-press on an avatar.
  List<JourneyStop>? _journeyStops;

  /// Premium: selected pin state for relationship focus dimming.
  String? _selectedPinId;

  /// Premium: one-time cinematic entrance animation flag.
  bool _entranceAnimationDone = false;

  /// P10.5 — Trigger for relationship path overlay repaint. Bumped by
  /// the AnimatedRelationshipPath on each animation tick.
  final ValueNotifier<int> _pathRepaintNotifier = ValueNotifier<int>(0);

  /// P11.6 — Ambient motion controller (desktop/web only). Starts the
  /// idle timer on map create; drifts the camera after 30s of no
  /// interaction. Disabled on mobile + low-tier + reduced motion.
  AmbientMotionController? _ambientMotion;

  /// Bundled Kinrel dark style — loaded at runtime from the app bundle
  /// and passed as a raw JSON string to MapLibre. This bypasses the
  /// web plugin's AssetManager URL resolution (which doesn't handle
  /// the asset:// protocol correctly).
  ///
  /// Based on OpenFreeMap liberty style (actively maintained, tuned
  /// label density) recolored dark with Kinrel brand colors. Includes
  /// 3D building extrusion layer.
  ///
  /// P10.8: POI filter is applied at load time — restaurants, cafés,
  /// hotels, shopping, nightlife, fuel are hidden; schools, hospitals,
  /// religious, parks, cemeteries are kept. Secondary POIs only appear
  /// past zoom 14.
  static const _kStyleAssetPath = 'assets/map_styles/kinrel_dark_style.json';
  String? _loadedStyleJson;

  /// Minimal inline dark style — used when the bundled asset fails to
  /// load (e.g., Flutter Web `asset://` resolution issues on Vercel).
  ///
  /// Just enough to render a usable map:
  ///   - background + water + land + roads from OpenFreeMap planet tiles
  ///   - the `family-places` GeoJSON source (empty by default — populated
  ///     at runtime by [FamilyBuildingLayer.add])
  ///   - the `family-buildings-glow`, `family-buildings`, and
  ///     `family-buildings-fallback` layers with the per-PlaceType
  ///     `match` color expression
  ///
  /// This is the single source of truth for the fallback. It must stay
  /// in sync with the family-* layers in `kinrel_dark_style.json`.
  static const _kFallbackStyleJson = '''
{
  "version": 8,
  "sources": {
    "openmaptiles": {
      "type": "vector",
      "url": "https://tiles.openfreemap.org/planet"
    },
    "family-places": {
      "type": "geojson",
      "data": { "type": "FeatureCollection", "features": [] }
    }
  },
  "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
  "layers": [
    {"id":"background","type":"background","paint":{"background-color":"#131416"}},
    {"id":"water","type":"fill","source":"openmaptiles","source-layer":"water","paint":{"fill-color":"#162335"}},
    {"id":"land","type":"fill","source":"openmaptiles","source-layer":"landcover","paint":{"fill-color":"#191B2C"}},
    {"id":"road-minor","type":"line","source":"openmaptiles","source-layer":"transportation","paint":{"line-color":"#2A2440","line-width":1}},
    {"id":"road-primary","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["==",["get","class"],"primary"],"paint":{"line-color":"#3A3252","line-width":2}},
    {"id":"road-motorway","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["==",["get","class"],"motorway"],"paint":{"line-color":"#4A3F63","line-width":3}},
    {"id":"family-buildings-glow","type":"circle","source":"family-places","minzoom":10,"paint":{"circle-color":["match",["get","placeType"],"current_home","#E8612A","childhood_home","#F59240","ancestral_home","#917520","birthplace","#F5B841","wedding","#E8612A","memorial","#F59240","family_business","#C44A18","school","#4E6984","important_place","#E8612A","#E8612A"],"circle-radius":24,"circle-blur":1.0,"circle-opacity":0.65}},
    {"id":"family-buildings","type":"fill-extrusion","source":"family-places","minzoom":13,"paint":{"fill-extrusion-color":["match",["get","placeType"],"current_home","#E8612A","childhood_home","#F59240","ancestral_home","#917520","birthplace","#F5B841","wedding","#E8612A","memorial","#F59240","family_business","#C44A18","school","#4E6984","important_place","#E8612A","#E8612A"],"fill-extrusion-height":12,"fill-extrusion-base":0,"fill-extrusion-opacity":0.95,"fill-extrusion-vertical-gradient":true}},
    {"id":"family-buildings-fallback","type":"circle","source":"family-places","maxzoom":13,"paint":{"circle-color":["match",["get","placeType"],"current_home","#E8612A","childhood_home","#F59240","ancestral_home","#917520","birthplace","#F5B841","wedding","#E8612A","memorial","#F59240","family_business","#C44A18","school","#4E6984","important_place","#E8612A","#E8612A"],"circle-radius":6,"circle-stroke-color":"#FFFFFF","circle-stroke-width":1,"circle-opacity":0.9}}
  ]
}
''';

  /// Loads the Kinrel dark style JSON. Tries the bundled asset first;
  /// on any failure (timeout, asset not found, web `asset://` resolution
  /// error) falls back to [_kFallbackStyleJson] so the map still renders.
  ///
  /// Bug 1 fix: previously this method had no try/catch and no timeout,
  /// so on Flutter Web the `rootBundle.loadString` call could hang
  /// indefinitely when the asset failed to resolve, leaving the
  /// FutureBuilder stuck on the skeleton screen forever.
  Future<String> _loadStyleJson() async {
    if (_loadedStyleJson != null) return _loadedStyleJson!;
    try {
      final raw = await rootBundle
          .loadString(_kStyleAssetPath)
          .timeout(const Duration(seconds: 10));
      // P10.8 — Apply POI filter at load time (Rule 15: works offline
      // because the style is bundled). Returns input unchanged on parse
      // error (Rule 12 graceful degradation).
      _loadedStyleJson = applyPoiFilters(raw);
    } catch (e) {
      debugPrint('⚠️ _loadStyleJson failed, using inline fallback: $e');
      _loadedStyleJson = _kFallbackStyleJson;
    }
    return _loadedStyleJson!;
  }

  @override
  void initState() {
    super.initState();
    // Start the live location provider when the map screen mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final familyId = ref.read(familyListProvider).valueOrNull?.first.id;
      if (familyId != null) {
        ref.read(liveLocationProvider.notifier).start(familyId);
        // P10.9 — initialize the debounced state saver for this family.
        _stateSaver = DebouncedMapStateSaver(familyId);
        // P10.9 — Load saved session state (camera, selection, timeline
        // year, focus mode, expanded household). On load, the screen
        // restores the camera + selection + timeline year. Gracefully
        // returns null on first launch / corrupted JSON.
        MapStatePersistence.load(familyId).then((state) {
          if (state != null && mounted) {
            setState(() => _restoredState = state);
            // Restore selection.
            _selectedPinId = state.selectedPersonId;
            // Restore expanded household.
            _expandedHouseholdId = state.expandedHouseholdId;
            // Restore timeline year via the journey provider.
            if (state.timelineYear != null) {
              ref
                  .read(journeyProvider.notifier)
                  .setYear(state.timelineYear!);
            }
            debugPrint('📦 P10.9: restored map session state $state');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _stopBroadcastLoop();
    _familyBuildings.dispose();
    _avatarLayer.cache.clear();
    _relationshipPaths?.dispose();
    _pathRepaintNotifier.dispose();
    _ambientMotion?.dispose();
    // P10.9 — flush any pending state save before tearing down.
    _stateSaver?.flushNow();
    _stateSaver?.dispose();
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
        loading: () => MapSkeleton(
          reducedMotion: MediaQuery.disableAnimationsOf(context),
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

  /// Bug 2 fix: Skeleton shown while the style JSON is loading.
  /// Includes an explicit "Loading family map…" message so the user
  /// knows what's happening — not a bare spinner.
  Widget _buildMapSkeleton() {
    return MapSkeleton(
      reducedMotion: MediaQuery.disableAnimationsOf(context),
      message: 'Loading family map…',
    );
  }

  /// Bug 2 fix: Error UI shown when the style JSON fails to load.
  /// Provides a Retry button that clears the cached style and re-fetches.
  Widget _buildStyleLoadError() {
    return Stack(
      children: [
        Container(color: KinrelColors.darkBackground),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined,
                    color: KinrelColors.orange, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Could not load the family map.',
                  style: TextStyle(
                    color: KinrelColors.textWhite,
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Check your connection and try again.',
                  style: TextStyle(
                    color: KinrelColors.textDim,
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loadedStyleJson = null;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: KinrelColors.orange,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMap(FamilyMapResult result) {
    _lastResult = result;

    // P10.7 — Filter pins + places by the journey provider's selected year.
    // On first build the journey state defaults to the current year, so all
    // alive members are shown.
    final journeyState = ref.watch(journeyProvider);
    final filteredPins = ref
            .read(journeyProvider.notifier)
            .filterMapPins(result.pins);
    final filteredPlaces = ref
        .read(journeyProvider.notifier)
        .filterMapPlaces(result.places);

    // P10.4 — Compute households from the filtered pins.
    final households = computeHouseholds(filteredPins);

    // P10.6 — Watch the focus state (drives per-marker opacity in the overlay).
    final focusState = ref.watch(graphFocusProvider);

    // P10.6 — Reduced-motion flag from MediaQuery (matches the graph pattern).
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    // Bug 4 fix: watch live location state so the AvatarMarkerOverlay can
    // pass per-pin LocationTier (live/recent/stale/cityFallback) — needed
    // for the LIVE pulse + STALE dimming visual treatments.
    final liveState = ref.watch(liveLocationProvider);

    // P11.2 — Update the family-buildings GeoJSON source when the filtered
    // places list changes. The source + layers are in the style JSON; we
    // just populate the data. Wrapped in post-frame callback to avoid
    // calling async style methods during build.
    if (_styleLoaded && filteredPlaces.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final style = _mapController?.style;
        if (style != null) {
          _familyBuildings.update(style, filteredPlaces);
        }
      });
    }

    // P10.9 — Initial camera from restored state (if any).
    final restored = _restoredState;
    final initCenter = restored != null
        ? Geographic(lon: restored.lng, lat: restored.lat)
        : Geographic(lon: 78.9629, lat: 20.5937);
    final initZoom = restored?.zoom ?? 4.0;
    final initPitch = restored?.pitch ?? 0.0;

    return FutureBuilder<String>(
      future: _loadStyleJson(),
      builder: (context, snapshot) {
        // Bug 2 fix: explicit error UI with Retry button. Previously
        // only `!snapshot.hasData` was checked — on error the user
        // saw a silent spinner forever.
        if (snapshot.hasError) {
          return _buildStyleLoadError();
        }
        if (!snapshot.hasData) {
          return _buildMapSkeleton();
        }

        // Pass the raw JSON string directly — the maplibre web plugin
        // detects strings starting with '{' as inline JSON, bypassing
        // the broken AssetManager URL resolution for asset:// paths.
        // P10.8 — POI filter is already applied in _loadStyleJson().
        final styleJson = snapshot.data!;

        return Stack(
          children: [
            // ── MapLibre map — permanent background ─────────────────────
            MapLibreMap(
              options: MapOptions(
                initStyle: styleJson,
                initCenter: initCenter,
                // Premium: start from higher altitude for cinematic descent
                initZoom: initZoom,
                initPitch: initPitch,
                minZoom: 2,
                maxZoom: 18,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoaded: _onStyleLoaded,
              // P10.2 / P10.6 — Handle map taps: if a family building is
              // hit, open its bottom sheet; otherwise exit Focus Mode.
              onEvent: (event) {
                if (event is MapEventClick) {
                  _handleMapTap(event.screenPoint);
                }
              },
            ),

            // ── P10.5 — Animated relationship paths overlay ─────────────
            // Rendered as a Flutter CustomPainter overlay because maplibre
            // 0.3.5 does not expose setPaintProperty (Rule 12 fallback).
            // The overlay reads pin screen positions from the controller.
            if (_styleLoaded && filteredPins.length >= 2)
              _RelationshipPathOverlay(
                mapController: _mapController,
                edges: result.edges,
                pins: filteredPins,
                progressNotifier: _pathRepaintNotifier,
                reducedMotion: reducedMotion,
              ),

            // ── P10.3 — Premium avatar markers (Flutter overlay path) ───
            // Replaces the old CircleStyleLayer pins. maplibre 0.3.5's
            // addImage API is probed at style-load time; if it throws,
            // the overlay path is used (Rule 12). The overlay renders
            // AvatarMarkerWidget for each pin with per-tier opacity
            // driven by the focus state (P10.6).
            //
            // Bug 4 fix: pass the live location tiers (live/recent/stale/
            // cityFallback) from the live location provider so markers
            // get the correct visual treatment. Previously this was an
            // empty map, which meant no LIVE pulse / STALE dimming.
            if (_styleLoaded && filteredPins.isNotEmpty)
              AvatarMarkerOverlay(
                mapController: _mapController,
                pins: filteredPins,
                selectedPinId: _selectedPinId,
                liveTiers: {
                  for (final entry in liveState.locations.entries)
                    entry.key: entry.value.tier,
                },
                reducedMotion: reducedMotion,
                onPinTap: _handlePinTap,
                onPinLongPress: _handlePinLongPress,
              ),

            // ── P10.4 — Household cluster markers ───────────────────────
            // Rendered as Positioned widgets for clusters with >1 member.
            // Single-member households are rendered by the avatar overlay.
            if (_styleLoaded && households.any((h) => h.isMulti))
              _HouseholdClusterOverlay(
                mapController: _mapController,
                households: households.where((h) => h.isMulti).toList(),
                expandedHouseholdId: _expandedHouseholdId,
                reducedMotion: reducedMotion,
                onClusterTap: _handleClusterTap,
                onClusterLongPress: _handleClusterLongPress,
              ),

            // ── P10.8 — Polish overlay (vignette + fog + ambient) ───────
            // Rendered on top of the map but below the bottom sheets.
            // IgnorePointer so map gestures pass through.
            // Bug 4 fix: pass deviceTier + reducedMotion so the overlay
            // disables fog/ambient on low-tier devices and respects
            // the user's reduced-motion preference.
            MapPolishOverlay(
              deviceTier: DeviceTierCache.instance.tier,
              reducedMotion: reducedMotion,
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

            // ── P10.7 — Timeline scrubber at the bottom ─────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MapTimelineScrubber(
                onYearChanged: (year) {
                  // P10.9 — Save the new year (debounced).
                  _scheduleStateSave();
                },
                reducedMotion: reducedMotion,
              ),
            ),

            // ── P10.7 — Family Journey animation (when a person is selected) ──
            if (_journeyStops != null && _journeyStops!.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 80,
                child: FamilyJourneyAnimation(
                  stops: _journeyStops!,
                  reducedMotion: reducedMotion,
                  onClose: () {
                    setState(() => _journeyStops = null);
                  },
                ),
              ),

            // ── P10.8 — Progressive loading indicator ───────────────────
            if (_loadState.phase != MapLoadPhase.complete &&
                _loadState.message.isNotEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkCard.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _loadState.message,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: KinrelTypography.bodyFont,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── MapLibre lifecycle ─────────────────────────────────────────────

  void _onMapCreated(MapController controller) {
    _mapController = controller;

    // P11.6 — Attach the ambient motion controller (desktop/web only).
    // It starts an idle timer; after 30s of no interaction, the camera
    // slowly drifts. onUserInteraction() resets the timer.
    _ambientMotion = AmbientMotionController(vsync: this);
    _ambientMotion!.attach(controller);

    // P11.6 — Cinematic entrance animation.
    // Only plays on first open (no saved state from P10.9). Returning
    // users get instant restore via _restoredState (handled in _buildMap
    // via initCenter/initZoom).
    if (!_entranceAnimationDone && _restoredState == null) {
      _entranceAnimationDone = true;
      final reducedMotion = MediaQuery.disableAnimationsOf(context);
      if (reducedMotion) {
        // Reduced motion: instant camera move (no animation).
        controller.moveCamera(
          center: Geographic(lon: 78.9629, lat: 20.5937),
          zoom: 5.5,
        );
      } else {
        // Cinematic entrance: animate from zoom 4 → 5.5 over
        // cinematicEntrance duration (1500ms, tunable — Rule 5).
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_mapController == null) return;
          _mapController!.animateCamera(
            center: Geographic(lon: 78.9629, lat: 20.5937),
            zoom: 5.5,
            pitch: 0,
            bearing: 0,
            nativeDuration: MapVisualConstants.cinematicEntrance,
          );
        });
      }
    } else {
      _entranceAnimationDone = true;
    }
  }

  /// Called when the OpenFreeMap dark style finishes loading.
  /// This is where we add the 3D building extrusion layer + family pins.
  void _onStyleLoaded(StyleController style) async {
    _styleLoaded = true;
    final controller = _mapController;
    if (controller == null) return;

    // 3D building extrusion is already in the bundled style JSON
    // (kinrel_dark_style.json includes the "kinrel-3d-buildings"
    // fill-extrusion layer with render_height/render_min_height).
    // No need to add it programmatically — it loads with the style.
    _buildingsAdded = true;
    debugPrint('✅ Style loaded — 3D buildings layer is in the bundled style');

    // P10.8 — Advance progressive loading: tiles + roads/buildings are in.
    setState(() => _loadState = _loadState.copyWith(
      phase: MapLoadPhase.roadsAndBuildings,
    ));

    // P10.3 — Probe SymbolLayer support. If addImage throws, the
    // AvatarMarkerOverlay (Flutter overlay path) is used. Either way,
    // the old CircleStyleLayer pins are no longer added — the overlay
    // renders the premium avatar markers.
    await _avatarLayer.verifySymbolLayerSupport(style);
    debugPrint('🎨 P10.3: avatar overlay path = ${_avatarLayer.useOverlay}');

    if (_lastResult != null) {
      // P10.2 — Family buildings with per-type emotional lighting.
      // Rendered as a GeoJSON source + FillExtrusionStyleLayer with a
      // match expression on the placeType property. Tap handled in
      // _handleMapTap via featuresAtPoint.
      if (_lastResult!.places.isNotEmpty) {
        await _familyBuildings.add(style, _lastResult!.places);
        setState(() => _loadState = _loadState.copyWith(
          phase: MapLoadPhase.familyPlaces,
        ));
      }

      // P10.5 — Animated relationship paths. The LineLayer is added to
      // the style with a static color; the flow animation is rendered
      // by the Flutter overlay (RelationshipPathOverlayPainter) driven
      // by the AnimatedRelationshipPath controller.
      if (_lastResult!.edges.isNotEmpty) {
        _relationshipPaths = AnimatedRelationshipPath(
          tickerProvider: this,
          mapController: controller,
          style: style,
          reducedMotion: MediaQuery.disableAnimationsOf(context),
          onRepaint: () => _pathRepaintNotifier.value++,
        );
        await _relationshipPaths!.verifyLineGradientSupport();
        _relationshipPaths!.start();
        setState(() => _loadState = _loadState.copyWith(
          phase: MapLoadPhase.relationshipPaths,
        ));
      }

      // P10.8 — Advance to markers + animations phase.
      setState(() => _loadState = _loadState.copyWith(
        phase: MapLoadPhase.markers,
      ));
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _loadState = _loadState.copyWith(
            phase: MapLoadPhase.complete,
          ));
        }
      });
    }
  }

  /// P10.3 / P10.6 — Handle a tap on a family member avatar marker.
  /// Activates Focus Mode (P10.6): camera springs to center on them,
  /// non-focus markers dim, related relationship paths brighten.
  void _handlePinTap(MapPin pin) async {
    setState(() => _selectedPinId = pin.personId);

    // P10.6 — Enter Focus Mode via the MapFocusController.
    final focusState = ref.read(graphFocusProvider);
    await _focusController.enterFocus(
      mapController: _mapController,
      style: _mapController?.style,
      familyBuildings: _familyBuildings,
      pin: pin,
      focusState: focusState,
    );

    // P10.9 — Save the new selection immediately.
    _scheduleStateSave();

    // Show the existing pin bottom sheet.
    if (mounted) _showPinBottomSheet(pin);
  }

  /// P10.7 — Handle a long-press on a family member avatar marker.
  /// Builds the journey stops from the person's linked places and
  /// shows the FamilyJourneyAnimation widget.
  void _handlePinLongPress(MapPin pin) {
    final result = _lastResult;
    if (result == null) return;
    final linkedPlaces =
        result.places.where((p) => p.personId == pin.personId).toList();
    final stops = buildJourneyStops(
      pin: pin,
      linkedPlaces: linkedPlaces,
    );
    if (stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No journey data for this family member yet.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _journeyStops = stops);
  }

  /// P10.4 — Handle a tap on a household cluster marker.
  /// If zoom < clusterMaxZoom, zoom in (spring physics via P3.1).
  /// Otherwise, expand the cluster to show individual members in a
  /// bottom sheet.
  void _handleClusterTap(Household household) {
    final controller = _mapController;
    if (controller == null) return;
    final currentZoom = controller.camera?.zoom ?? 14.0;
    if (currentZoom < MapVisualConstants.clusterMaxZoom) {
      controller.animateCamera(
        center: Geographic(lon: household.lng, lat: household.lat),
        zoom: MapVisualConstants.clusterMaxZoom + 1,
      );
    } else {
      setState(() => _expandedHouseholdId = household.id);
      _showHouseholdBottomSheet(household);
    }
    _scheduleStateSave();
  }

  /// P10.4 — Handle a long-press on a household cluster marker.
  /// Temporarily expands the cluster to show individual members.
  void _handleClusterLongPress(Household household) {
    setState(() => _expandedHouseholdId = household.id);
    _showHouseholdBottomSheet(household);
    _scheduleStateSave();
  }

  /// P10.2 — Handle a tap on the map background. If the tap hits a
  /// family building (queried via featuresAtPoint on the
  /// kinrel-family-buildings-fallback layer), open the
  /// FamilyBuildingBottomSheet. Otherwise, exit Focus Mode.
  void _handleMapTap(Offset screenPoint) async {
    final controller = _mapController;
    if (controller == null) return;

    // Query family buildings at the tap point.
    try {
      final features = controller.featuresAtPoint(
        screenPoint,
        layerIds: const [
          FamilyBuildingLayer.circleFallbackLayerId,
          FamilyBuildingLayer.extrusionLayerId,
        ],
      );
      if (features.isNotEmpty) {
        final feature = features.first;
        final props = feature.properties ?? const <String, dynamic>{};
        final placeId = props['placeId'] as String?;
        if (placeId != null) {
          final place = _lastResult?.places.firstWhere(
            (p) => p.id == placeId,
            orElse: () => _lastResult!.places.first,
          );
          if (place != null && mounted) {
            _showFamilyBuildingBottomSheet(place);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ featuresAtPoint failed: $e');
    }

    // P10.6 — Tap empty map → exit Focus Mode.
    if (_selectedPinId != null) {
      setState(() => _selectedPinId = null);
      await _focusController.exitFocus(
        mapController: _mapController,
        style: _mapController?.style,
        familyBuildings: _familyBuildings,
      );
      _scheduleStateSave();
    }
  }

  /// P10.2 — Show the family building bottom sheet (reuses the
  /// FamilyBuildingBottomSheet widget from family_building_layer.dart).
  void _showFamilyBuildingBottomSheet(FamilyPlace place) {
    final linkedPersonName = _lastResult?.pins
        .firstWhere(
          (p) => p.personId == place.personId,
          orElse: () => _lastResult!.pins.first,
        )
        .name;
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

  /// P10.4 — Show the household members bottom sheet.
  void _showHouseholdBottomSheet(Household household) {
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
                'Household — ${household.size} members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 12),
              ...household.members.map((pin) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: KinrelColors.darkElevated,
                      child: Text(
                        _initials(pin.name),
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
                      _handlePinTap(pin);
                    },
                  )),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// P10.9 — Schedule a debounced save of the current session state.
  /// Reads the camera position from the MapController + the current
  /// selection / timeline year / focus mode / expanded household.
  void _scheduleStateSave() {
    final saver = _stateSaver;
    final controller = _mapController;
    if (saver == null || controller == null) return;
    final cam = controller.camera;
    final journeyState = ref.read(journeyProvider);
    final state = MapSessionState(
      lat: cam?.center.lat ?? 20.5937,
      lng: cam?.center.lon ?? 78.9629,
      zoom: cam?.zoom ?? 4.0,
      pitch: cam?.pitch ?? 0.0,
      bearing: cam?.bearing ?? 0.0,
      selectedPersonId: _selectedPinId,
      timelineYear: journeyState.selectedYear,
      isFocusMode: _selectedPinId != null,
      expandedHouseholdId: _expandedHouseholdId,
    );
    saver.schedule(state);
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

// ═══════════════════════════════════════════════════════════════════════
// P10.5 — RELATIONSHIP PATH OVERLAY (Flutter overlay fallback)
// ═══════════════════════════════════════════════════════════════════════
//
// Renders relationship edges as a Flutter CustomPainter overlay because
// maplibre 0.3.5 does not expose setPaintProperty (Rule 12 fallback).
// Reads pin screen positions from the MapController on every repaint
// triggered by the [progressNotifier].

class _RelationshipPathOverlay extends StatefulWidget {
  const _RelationshipPathOverlay({
    required this.mapController,
    required this.edges,
    required this.pins,
    required this.progressNotifier,
    required this.reducedMotion,
  });

  final MapController? mapController;
  final List<MapRelationshipEdge> edges;
  final List<MapPin> pins;
  final ValueNotifier<int> progressNotifier;
  final bool reducedMotion;

  @override
  State<_RelationshipPathOverlay> createState() =>
      _RelationshipPathOverlayState();
}

class _RelationshipPathOverlayState extends State<_RelationshipPathOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Map<String, Offset> _screenPositions = {};

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final controller = widget.mapController;
    if (controller == null) return;
    bool changed = false;
    for (final pin in widget.pins) {
      try {
        final screen =
            controller.toScreenLocation(Geographic(lon: pin.lng, lat: pin.lat));
        if (_screenPositions[pin.personId] != screen) {
          _screenPositions[pin.personId] = screen;
          changed = true;
        }
      } catch (_) {
        // ignore
      }
    }
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RelationshipPathPainter(
          edges: widget.edges,
          screenPositions: _screenPositions,
          progress: widget.reducedMotion
              ? 0.0
              : (DateTime.now().millisecondsSinceEpoch %
                      MapVisualConstants.relationshipFlowCycle.inMilliseconds)
                  .toDouble() /
                  MapVisualConstants.relationshipFlowCycle.inMilliseconds,
          repaintNotifier: widget.progressNotifier,
        ),
      ),
    );
  }
}

class _RelationshipPathPainter extends CustomPainter {
  _RelationshipPathPainter({
    required this.edges,
    required this.screenPositions,
    required this.progress,
    required this.repaintNotifier,
  }) : super(repaint: repaintNotifier);

  final List<MapRelationshipEdge> edges;
  final Map<String, Offset> screenPositions;
  final double progress;
  final ValueNotifier<int> repaintNotifier;

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty || screenPositions.length < 2) return;
    for (final edge in edges) {
      final a = screenPositions[edge.pinA.personId];
      final b = screenPositions[edge.pinB.personId];
      if (a == null || b == null) continue;
      _drawEdge(canvas, edge, a, b);
    }
  }

  void _drawEdge(Canvas canvas, MapRelationshipEdge edge, Offset a, Offset b) {
    final category = categorizeRelationship(edge.relationshipKey);
    final style = PathStyle.forCategory(category);
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round;

    if (style.dashed) {
      _drawDashedLine(canvas, a, b, paint);
    } else {
      canvas.drawLine(a, b, paint);
    }

    if (style.showHeartMidpoint) {
      final mid = (a + b) / 2;
      final path = HeartShape.buildPath(center: mid, width: 14, height: 14);
      canvas.drawPath(
        path,
        Paint()
          ..color = KinrelColors.orange
          ..style = ui.PaintingStyle.fill,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashWidth = 6.0;
    const dashGap = 4.0;
    final total = dashWidth + dashGap;
    final distance = (b - a).distance;
    if (distance == 0) return;
    final count = (distance / total).floor();
    final dir = (b - a) / distance;
    for (var i = 0; i < count; i++) {
      final start = a + dir * (i * total);
      final end = start + dir * dashWidth;
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RelationshipPathPainter old) =>
      old.progress != progress || old.edges != edges;
}

// ═══════════════════════════════════════════════════════════════════════
// P10.4 — HOUSEHOLD CLUSTER OVERLAY
// ═══════════════════════════════════════════════════════════════════════
//
// Renders HouseholdClusterMarkerWidget for each multi-member household,
// positioned via MapController.toScreenLocation on every frame.

class _HouseholdClusterOverlay extends StatefulWidget {
  const _HouseholdClusterOverlay({
    required this.mapController,
    required this.households,
    required this.expandedHouseholdId,
    required this.reducedMotion,
    required this.onClusterTap,
    required this.onClusterLongPress,
  });

  final MapController? mapController;
  final List<Household> households;
  final String? expandedHouseholdId;
  final bool reducedMotion;
  final void Function(Household) onClusterTap;
  final void Function(Household) onClusterLongPress;

  @override
  State<_HouseholdClusterOverlay> createState() =>
      _HouseholdClusterOverlayState();
}

class _HouseholdClusterOverlayState extends State<_HouseholdClusterOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Map<String, Offset> _positions = {};

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final controller = widget.mapController;
    if (controller == null) return;
    bool changed = false;
    for (final h in widget.households) {
      try {
        final screen =
            controller.toScreenLocation(Geographic(lon: h.lng, lat: h.lat));
        if (_positions[h.id] != screen) {
          _positions[h.id] = screen;
          changed = true;
        }
      } catch (_) {
        // ignore
      }
    }
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final h in widget.households)
          _buildPositioned(h),
      ],
    );
  }

  Widget _buildPositioned(Household h) {
    final pos = _positions[h.id];
    if (pos == null) return const SizedBox.shrink();
    final size = MapVisualConstants.clusterMarkerSize;
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      child: HouseholdClusterMarkerWidget(
        household: h,
        reducedMotion: widget.reducedMotion,
        onTap: () => widget.onClusterTap(h),
        onLongPress: () => widget.onClusterLongPress(h),
      ),
    );
  }
}

