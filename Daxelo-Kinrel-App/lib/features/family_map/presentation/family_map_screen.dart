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
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/utils/device_tier.dart';
import '../../../graph/interaction/graph_focus_state.dart';
import '../../family_journey/providers/journey_provider.dart';
import '../config/map_visual_constants.dart';
import '../widgets/family_building_layer.dart';
import '../widgets/avatar_marker_overlay.dart';
import '../widgets/animated_relationship_path.dart';
import '../widgets/map_focus_controller.dart';
import '../widgets/map_timeline_scrubber.dart';
import '../widgets/family_journey_animation.dart';
import '../widgets/map_polish_overlay.dart';
import '../widgets/map_skeleton.dart';
import '../data/family_map_lifecycle.dart';
import '../data/map_state_persistence.dart';
import '../data/poi_filter.dart';
import '../data/progressive_loading.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/family_map_provider.dart';
import '../providers/live_location_provider.dart';
import '../widgets/household_cluster_overlay.dart';
import '../widgets/map_bottom_sheets.dart';
import '../widgets/map_legend_widget.dart';
import '../widgets/relationship_path_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════
// FAMILY MAP SCREEN
// ═══════════════════════════════════════════════════════════════════════

class FamilyMapScreen extends ConsumerStatefulWidget {
  const FamilyMapScreen({
    super.key,
    required this.familyId,
  });

  /// The family whose members + places are rendered on the map.
  /// Required — the map screen no longer falls back to
  /// `familyListProvider.first`. Callers (route + navigation push)
  /// MUST supply a concrete familyId.
  final String familyId;

  @override
  ConsumerState<FamilyMapScreen> createState() => _FamilyMapScreenState();
}

class _FamilyMapScreenState extends ConsumerState<FamilyMapScreen>
    with TickerProviderStateMixin {
  MapController? _mapController;

  /// RENDERER CAPABILITY FLAG — true once the map style has loaded.
  /// Used ONLY to gate overlay rendering in build() (e.g.
  /// `if (_styleLoaded && filteredPins.isNotEmpty)`). Do NOT use for
  /// lifecycle decisions — the authoritative lifecycle is [_lifecycle].
  bool _styleLoaded = false;

  /// §12 — Rendezvous: stored callback results from onMapCreated +
  /// onStyleLoaded. Both must arrive before [_tryPrepareMapLayers]
  /// runs. Eliminates the race where onStyleLoaded fires before
  /// onMapCreated (or vice versa) and bails out, relying solely on
  /// the watchdog.
  MapController? _rendezvousController;
  StyleController? _rendezvousStyle;

  /// §12 — Idempotency guard for [_tryPrepareMapLayers]. Reset on
  /// retry / family-switch so a new attempt can prepare layers again.
  bool _layersPrepared = false;

  FamilyMapResult? _lastResult;
  Timer? _broadcastTimer;
  Timer? _dbUpsertTimer;
  DateTime? _lastDbUpsert;

  /// ── AUTHORITATIVE LIFECYCLE ────────────────────────────────────────
  /// Replaces the fragile multi-boolean lifecycle (`_styleLoaded` +
  /// `_loadState.phase` + `_entranceAnimationDone`)
  /// with a single state machine that the screen watches.
  ///
  /// INVARIANTS:
  ///   • Every initialization attempt MUST end in `ready`, `empty`, or
  ///     `failed` — never in `initializing` / `loadingStyle` /
  ///     `preparingLayers` forever.
  ///   • 0 members located → `empty` (NOT a loading state). The base
  ///     map is fully interactive.
  ///   • A bounded watchdog (8 seconds) forces `loadingStyle → ready`
  ///     even if `onStyleLoaded` never fires (maplibre 0.3.5 web bug).
  ///   • Optional premium-layer failures are logged + skipped — they
  ///     cannot keep the loader visible.
  final FamilyMapLifecycleController _lifecycle =
      FamilyMapLifecycleController();

  /// Watchdog timer that forces `loadingStyle → ready/empty` if
  /// `onStyleLoaded` never fires. Started when the MapLibreMap widget
  /// is first mounted. Cancelled in `dispose()` and when the lifecycle
  /// reaches a terminal state.
  Timer? _styleWatchdog;

  /// P10.2 — Family buildings (semantic types + emotional lighting).
  /// Initialized on first style load; updated whenever familyMapProvider
  /// emits a new place list.
  final FamilyBuildingLayer _familyBuildings = FamilyBuildingLayer();

  /// P11.x — Family Building Animation Engine.
  /// Drives the per-type glow animations (wedding pulse, memorial flicker,
  /// temple pulse, ancestral breathing) per master prompt Phase 3.
  FamilyBuildingAnimationEngine? _buildingAnimEngine;

  /// P11.x — Current camera pitch (degrees), tracked on camera move events.
  /// Drives the atmospheric perspective overlay opacity (linear fade
  /// top-down when pitch > 10° per master prompt).
  double _currentPitch = 0.0;

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
  ///
  /// COSMETIC PROGRESS INDICATOR (acknowledged secondary). The primary
  /// lifecycle is [_lifecycle]. The progressive phases only matter once
  /// the lifecycle has reached `preparingLayers` or beyond — they
  /// describe the progress of OPTIONAL premium layer attachment, not
  /// map readiness. Do NOT use for lifecycle decisions.
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

  /// ONE-SHOT ANIMATION state — true once the cinematic entrance
  /// camera animation has been triggered. Reset to false on
  /// family-switch so a new family gets its own entrance. Do NOT use
  /// for lifecycle decisions.
  bool _entranceAnimationDone = false;

  /// P10.5 — Trigger for relationship path overlay repaint. Bumped by
  /// the AnimatedRelationshipPath on each animation tick.
  final ValueNotifier<int> _pathRepaintNotifier = ValueNotifier<int>(0);

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

  /// WEB-SPECIFIC STYLE PATH.
  ///
  /// §8 — WEB STYLE CONSISTENCY: web and native now share the SAME
  /// bundled Kinrel dark style (`assets/map_styles/kinrel_dark_style.json`)
  /// so the map looks identical on every platform.
  ///
  /// On Flutter Web, the maplibre 0.3.5 web plugin's
  /// `_prepareStyleString` checks the style string prefix:
  ///   • starts with '{' → inline JSON (parsed + jsified — slow for 6k-line styles)
  ///   • starts with '/' → file path
  ///   • starts with 'http' → URL (passed through as-is)
  ///   • everything else → Flutter asset (resolved via `AssetManager`)
  ///
  /// Passing the relative asset path (`assets/map_styles/...`, no
  /// leading slash) makes the plugin fall into the "Flutter asset"
  /// branch, which calls `AssetManager().getAssetUrl()` to resolve it
  /// to a proper URL — typically `assets/assets/map_styles/...` (the
  /// double `assets` is intentional: the first is the web asset root,
  /// the second is the pubspec asset prefix). MapLibre GL JS then
  /// fetches the JSON natively, avoiding the dart→JS interop cost of
  /// inline JSON.
  ///
  /// POI FILTERING CAVEAT: the asset path bypasses the runtime
  /// `applyPoiFilters` patching that native uses (we can't easily
  /// rewrite a URL-served style). The bundled `kinrel_dark_style.json`
  /// already has the POI layers curated, so the visual difference is
  /// minimal — but if POI filtering tuning changes in
  /// `poi_filter.dart`, the bundled JSON should be regenerated to
  /// match. See `data/poi_filter.dart` for the filter rules.
  ///
  /// The family-places source + family-buildings layers are still
  /// added programmatically in [_onStyleLoaded] via
  /// [_ensureFamilyPlacesLayers] — they're not in the source style.
  static const _kWebStylePath = 'assets/map_styles/kinrel_dark_style.json';

  /// Light "Snapchat-style" map style URL — OpenFreeMap liberty is a
  /// clean, light, social-friendly style that matches the Snapchat map
  /// aesthetic: white background, pastel water, light parks, clean roads.
  /// Family-building layers are added programmatically after style load.
  static const _kLightStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  /// Whether the user has selected light map theme. Loaded from
  /// SharedPreferences in initState. Toggled via the AppBar sun/moon button.
  bool _isLightMap = false;

  /// RENDERER CAPABILITY FLAG — idempotency guard for
  /// [_ensureFamilyPlacesLayers]. True once the family-places source +
  /// family-buildings layers have been added to the current style.
  /// Reset to false on retry. Do NOT use for lifecycle decisions —
  /// the authoritative lifecycle is [_lifecycle].
  bool _familyPlacesLayersAdded = false;

  /// P12.2 — idempotency guard for the live-location ambient glow
  /// source + layer. True once [live-location-point] source +
  /// [live-location-ambient-glow] layer have been added.
  /// Reset to false on family switch.
  bool _liveLocationGlowAdded = false;

  /// P12.2 — the current user's last captured lat/lng (null until the
  /// first successful _captureAndBroadcast). Drives the
  /// [live-location-point] GeoJSON source for the ambient ground glow.
  double? _liveLocationLat;
  double? _liveLocationLng;

  /// Loads the map style. Strategy:
  ///   • LIGHT MODE (Snapchat-style): use OpenFreeMap liberty style URL.
  ///     Clean, light, social — white base, pastel water, light parks.
  ///     Family-buildings layers added programmatically after load.
  ///   • DARK MODE (Kinrel premium): use the bundled kinrel_dark_style.json.
  ///     Dark, cinematic, immersive — matches the rest of the Kinrel app.
  ///     Family-buildings layers are already in the JSON.
  ///   • WEB: both modes pass the style path/URL to the maplibre plugin
  ///     which resolves it natively (no dart→JS interop).
  ///   • NATIVE: dark mode loads the bundled JSON via rootBundle;
  ///     light mode passes the URL directly to MapLibre.
  Future<String> _loadStyleJson() async {
    if (_loadedStyleJson != null) return _loadedStyleJson!;

    if (_isLightMap) {
      // ── LIGHT MODE: Snapchat-style ───────────────────────────────
      debugPrint('☀️ FamilyMap: using light Snapchat-style: $_kLightStyleUrl');
      _loadedStyleJson = _kLightStyleUrl;
      return _loadedStyleJson!;
    }

    // ── DARK MODE: Kinrel premium ─────────────────────────────────
    if (kIsWeb) {
      debugPrint('🌙 FamilyMap: using bundled Kinrel dark style as web asset: '
          '$_kWebStylePath');
      _loadedStyleJson = _kWebStylePath;
      return _loadedStyleJson!;
    }

    // Native dark mode: load bundled JSON + apply POI filters
    try {
      final raw = await rootBundle
          .loadString(_kStyleAssetPath)
          .timeout(const Duration(seconds: 10));
      _loadedStyleJson = applyPoiFilters(raw);
    } catch (e) {
      debugPrint('⚠️ _loadStyleJson failed, using inline fallback: $e');
      _loadedStyleJson = _kFallbackStyleJson;
    }
    return _loadedStyleJson!;
  }

  /// Toggles between dark and light map themes. Clears the cached style
  /// so _loadStyleJson re-fetches with the new theme. Resets the
  /// family-places layers flag so they get re-added for the new style.
  void _toggleMapTheme() {
    setState(() {
      _isLightMap = !_isLightMap;
      _loadedStyleJson = null;
      _familyPlacesLayersAdded = false;
      _liveLocationGlowAdded = false;
      _liveLocationLat = null;
      _liveLocationLng = null;
      _styleLoaded = false;
      _lifecycle.reset();
      // Persist the preference
      _saveMapThemePreference(_isLightMap);
    });
  }

  /// Saves the map theme preference to SharedPreferences.
  void _saveMapThemePreference(bool isLight) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('family_map_light_theme', isLight);
    } catch (e) {
      debugPrint('⚠️ Failed to save map theme preference: $e');
    }
  }

  /// Loads the map theme preference from SharedPreferences.
  Future<void> _loadMapThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLightMap = prefs.getBool('family_map_light_theme') ?? false;
    } catch (e) {
      debugPrint('⚠️ Failed to load map theme preference: $e');
    }
  }

  /// Ensures the family-places GeoJSON source + family-buildings layers
  /// exist in the current style. Called from [_onStyleLoaded].
  ///
  /// §8 — Web style consistency: now that web uses the bundled Kinrel
  /// style (same as native), these layers are ALREADY in the style JSON
  /// on BOTH platforms — this method is effectively a no-op. The
  /// addSource/addLayer calls are still attempted (idempotently) so
  /// that any environment where the source layers are missing (e.g. a
  /// hand-edited style, or a future style swap) still gets them added.
  ///
  /// Historically (pre-§8), web used the OpenFreeMap dark style URL
  /// which did NOT include the family-* layers — they had to be added
  /// programmatically here. The implementation was kept idempotent so
  /// it continues to work whether or not the layers are already
  /// present.
  ///
  /// When layers ARE already present, the addSource/addLayer calls
  /// throw — each is wrapped in its own try/catch so a duplicate-add
  /// is logged + skipped (non-fatal). The method:
  ///   1. Adds the `family-places` GeoJSON source (empty FeatureCollection)
  ///   2. Adds the `family-buildings-glow` circle layer (minzoom 10)
  ///   3. Adds the `family-buildings` fill-extrusion layer (minzoom 13)
  ///   4. Adds the `family-buildings-fallback` circle layer (maxzoom 13)
  ///
  /// All layers use a `match` expression on the `placeType` property for
  /// per-type emotional lighting. Idempotent — safe to call multiple times.
  Future<void> _ensureFamilyPlacesLayers(StyleController style) async {
    if (_familyPlacesLayersAdded) return;
    try {
      // Add the family-places source (empty — populated by
      // FamilyBuildingLayer.add/update).
      try {
        await style.addSource(GeoJsonSource(
          id: FamilyBuildingLayer.sourceId,
          data: '{"type":"FeatureCollection","features":[]}',
        ));
        debugPrint('✅ FamilyMap: added family-places source (web)');
      } catch (e) {
        // Source may already exist — that's fine.
        debugPrint('ℹ️ FamilyMap: family-places source already exists: $e');
      }

      // Add the three family-buildings layers. We use addLayer with
      // raw paint properties — the maplibre 0.3.5 API accepts a generic
      // map for paint/layout.
      // Note: the match expression uses the same hex colors as the
      // bundled style JSON (single source of truth = MapVisualConstants).
      final matchExpr = <Object>[
        'match',
        <String>['get', 'placeType'],
        'current_home', MapVisualConstants.hexBuildingCurrentHome,
        'childhood_home', MapVisualConstants.hexBuildingChildhoodHome,
        'ancestral_home', MapVisualConstants.hexBuildingAncestralHome,
        'birthplace', MapVisualConstants.hexBuildingBirthplace,
        'wedding', MapVisualConstants.hexBuildingWedding,
        'memorial', MapVisualConstants.hexBuildingMemorial,
        'family_business', MapVisualConstants.hexBuildingFamilyBusiness,
        'school', MapVisualConstants.hexBuildingSchool,
        'important_place', MapVisualConstants.hexBuildingImportantPlace,
        MapVisualConstants.hexBuildingImportantPlace, // default
      ];

      // Glow layer (circle, minZoom 10)
      try {
        await style.addLayer(CircleStyleLayer(
          id: FamilyBuildingLayer.glowLayerId,
          sourceId: FamilyBuildingLayer.sourceId,
          minZoom: 10,
          paint: {
            'circle-color': matchExpr,
            'circle-radius': 24,
            'circle-blur': 1.0,
            'circle-opacity': 0.65,
          },
        ));
        debugPrint('✅ FamilyMap: added family-buildings-glow layer (web)');
      } catch (e) {
        debugPrint('ℹ️ FamilyMap: glow layer already exists: $e');
      }

      // Extrusion layer (fill-extrusion, minZoom 13)
      try {
        await style.addLayer(FillExtrusionStyleLayer(
          id: FamilyBuildingLayer.extrusionLayerId,
          sourceId: FamilyBuildingLayer.sourceId,
          minZoom: 13,
          paint: {
            'fill-extrusion-color': matchExpr,
            'fill-extrusion-height': ['coalesce', ['get', 'height'], 12],
            'fill-extrusion-base': 0,
            'fill-extrusion-opacity': 0.95,
            'fill-extrusion-vertical-gradient': true,
          },
        ));
        debugPrint('✅ FamilyMap: added family-buildings layer (web)');
      } catch (e) {
        debugPrint('ℹ️ FamilyMap: extrusion layer already exists: $e');
      }

      // Fallback circle layer (maxZoom 13)
      try {
        await style.addLayer(CircleStyleLayer(
          id: FamilyBuildingLayer.circleFallbackLayerId,
          sourceId: FamilyBuildingLayer.sourceId,
          maxZoom: 13,
          paint: {
            'circle-color': matchExpr,
            'circle-radius': 6,
            'circle-stroke-color': '#FFFFFF',
            'circle-stroke-width': 1,
            'circle-opacity': 0.9,
          },
        ));
        debugPrint('✅ FamilyMap: added family-buildings-fallback layer (web)');
      } catch (e) {
        debugPrint('ℹ️ FamilyMap: fallback layer already exists: $e');
      }

      _familyPlacesLayersAdded = true;
    } catch (e) {
      debugPrint('⚠️ FamilyMap: _ensureFamilyPlacesLayers failed: $e');
      // Non-fatal — the base map still works without family-buildings.
    }
  }

  /// P12.2 — Ensures the [live-location-point] GeoJSON source +
  /// [live-location-ambient-glow] CircleLayer exist in the current style.
  ///
  /// The ambient glow is a large, soft, low-opacity circle painted at
  /// the current user's location — creates the "lit pool" effect from
  /// the Snap Map reference, in Kinrel's teal accent (livePulseRingColor)
  /// so it reads as "you are here, live" against the warm orange family
  /// beacons.
  ///
  /// Idempotent — safe to call multiple times. The source is added
  /// empty here; [_updateLiveLocationPoint] populates it when the
  /// first GPS capture arrives.
  Future<void> _ensureLiveLocationGlow(StyleController style) async {
    if (_liveLocationGlowAdded) return;
    try {
      // 1. Add the live-location-point source (empty — populated by
      // _updateLiveLocationPoint).
      try {
        await style.addSource(GeoJsonSource(
          id: 'live-location-point',
          data: '{"type":"FeatureCollection","features":[]}',
        ));
        debugPrint('✅ FamilyMap: added live-location-point source');
      } catch (e) {
        debugPrint('ℹ️ FamilyMap: live-location-point source already exists: $e');
      }

      // 2. Add the ambient glow layer. Large, soft, teal-tinted circle
      // that scales with zoom (40px at zoom 10 → 150px at zoom 16).
      // Uses MapVisualConstants.livePulseRingColor (#4ED9C7) for the
      // cool "live presence" contrast against warm family beacons.
      try {
        await style.addLayer(CircleStyleLayer(
          id: 'live-location-ambient-glow',
          sourceId: 'live-location-point',
          minZoom: 8,
          paint: {
            'circle-color': '#4ED9C7', // MapVisualConstants.livePulseRingColor
            'circle-radius': [
              'interpolate', ['linear'], ['zoom'],
              10, 40,
              16, 150,
            ],
            'circle-blur': 1.2,
            'circle-opacity': 0.22,
          },
        ));
        debugPrint('✅ FamilyMap: added live-location-ambient-glow layer');
      } catch (e) {
        debugPrint('ℹ️ FamilyMap: live-location-ambient-glow layer already exists: $e');
      }

      _liveLocationGlowAdded = true;
    } catch (e) {
      debugPrint('⚠️ FamilyMap: _ensureLiveLocationGlow failed: $e');
      // Non-fatal — the base map still works without the ambient glow.
    }
  }

  /// P12.2 — Updates the [live-location-point] GeoJSON source with the
  /// current user's lat/lng. Called from [_captureAndBroadcast] after a
  /// successful GPS capture. No-op if the source hasn't been added yet
  /// or if the position is null.
  Future<void> _updateLiveLocationPoint() async {
    if (!_liveLocationGlowAdded) return;
    final lat = _liveLocationLat;
    final lng = _liveLocationLng;
    if (lat == null || lng == null) return;
    final style = _mapController?.style;
    if (style == null) return;
    try {
      final geojson = '{"type":"FeatureCollection","features":['
          '{"type":"Feature","geometry":{"type":"Point","coordinates":[$lng,$lat]},'
          '"properties":{"kind":"live-location"}}'
          ']}';
      await style.updateGeoJsonSource(id: 'live-location-point', data: geojson);
    } catch (e) {
      debugPrint('⚠️ FamilyMap: _updateLiveLocationPoint failed: $e');
    }
  }

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
    },
    "live-location-point": {
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
    {"id":"live-location-ambient-glow","type":"circle","source":"live-location-point","minzoom":8,"paint":{"circle-color":"#4ED9C7","circle-radius":["interpolate",["linear"],["zoom"],10,40,16,150],"circle-blur":1.2,"circle-opacity":0.22}},
    {"id":"family-buildings-glow","type":"circle","source":"family-places","minzoom":10,"paint":{"circle-color":["match",["get","placeType"],"current_home","#E8612A","childhood_home","#F59240","ancestral_home","#917520","birthplace","#F5B841","wedding","#E8612A","memorial","#F59240","family_business","#C44A18","school","#4E6984","important_place","#E8612A","#E8612A"],"circle-radius":24,"circle-blur":1.0,"circle-opacity":0.65}},
    {"id":"family-buildings","type":"fill-extrusion","source":"family-places","minzoom":13,"paint":{"fill-extrusion-color":["match",["get","placeType"],"current_home","#E8612A","childhood_home","#F59240","ancestral_home","#917520","birthplace","#F5B841","wedding","#E8612A","memorial","#F59240","family_business","#C44A18","school","#4E6984","important_place","#E8612A","#E8612A"],"fill-extrusion-height":["coalesce",["get","height"],12],"fill-extrusion-base":0,"fill-extrusion-opacity":0.95,"fill-extrusion-vertical-gradient":true}},
    {"id":"family-buildings-fallback","type":"circle","source":"family-places","maxzoom":13,"paint":{"circle-color":["match",["get","placeType"],"current_home","#E8612A","childhood_home","#F59240","ancestral_home","#917520","birthplace","#F5B841","wedding","#E8612A","memorial","#F59240","family_business","#C44A18","school","#4E6984","important_place","#E8612A","#E8612A"],"circle-radius":6,"circle-stroke-color":"#FFFFFF","circle-stroke-width":1,"circle-opacity":0.9}}
  ]
}
''';

  @override
  void initState() {
    super.initState();
    // Start the live location provider when the map screen mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final familyId = widget.familyId;
      if (familyId.isNotEmpty) {
        ref.read(liveLocationProvider.notifier).start(familyId);
        // P10.9 — initialize the debounced state saver for this family.
        _stateSaver = DebouncedMapStateSaver(familyId);
        // P10.9 — Load saved session state (camera, selection, timeline
        // year, focus mode, expanded household). On load, the screen
        // restores the camera + selection + timeline year. Gracefully
        // returns null on first launch / corrupted JSON.
        MapStatePersistence.load(familyId).then((state) {
          if (!mounted) return;
          // Guard against stale result from a previous family
          // (if didUpdateWidget changed the family before this completes).
          if (widget.familyId != familyId) return;
          if (state != null) {
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

    // ── CRITICAL: Load map theme preference BEFORE style ────────────
    // The theme preference (dark/light) must be loaded before _loadStyleJson
    // so the correct style is fetched on the first render.
    _loadMapThemePreference().then((_) {
      if (!mounted) return;
      _loadStyleJson().then((style) {
        if (mounted) {
          debugPrint('✅ FamilyMap: style loaded in initState '
              '(${style.length} chars, web=$kIsWeb, light=$_isLightMap)');
          _lifecycle.transition(
            FamilyMapLifecycle.loadingStyle,
            attempt: _lifecycle.currentAttempt,
          );
          setState(() {});
        }
      }).catchError((e) {
        if (mounted) {
          debugPrint('❌ FamilyMap: style load failed in initState: $e');
          _lifecycle.transition(
            FamilyMapLifecycle.failed,
            attempt: _lifecycle.currentAttempt,
          );
          setState(() {});
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant FamilyMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) {
      // Family changed — flush old saver, stop old live location,
      // clear stale state, re-initialize for new family.
      _stopBroadcastLoop();
      _stateSaver?.flushNow();
      _stateSaver?.dispose();
      _stateSaver = null;
      ref.read(liveLocationProvider.notifier).stop();

      // Clear stale selection/journey state
      _selectedPinId = null;
      _expandedHouseholdId = null;
      _journeyStops = null;
      _restoredState = null;
      _entranceAnimationDone = false;

      // Reset lifecycle for the new family
      _lifecycle.reset();
      _styleLoaded = false;
      // §12 — reset rendezvous state so the new attempt re-prepares.
      _rendezvousController = null;
      _rendezvousStyle = null;
      _layersPrepared = false;
      _familyPlacesLayersAdded = false;
      _liveLocationGlowAdded = false;
      _liveLocationLat = null;
      _liveLocationLng = null;
      _loadedStyleJson = null;

      // Start live location + persistence for the new family
      if (widget.familyId.isNotEmpty) {
        final loadedFamilyId = widget.familyId;
        ref.read(liveLocationProvider.notifier).start(loadedFamilyId);
        _stateSaver = DebouncedMapStateSaver(loadedFamilyId);
        MapStatePersistence.load(loadedFamilyId).then((state) {
          if (!mounted) return;
          if (widget.familyId != loadedFamilyId) return; // stale — family changed again
          if (state != null && mounted) {
            setState(() {
              _restoredState = state;
              _selectedPinId = state.selectedPersonId;
              _expandedHouseholdId = state.expandedHouseholdId;
              if (state.timelineYear != null) {
                ref.read(journeyProvider.notifier).setYear(state.timelineYear!);
              }
            });
          }
        });
      }

      setState(() {});
    }
  }

  @override
  void dispose() {
    _stopBroadcastLoop();
    _styleWatchdog?.cancel();
    _lifecycle.dispose();
    _buildingAnimEngine?.dispose();
    _familyBuildings.dispose();
    _avatarLayer.cache.clear();
    _relationshipPaths?.dispose();
    _pathRepaintNotifier.dispose();
    // P10.9 — flush any pending state save before tearing down.
    _stateSaver?.flushNow();
    _stateSaver?.dispose();
    ref.read(liveLocationProvider.notifier).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(familyMapProvider(widget.familyId));

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
          tooltip: S.of(context)?.familyMapBack ?? 'Back',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context)?.familyMapTitle ?? 'Family Map',
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
                final l10n = S.of(context);
                return Text(
                  l10n?.familyMapLocatedCount(locatedCount) ??
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
                S.of(context)?.familyMapLoading ?? 'Loading...',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
              error: (_, __) => Text(
                S.of(context)?.familyMapFailedTitle ?? 'Unable to load',
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
          // Map theme toggle — dark (Kinrel premium) ↔ light (Snapchat-style)
          IconButton(
            icon: Icon(
              _isLightMap ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 22,
            ),
            tooltip: _isLightMap ? 'Dark map' : 'Light map',
            onPressed: _toggleMapTheme,
          ),
          // Dev test: fly to Bengaluru at zoom 16, tilt 45° to verify 3D
          // buildings. Debug builds only — never shipped to production.
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.location_city, size: 20),
              tooltip:
                  S.of(context)?.familyMapTest3dBengaluru ?? 'Test 3D: Bengaluru',
              onPressed: _flyToBengaluru3D,
            ),
        ],
      ),
      body: mapAsync.when(
        // §7 — PROGRESSIVE DATA DELIVERY: render the map shell
        // IMMEDIATELY with an empty FamilyMapResult while
        // `familyMapProvider` is still resolving members + places +
        // relationships. The map SHELL (MapLibreMap widget) only needs
        // the style JSON to render — family data is used purely for
        // overlays (pins, edges, places). By calling `_buildMap` with
        // an empty result here, the user sees the interactive base map
        // right away, and the pins/edges/places appear as overlays the
        // moment `familyMapProvider` resolves (the `data:` branch
        // below). The maplibre lifecycle is unaffected — `_styleLoaded`
        // gates every overlay, so an empty result simply renders a
        // bare map. `_buildMap` is also responsible for showing the
        // style-loading skeleton when `_loadedStyleJson == null`, so
        // the style-JSON fetch (the only thing that should block the
        // map shell) is still surfaced to the user via [MapSkeleton].
        loading: () => _buildMap(const FamilyMapResult(
          pins: [],
          unpinnedMembers: [],
          unpinnedCount: 0,
          edges: [],
          familyId: '',
        )),
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

  /// Skeleton shown while the style JSON is loading (lifecycle ==
  /// `initializing`). Uses the localized "Loading family map…" message
  /// so the user knows what's happening — not a bare spinner.
  Widget _buildMapSkeleton() {
    final l10n = S.of(context);
    return MapSkeleton(
      reducedMotion: MediaQuery.disableAnimationsOf(context),
      message: l10n?.familyMapLoading ?? 'Loading family map…',
    );
  }

  /// Error UI shown when the style JSON fails to load (lifecycle ==
  /// `failed`). Provides a Retry button that resets the lifecycle and
  /// re-fetches.
  Widget _buildStyleLoadError() {
    final l10n = S.of(context);
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
                  l10n?.familyMapFailedTitle ?? 'Could not load the family map.',
                  style: TextStyle(
                    color: KinrelColors.textWhite,
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n?.familyMapFailedBody ?? 'Check your connection and try again.',
                  style: TextStyle(
                    color: KinrelColors.textDim,
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _retryInitialization,
                  style: FilledButton.styleFrom(
                    backgroundColor: KinrelColors.orange,
                  ),
                  child: Text(l10n?.familyMapRetry ?? 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact, non-blocking empty-state overlay shown when the lifecycle
  /// is `empty` (0 located members). The base map is fully interactive
  /// underneath — this overlay just nudges the user to add a location.
  Widget _buildEmptyStateOverlay() {
    final l10n = S.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: KinrelSpacing.base,
      right: KinrelSpacing.base,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard.withOpacity(0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KinrelColors.darkElevated),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_rounded,
                  color: KinrelColors.orange, size: 24),
              const SizedBox(height: 8),
              Text(
                l10n?.familyMapEmptyTitle ?? 'No family locations yet',
                style: TextStyle(
                  color: KinrelColors.textWhite,
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                l10n?.familyMapEmptyBody ??
                    'Add a location to a family member to see your family across the map.',
                style: TextStyle(
                  color: KinrelColors.textSilver,
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Retry handler — clears cached state and resets the lifecycle so a
  /// fresh initialization attempt runs. The previous attempt's stale
  /// callbacks are invalidated by the lifecycle's attempt-ID increment.
  void _retryInitialization() {
    debugPrint('🔄 FamilyMap: retry requested — resetting lifecycle');
    // Cancel any pending watchdog.
    _styleWatchdog?.cancel();
    _styleWatchdog = null;
    // Clear cached style so _loadStyleJson re-fetches from the asset.
    _loadedStyleJson = null;
    // Reset the family-places-layers flag so _ensureFamilyPlacesLayers
    // re-adds them when the new style loads.
    _familyPlacesLayersAdded = false;
    // P12.2 — reset live-location glow flag + position too.
    _liveLocationGlowAdded = false;
    _liveLocationLat = null;
    _liveLocationLng = null;
    // Reset the _styleLoaded flag so the new attempt's _onStyleLoaded
    // runs the full initialization.
    _styleLoaded = false;
    // §12 — reset rendezvous state so the new attempt re-prepares.
    _rendezvousController = null;
    _rendezvousStyle = null;
    _layersPrepared = false;
    // Reset lifecycle — this increments the attempt ID, invalidating
    // any in-flight callbacks from the previous attempt.
    _lifecycle.reset();
    // Trigger a rebuild — the FutureBuilder will re-execute
    // _loadStyleJson() because _loadedStyleJson is null again.
    setState(() {});
  }

  /// Called when the MapLibreMap widget is first mounted — starts the
  /// watchdog that forces `loadingStyle → ready/empty` if `onStyleLoaded`
  /// never fires (maplibre 0.3.5 web plugin has a known bug where the
  /// callback is not invoked for inline JSON styles).
  ///
  /// Two-phase watchdog:
  ///   • Phase 1 (5s): if `_mapController` is still null, the JsMap
  ///     constructor threw (WebGL failure, maplibre-gl.js not loaded,
  ///     CSP block). Transition to `failed` — the map widget itself
  ///     is broken, not just the style.
  ///   • Phase 2 (10s): if `_mapController` exists but `onStyleLoaded`
  ///     never fired, the style failed to load (network error, parse
  ///     error). Force the lifecycle to `ready`/`empty` — the base map
  ///     div exists even if the style is broken; the user can still
  ///     see the dark background + empty-state overlay.
  void _startStyleWatchdog({required int attempt}) {
    _styleWatchdog?.cancel();

    // Phase 1: 5-second controller-null check.
    Timer(const Duration(seconds: 5), () {
      if (attempt != _lifecycle.currentAttempt) return;
      if (_lifecycle.state.isTerminal) return;
      if (_mapController == null) {
        debugPrint('❌ FamilyMap: MapController still null after 5s — '
            'JsMap constructor likely threw (WebGL/maplibre-gl.js failure). '
            'Transitioning to failed.');
        _lifecycle.transition(
          FamilyMapLifecycle.failed,
          attempt: attempt,
        );
        _styleWatchdog?.cancel();
        _styleWatchdog = null;
      }
    });

    // Phase 2: 10-second style-loaded check.
    _styleWatchdog = Timer(const Duration(seconds: 10), () {
      if (attempt != _lifecycle.currentAttempt) return;
      if (_lifecycle.state.isTerminal) return;
      if (_lifecycle.state == FamilyMapLifecycle.loadingStyle ||
          _lifecycle.state == FamilyMapLifecycle.preparingLayers) {
        debugPrint('⚠️ FamilyMap: onStyleLoaded watchdog fired after 10s — '
            'forcing lifecycle to ready/empty (state=${_lifecycle.state})');
        _advanceToReadyOrEmpty(attempt: attempt);
      }
    });
  }

  /// Transitions the lifecycle to `ready` or `empty` based on the
  /// current family data. Called when `onStyleLoaded` fires OR when
  /// the watchdog forces the transition.
  void _advanceToReadyOrEmpty({required int attempt}) {
    final hasLocatedMembers = _lastResult?.pins.isNotEmpty ?? false;
    final nextState = hasLocatedMembers
        ? FamilyMapLifecycle.ready
        : FamilyMapLifecycle.empty;
    _lifecycle.transition(nextState, attempt: attempt);
    // Cancel the watchdog — we've reached a terminal state.
    _styleWatchdog?.cancel();
    _styleWatchdog = null;
  }

  Widget _buildMap(FamilyMapResult result) {
    _lastResult = result;

    // P10.7 — Filter pins + places by the journey provider's selected year.
    // CRITICAL: ref.watch(journeyProvider) is needed here so the screen
    // rebuilds when the user drags the timeline year slider. Without it,
    // the slider updates its own label but the map pins/places are never
    // re-filtered — the timeline appears broken.
    ref.watch(journeyProvider);
    final filteredPins = ref
            .read(journeyProvider.notifier)
            .filterMapPins(result.pins);
    final filteredPlaces = ref
        .read(journeyProvider.notifier)
        .filterMapPlaces(result.places);

    // P10.4 — Compute households from the filtered pins.
    final households = computeHouseholds(filteredPins);

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
          // P11.x — Start (or restart) the building animation engine for
          // wedding pulse / memorial flicker / temple pulse / ancestral
          // breathing. Engine self-disables on reduced motion + low-tier.
          _buildingAnimEngine ??= FamilyBuildingAnimationEngine(
            deviceTier: DeviceTierCache.instance.tier,
            reducedMotion: reducedMotion,
          );
          _buildingAnimEngine!.start(style, filteredPlaces);
        }
      });
    } else if (filteredPlaces.isEmpty) {
      // P11.x — Stop the animation engine when there are no places.
      _buildingAnimEngine?.stop();
    }

    // P10.9 — Initial camera from restored state (if any).
    final restored = _restoredState;
    final initCenter = restored != null
        ? Geographic(lon: restored.lng, lat: restored.lat)
        : Geographic(lon: 78.9629, lat: 20.5937);
    final initZoom = restored?.zoom ?? 4.0;
    final initPitch = restored?.pitch ?? 0.0;

    // ── NO FutureBuilder — style is loaded in initState() ────────────
    // The old FutureBuilder created a new Future on every build, causing
    // re-subscription → lifecycle transitions during build() → infinite
    // rebuild loops on some platforms. Now we simply check if the style
    // is loaded. If not, show the skeleton. If yes, render the map.
    final styleJson = _loadedStyleJson;
    if (styleJson == null) {
      // Style still loading — show skeleton. The initState callback
      // will call setState when the style is ready.
      return _buildMapSkeleton();
    }

    // Start the watchdog the FIRST time the map is rendered.
    // This is idempotent — _startStyleWatchdog cancels any existing timer.
    if (_lifecycle.state == FamilyMapLifecycle.loadingStyle) {
      _startStyleWatchdog(attempt: _lifecycle.currentAttempt);
    }

    return AnimatedBuilder(
      animation: _lifecycle,
      builder: (context, _) {
        final state = _lifecycle.state;
        if (state == FamilyMapLifecycle.failed) {
          return _buildStyleLoadError();
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── MapLibre map — permanent background ─────────────────────
            //
            // CRITICAL: Stable ValueKey so Flutter NEVER destroys and
            // recreates this widget. Timeline, focus, search, and live
            // location changes UPDATE the existing map (via style source
            // updates + Flutter overlay repaints); they do NOT recreate
            // MapLibreMap. The key 'family-map' is constant for the
            // lifetime of the screen.
            //
            // CRITICAL: Positioned.fill ensures the map fills the entire
            // Stack. Without this, the MapLibreMap (which contains an
            // HtmlElementView on web) might render at 0×0 because
            // Stack's default StackFit.loose allows children to be
            // smaller than the parent.
            Positioned.fill(
              child: MapLibreMap(
                key: const ValueKey('family-map'),
                options: MapOptions(
                  initStyle: styleJson,
                  initCenter: initCenter,
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
            ),

            // ── P10.5 — Animated relationship paths overlay ─────────────
            // Rendered as a Flutter CustomPainter overlay because maplibre
            // 0.3.5 does not expose setPaintProperty (Rule 12 fallback).
            // The overlay reads pin screen positions from the controller.
            if (_styleLoaded && filteredPins.length >= 2)
              RelationshipPathOverlay(
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
              HouseholdClusterOverlay(
                mapController: _mapController,
                households: households.where((h) => h.isMulti).toList(),
                expandedHouseholdId: _expandedHouseholdId,
                reducedMotion: reducedMotion,
                onClusterTap: _handleClusterTap,
                onClusterLongPress: _handleClusterLongPress,
              ),

            // ── P10.8 — Polish overlay (vignette + fog + ambient + atmospheric perspective) ───────
            // Rendered on top of the map but below the bottom sheets.
            // IgnorePointer so map gestures pass through.
            // Bug 4 fix: pass deviceTier + reducedMotion so the overlay
            // disables fog/ambient on low-tier devices and respects
            // the user's reduced-motion preference.
            // P11.x: pass current pitch for atmospheric perspective (master prompt).
            MapPolishOverlay(
              deviceTier: DeviceTierCache.instance.tier,
              reducedMotion: reducedMotion,
              pitch: _currentPitch,
            ),

            // ── Empty-state overlay (lifecycle == empty) ───────────────
            // 0 located members is NOT a loading state. The base map is
            // fully interactive underneath this compact, non-blocking
            // overlay. IgnorePointer so map gestures pass through.
            if (_lifecycle.state == FamilyMapLifecycle.empty)
              _buildEmptyStateOverlay(),

            // ── Legend overlay — bottom-left ───────────────────────────
            // The map is ALWAYS fully visible and interactive — no
            // empty-state card replaces it.
            Positioned(
              left: KinrelSpacing.base,
              bottom: KinrelSpacing.base,
              child: MapLegendWidget(result: result),
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

            // ── OPTIONAL premium-layer progress indicator ───────────────
            // This is NOT the primary loading indicator (the lifecycle
            // drives that). It only shows the progress of OPTIONAL
            // premium layers (family buildings, relationship paths)
            // while the base map is already visible + interactive.
            // Hidden once the lifecycle reaches a terminal state.
            if (!_lifecycle.state.isTerminal &&
                _loadState.phase != MapLoadPhase.complete &&
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
    _rendezvousController = controller;
    // §12 — Try to prepare layers. Will only run if the style is also
    // loaded (i.e. _onStyleLoaded has fired for this attempt).
    _tryPrepareMapLayers();
    // NOTE: AmbientMotionController (idle camera rotation) was removed
    // per the regression spec — "NO idle rotation". The camera stays
    // where the user left it. Reduced-motion users especially do not
    // want any involuntary camera movement.

    // Cinematic entrance animation — runs ONCE on first open.
    // Returning users get instant restore via _restoredState (handled
    // in _buildMap via initCenter/initZoom).
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
        // cinematicEntrance duration (1500ms). Runs ONCE.
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_mapController == null) return;
          if (!mounted) return;
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

  /// Called when the Kinrel dark style finishes loading.
  ///
  /// §12 — DETERMINISTIC RENDEZVOUS: this callback stores the style
  /// in [_rendezvousStyle] and calls [_tryPrepareMapLayers]. The
  /// actual layer preparation runs once BOTH `_onMapCreated` and
  /// `_onStyleLoaded` have fired for the current attempt — see
  /// [_tryPrepareMapLayers].
  ///
  /// REQUIRED vs OPTIONAL initialization:
  ///   • REQUIRED (failure → lifecycle stays usable): the base map is
  ///     already visible because the style JSON itself defines all
  ///     layers (background, roads, water, family-buildings).
  ///   • OPTIONAL (failure → logged + skipped): avatar overlay probe,
  ///     family buildings data population, relationship path animation.
  ///
  /// CRITICAL: Every await is wrapped in try/catch so an optional
  /// layer failure cannot block the lifecycle transition to
  /// `ready`/`empty`. The lifecycle MUST reach a terminal state.
  void _onStyleLoaded(StyleController style) async {
    final attempt = _lifecycle.currentAttempt;
    _styleLoaded = true;
    _rendezvousStyle = style;

    debugPrint('✅ FamilyMap: style loaded (attempt=$attempt, '
        'web=$kIsWeb)');

    // Transition lifecycle to preparingLayers (style is loaded).
    _lifecycle.transition(
      FamilyMapLifecycle.preparingLayers,
      attempt: attempt,
    );

    // Try to prepare layers — will only run if controller is also
    // available.
    _tryPrepareMapLayers();
  }

  /// §12 — Deterministic rendezvous: runs once when BOTH onMapCreated
  /// and onStyleLoaded have fired for the current attempt. Idempotent —
  /// safe to call from both callbacks; only runs once per attempt.
  ///
  /// This eliminates the race where onStyleLoaded fires before
  /// onMapCreated (or vice versa) and bails out, relying solely on the
  /// watchdog. Now both callbacks stash their result and the second one
  /// to arrive triggers the actual layer preparation.
  void _tryPrepareMapLayers() {
    final attempt = _lifecycle.currentAttempt;

    // Both callbacks must have fired.
    if (_rendezvousController == null || _rendezvousStyle == null) return;

    // Idempotency: only run once per attempt.
    if (_layersPrepared) return;
    _layersPrepared = true;

    // Transition lifecycle if not already done (safe — transition is
    // a no-op if already in preparingLayers).
    _lifecycle.transition(
      FamilyMapLifecycle.preparingLayers,
      attempt: attempt,
    );

    // Run the optional layer preparation (avatar probe, family
    // buildings, relationship paths, etc.) — same logic that was in
    // _onStyleLoaded.
    _prepareOptionalLayers(
      _rendezvousStyle!,
      _rendezvousController!,
      attempt,
    );
  }

  /// §12 — Optional premium-layer preparation. Extracted from the old
  /// _onStyleLoaded body. Runs after the rendezvous in
  /// [_tryPrepareMapLayers] completes.
  ///
  /// Steps:
  ///   - ensure family-places layers (web only — native has them in JSON)
  ///   - avatar probe (SymbolLayer vs Flutter overlay decision)
  ///   - family buildings data population
  ///   - relationship paths init
  ///   - advance to ready/empty
  ///
  /// Every step is wrapped in try/catch + bounded by a timeout. An
  /// optional layer failure is logged + skipped — it CANNOT block the
  /// lifecycle transition to a terminal state.
  Future<void> _prepareOptionalLayers(
    StyleController style,
    MapController controller,
    int attempt,
  ) async {
    // ── Ensure family-places source + family-buildings layers exist ───
    // §8 — Web and native now share the SAME bundled Kinrel style, so
    // these layers are already in the JSON on both platforms and this
    // call is effectively a no-op (idempotent — see
    // [_ensureFamilyPlacesLayers]). The addSource/addLayer calls inside
    // are wrapped in try/catch so duplicate-adds are logged + skipped
    // (non-fatal). Kept for robustness against future style swaps.
    try {
      await _ensureFamilyPlacesLayers(style)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('⚠️ FamilyMap: _ensureFamilyPlacesLayers timed out: $e');
    }
    if (_lifecycle.currentAttempt != attempt) return;

    // ── P12.2 — Ensure live-location ambient glow source + layer ────
    // Adds the [live-location-point] source + [live-location-ambient-glow]
    // CircleLayer for the "lit pool" effect at the current user's location.
    // Idempotent — safe to call multiple times.
    try {
      await _ensureLiveLocationGlow(style)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('⚠️ FamilyMap: _ensureLiveLocationGlow timed out: $e');
    }
    if (_lifecycle.currentAttempt != attempt) return;

    // Advance the secondary progress indicator.
    if (mounted) {
      setState(() => _loadState = _loadState.copyWith(
        phase: MapLoadPhase.roadsAndBuildings,
      ));
    }

    // ── OPTIONAL: Probe SymbolLayer support for avatar markers ────────
    // Wrapped in try/catch + bounded by a 3-second timeout. If addImage
    // hangs (maplibre 0.3.5 web bug), we fall back to the Flutter overlay
    // path. This MUST NOT block the lifecycle.
    try {
      await _avatarLayer.verifySymbolLayerSupport(style)
          .timeout(const Duration(seconds: 3));
      debugPrint('🎨 FamilyMap: avatar overlay path = ${_avatarLayer.useOverlay}');
    } catch (e) {
      debugPrint('⚠️ FamilyMap: avatar probe failed ($e) — using overlay path');
      _avatarLayer.useOverlay = true;
    }
    if (_lifecycle.currentAttempt != attempt) return;

    // ── OPTIONAL: Family buildings data population ────────────────────
    // The source + layers are already in the style JSON; we just populate
    // the data. Failure is logged — the base map remains usable.
    final result = _lastResult;
    if (result != null && result.places.isNotEmpty) {
      try {
        await _familyBuildings.add(style, result.places)
            .timeout(const Duration(seconds: 3));
        if (mounted && _lifecycle.currentAttempt == attempt) {
          setState(() => _loadState = _loadState.copyWith(
            phase: MapLoadPhase.familyPlaces,
          ));
        }
      } catch (e) {
        debugPrint('⚠️ FamilyMap: family buildings add failed ($e) — skipping');
      }
    }
    if (_lifecycle.currentAttempt != attempt) return;

    // ── OPTIONAL: Animated relationship paths ─────────────────────────
    if (result != null && result.edges.isNotEmpty) {
      try {
        // Capture reduced-motion before the async gap so we don't use
        // BuildContext across async gaps.
        final reducedMotion = MediaQuery.disableAnimationsOf(context);
        _relationshipPaths = AnimatedRelationshipPath(
          tickerProvider: this,
          mapController: controller,
          style: style,
          reducedMotion: reducedMotion,
          onRepaint: () => _pathRepaintNotifier.value++,
        );
        await _relationshipPaths!.verifyLineGradientSupport()
            .timeout(const Duration(seconds: 2));
        _relationshipPaths!.start();
        if (mounted && _lifecycle.currentAttempt == attempt) {
          setState(() => _loadState = _loadState.copyWith(
            phase: MapLoadPhase.relationshipPaths,
          ));
        }
      } catch (e) {
        debugPrint('⚠️ FamilyMap: relationship paths init failed ($e) — skipping');
        _relationshipPaths?.dispose();
        _relationshipPaths = null;
      }
    }
    if (_lifecycle.currentAttempt != attempt) return;

    // ── OPTIONAL: Markers phase ───────────────────────────────────────
    if (mounted && _lifecycle.currentAttempt == attempt) {
      setState(() => _loadState = _loadState.copyWith(
        phase: MapLoadPhase.markers,
      ));
    }

    // ── REQUIRED: Transition to terminal state ────────────────────────
    // This is the fix for the infinite-loading bug. The lifecycle MUST
    // reach `ready` or `empty` — never stay in `preparingLayers` forever.
    // 0 located members → `empty` (NOT a loading state).
    _advanceToReadyOrEmpty(attempt: attempt);

    // Advance the secondary progress indicator to `complete` after a
    // brief delay. This is purely cosmetic — the lifecycle is already
    // terminal.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_lifecycle.currentAttempt != attempt) return;
      setState(() => _loadState = _loadState.copyWith(
        phase: MapLoadPhase.complete,
      ));
    });
  }

  /// P10.3 / P10.6 — Handle a tap on a family member avatar marker.
  /// Activates Focus Mode (P10.6): camera springs to center on them,
  /// non-focus markers dim, related relationship paths brighten.
  void _handlePinTap(MapPin pin) async {
    // P11.x — Haptic feedback on tap (selection click).
    await HapticFeedback.selectionClick();
    setState(() {
      _selectedPinId = pin.personId;
      // P11.x — Focus Mode pitches the camera to 45° per master prompt.
      // Track this so the atmospheric perspective overlay can fade in.
      _currentPitch = MapVisualConstants.focusPitch;
    });

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
    if (mounted) MapBottomSheets.showPinBottomSheet(context, pin);
  }

  /// P10.7 — Handle a long-press on a family member avatar marker.
  /// Builds the journey stops from the person's linked places and
  /// shows the FamilyJourneyAnimation widget.
  void _handlePinLongPress(MapPin pin) async {
    // P11.x — Haptic feedback on long-press (heavy impact).
    await HapticFeedback.heavyImpact();
    final result = _lastResult;
    if (result == null) return;
    final linkedPlaces =
        result.places.where((p) => p.personId == pin.personId).toList();
    final stops = buildJourneyStops(
      pin: pin,
      linkedPlaces: linkedPlaces,
      bornLabel:
          S.of(context)?.familyMapJourneyBorn ?? 'Born',
    );
    if (stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              S.of(context)?.familyMapNoJourney ??
                  'No journey data for this family member yet.'),
          duration: const Duration(seconds: 2),
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
      MapBottomSheets.showHouseholdBottomSheet(
          context, household, _handlePinTap);
    }
    _scheduleStateSave();
  }

  /// P10.4 — Handle a long-press on a household cluster marker.
  /// Temporarily expands the cluster to show individual members.
  void _handleClusterLongPress(Household household) {
    setState(() => _expandedHouseholdId = household.id);
    MapBottomSheets.showHouseholdBottomSheet(
        context, household, _handlePinTap);
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
        final props = feature.properties;
        final placeId = props['placeId'] as String?;
        if (placeId != null) {
          final place = _lastResult?.places.firstWhere(
            (p) => p.id == placeId,
            orElse: () => _lastResult!.places.first,
          );
          if (place != null && mounted) {
            final linkedPersonName = _lastResult?.pins
                .firstWhere(
                  (p) => p.personId == place.personId,
                  orElse: () => _lastResult!.pins.first,
                )
                .name;
            MapBottomSheets.showFamilyBuildingBottomSheet(
                context, place, linkedPersonName);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ featuresAtPoint failed: $e');
    }

    // P10.6 — Tap empty map → exit Focus Mode.
    if (_selectedPinId != null) {
      setState(() {
        _selectedPinId = null;
        // P11.x — Exiting Focus Mode resets the camera pitch to 0°.
        _currentPitch = 0.0;
      });
      await _focusController.exitFocus(
        mapController: _mapController,
        style: _mapController?.style,
        familyBuildings: _familyBuildings,
      );
      _scheduleStateSave();
    }
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
    // Debug-only: this is a dev test for visually verifying 3D building
    // extrusion. The AppBar entry is also gated by kDebugMode; this guard
    // is defensive in case the method is invoked from elsewhere.
    if (!kDebugMode) return;
    final controller = _mapController;
    if (controller == null) {
      debugPrint('❌ Map controller not ready');
      return;
    }

    debugPrint('🚀 Flying to Bengaluru: zoom=16.5, pitch=45° for 3D building test');
    controller.animateCamera(
      center: Geographic(lon: 77.5946, lat: 12.9716), // Bengaluru
      zoom: 16.5,
      pitch: 45, // 45° pitch — shows 3D building extrusion
      bearing: 0,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context)?.familyMapFlyToBengaluruSnackbar ??
            'Flying to Bengaluru — 3D buildings should appear at this zoom level'),
        duration: const Duration(seconds: 4),
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
    // Debug-only: runtime feature query for verifying 3D building
    // extrusion properties. Never runs in production builds.
    if (!kDebugMode) return;
    final controller = _mapController;
    if (controller == null) {
      debugPrint('⚠️ Cannot query buildings — controller null');
      return;
    }

    try {
      final size = MediaQuery.of(context).size;
      final centerPoint = Offset(size.width / 2, size.height / 2);

      final features = controller.featuresAtPoint(
        centerPoint,
        layerIds: const [
          FamilyBuildingLayer.extrusionLayerId,
          FamilyBuildingLayer.circleFallbackLayerId,
        ],
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
      if (props.isEmpty) {
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
      final familyId = widget.familyId;
      if (familyId.isEmpty) return;

      // P12.2 — Store the current user's position for the live-location
      // ambient glow. Update the GeoJSON source immediately so the
      // "lit pool" follows the user in real time.
      _liveLocationLat = pos.latitude;
      _liveLocationLng = pos.longitude;
      await _updateLiveLocationPoint();

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

  // ── Error State ────────────────────────────────────────────────────
  // Note: The map is always rendered — there is no "no members" or
  // "no cities" full-page empty state. When there are no located
  // members, the map shows with a small non-blocking overlay card.
  // The only full-page replacement state is the error state below.

  Widget _buildErrorState(Object error) {
    final l10n = S.of(context);
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
                l10n?.familyMapCouldNotLoad ?? 'Could Not Load Map',
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
                l10n?.familyMapErrorBody ??
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
                label: l10n?.familyMapRetry ?? 'Retry',
                variant: DKButtonVariant.primary,
                size: DKButtonSize.md,
                onPressed: () =>
                    ref.invalidate(familyMapProvider(widget.familyId)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

