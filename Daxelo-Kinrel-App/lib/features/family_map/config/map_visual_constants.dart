// lib/features/family_map/config/map_visual_constants.dart
//
// P10.1 — Single source of truth for ALL visual values in Phase 10.
// (Rule 14 — No magic constants. Every Phase 10 widget reads from here.)
//
// All values are STARTING POINTS per Rule 16. Tune after testing on a
// mid-tier device while preserving:
//   - Performance (60 FPS hard floor — Rule 13)
//   - Readability (WCAG AA contrast — Rule 8)
//   - Accessibility (reduced motion — Rule 8)
//   - One visual language (Guardrail 3)

import 'dart:ui';

/// Centralised visual constants for the Family Atlas (Phase 10).
///
/// Every color, size, duration, opacity, and zoom threshold used by
/// the family map lives here. Widgets MUST reference these constants
/// instead of inlining values, so the visual language can be tuned
/// in one place without touching widget code (Rule 14).
class MapVisualConstants {
  MapVisualConstants._(); // no instances

  // ═════════════════════════════════════════════════════════════════════
  // MAP STYLE PALETTE
  // ═════════════════════════════════════════════════════════════════════
  // Used by kinrel_dark_style.json — keep the hex values in sync
  // between this file and the JSON.
  // ═════════════════════════════════════════════════════════════════════

  /// Base background of the dark map — P12 premium warm charcoal.
  /// Slightly warmer than the original #131416 to match the
  /// Snapchat-style 3D map aesthetic with Kinrel warmth.
  static const Color background = Color(0xFF0F1014);

  /// Land color (parks, land-use polygons) — warm dark purple-grey.
  static const Color land = Color(0xFF1B1A24);

  /// Water bodies — warm navy with amber undertone.
  static const Color water = Color(0xFF1A1E2A);

  /// Minor / residential roads.
  static const Color roadMinor = Color(0xFF2A2440);

  /// Primary roads.
  static const Color roadPrimary = Color(0xFF3A3252);

  /// Motorways / highways.
  static const Color roadMotorway = Color(0xFF4A3F63);

  /// Generic non-family buildings — warm dark base for 3D extrusion.
  /// P12 premium: generic 3D buildings now extrude (Snapchat-style
  /// blocky) with this warm-tinted base. Family buildings still pop
  /// on top with their warm beacon colors.
  static const Color buildingNormal = Color(0xFF1C1B26);

  /// Generic building top color (slightly lighter for vertical gradient).
  static const Color buildingNormalTop = Color(0xFF2A2638);

  /// Generic building tall accent (high-rises get this tint).
  static const Color buildingNormalTall = Color(0xFF352D44);

  // ═════════════════════════════════════════════════════════════════════
  // FAMILY BUILDING COLORS (by PlaceType — P10.2)
  // ═════════════════════════════════════════════════════════════════════
  // Emotional lighting per family-place type. These warm colors stand
  // out against the dark neutral of generic buildings.
  // ═════════════════════════════════════════════════════════════════════

  /// Current home — warm orange (active living).
  static const Color buildingCurrentHome = Color(0xFFE8612A);

  /// Childhood home — soft amber (memory).
  static const Color buildingChildhoodHome = Color(0xFFF59240);

  /// Ancestral home — gold (heritage).
  static const Color buildingAncestralHome = Color(0xFF917520);

  /// Birthplace — gentle highlight.
  static const Color buildingBirthplace = Color(0xFFF5B841);

  /// Wedding location — warm celebration glow (also pulse-animated).
  static const Color buildingWedding = Color(0xFFE8612A);

  /// Memorial location — soft candle amber (also flicker-animated).
  static const Color buildingMemorial = Color(0xFFF59240);

  /// Family business — neutral warm.
  static const Color buildingFamilyBusiness = Color(0xFFC44A18);

  /// School — cool neutral (the only cool color in the family palette).
  static const Color buildingSchool = Color(0xFF4E6984);

  /// Vacation home — cool serenity glow (retreat / getaway).
  static const Color buildingVacationHome = Color(0xFF4E6984);

  /// Family temple — sacred warm glow (reverent pulse).
  static const Color buildingFamilyTemple = Color(0xFFE8612A);

  /// Grandparents home — amber warmth (gentle pulse).
  static const Color buildingGrandparentsHome = Color(0xFFF59240);

  /// Important family place — default warm.
  static const Color buildingImportantPlace = Color(0xFFE8612A);

  // ═════════════════════════════════════════════════════════════════════
  // AVATAR MARKER SIZES (P10.3)
  // ═════════════════════════════════════════════════════════════════════

  /// Diameter of an unselected avatar marker (logical px).
  /// P12: bumped from 40 → 44 for more prominent Snapchat-style
  /// photo markers.
  static const double markerNormalSize = 44.0;

  /// Diameter of a selected avatar marker.
  /// P12: bumped from 56 → 60 for stronger focus emphasis.
  static const double markerSelectedSize = 60.0;

  /// Ring stroke width for an unselected marker.
  static const double markerRingWidthNormal = 2.0;

  /// Ring stroke width for a selected marker (gold).
  static const double markerRingWidthSelected = 3.0;

  /// Outer glow blur radius (unselected).
  /// P12: increased from 6 → 8 for more prominent photo markers.
  static const double markerGlowBlurNormal = 8.0;

  /// Outer glow blur radius (selected).
  /// P12: increased from 12 → 16 for stronger focus glow.
  static const double markerGlowBlurSelected = 16.0;

  /// Drop shadow offset for markers.
  static const double markerShadowOffset = 2.0;

  // ═════════════════════════════════════════════════════════════════════
  // CLUSTER MARKER (P10.4)
  // ═════════════════════════════════════════════════════════════════════

  /// Diameter of a household cluster marker.
  static const double clusterMarkerSize = 48.0;

  /// Stacked-avatar offset within a cluster (overlap distance).
  static const double clusterStackOffset = 12.0;

  /// "+N" badge diameter.
  static const double clusterBadgeSize = 18.0;

  // ═════════════════════════════════════════════════════════════════════
  // ANIMATION DURATIONS (Rule 16 — tune after testing)
  // ═════════════════════════════════════════════════════════════════════

  /// Camera spring duration when entering Focus Mode.
  static const Duration focusTransition = Duration(milliseconds: 420);

  /// Cinematic map entrance on first open.
  static const Duration cinematicEntrance = Duration(milliseconds: 1500);

  /// One full cycle of a relationship-path gradient flow.
  static const Duration relationshipFlowCycle = Duration(seconds: 3);

  /// Household cluster expand/collapse animation.
  static const Duration clusterExpand = Duration(milliseconds: 300);

  /// Crossfade duration when the timeline year changes.
  static const Duration timelineCrossfade = Duration(milliseconds: 300);

  /// Live-location pulse cycle (LIVE tier).
  static const Duration livePulseCycle = Duration(milliseconds: 1800);

  /// Wedding celebration glow cycle (slower than LIVE pulse).
  static const Duration weddingGlowCycle = Duration(seconds: 4);

  /// Memorial candle flicker cycle.
  static const Duration memorialFlickerCycle = Duration(milliseconds: 2400);

  /// Selection scale spring duration.
  static const Duration selectionScale = Duration(milliseconds: 260);

  // ═════════════════════════════════════════════════════════════════════
  // POLISH OVERLAY (P10.8) — Rule 16: tune after testing
  // ═════════════════════════════════════════════════════════════════════

  /// Vignette intensity at the corners. Per master prompt: 0.35.
  /// P12 premium: bumped to 0.40 for the cinematic Snapchat-style mood
  /// (darker corners focus attention on the 3D buildings + markers).
  static const double vignetteOpacity = 0.40;

  /// Atmospheric fog opacity (barely visible).
  /// P12: bumped slightly to 0.06 for more depth perception.
  static const double fogOpacity = 0.06;

  /// Warm ambient lighting overlay opacity.
  /// P12: bumped slightly to 0.04 to amplify the warm Kinrel orange
  /// mood over the whole map (matches the Snapchat "lit" feel).
  static const double ambientWarmthOpacity = 0.04;

  // ═════════════════════════════════════════════════════════════════════
  // ZOOM THRESHOLDS
  // ═════════════════════════════════════════════════════════════════════

  /// Below this zoom, 3D building extrusion is hidden for performance.
  /// P12 premium: lowered from 15 → 14 to match Snapchat-style 3D
  /// appearance earlier (buildings extrude at city-street view).
  static const double buildingExtrusionMinZoom = 14.0;

  /// P11.x — Above this zoom, the per-type roof detail layer renders.
  /// Per master prompt: roof pattern added at runtime at zoom 17+.
  static const double buildingRoofMinZoom = 17.0;

  /// Above this zoom, household clustering is disabled (show individuals).
  static const double clusterMaxZoom = 14.0;

  /// Below this zoom, secondary POIs (small landmarks) are hidden.
  static const double secondaryPoiMinZoom = 14.0;

  /// Minimum zoom the camera will use when entering Focus Mode.
  static const double focusMinZoom = 13.0;

  /// Camera pitch (tilt) for Focus Mode and cinematic entrance.
  static const double focusPitch = 45.0;

  /// P11.x — Pitch (degrees) above which atmospheric perspective fades in.
  /// Per master prompt: linear fade top-down when pitch > 10°, max 0.12.
  static const double atmosphericPerspectivePitchThreshold = 10.0;

  /// P11.x — Maximum opacity of the atmospheric perspective overlay.
  static const double atmosphericPerspectiveMaxOpacity = 0.12;

  /// P11.x — Wedding glow pulse minimum opacity (sine wave trough).
  static const double weddingGlowMin = 0.45;

  /// P11.x — Wedding glow pulse maximum opacity (sine wave peak).
  static const double weddingGlowMax = 0.85;

  /// P11.x — Memorial candle flicker minimum opacity.
  static const double memorialFlickerMin = 0.40;

  /// P11.x — Memorial candle flicker maximum opacity.
  static const double memorialFlickerMax = 0.80;

  /// P11.x — Selection halo stroke width (px) for the focused avatar.
  static const double selectionHaloStrokeWidth = 4.0;

  /// P11.x — Selection halo radius increase beyond the marker (px).
  static const double selectionHaloRadiusPadding = 8.0;

  /// P11.x — Focus Mode dimmed opacity for non-related markers (per master prompt).
  static const double focusModeDimmedOpacity = 0.4;

  // ═════════════════════════════════════════════════════════════════════
  // FOCUS MODE (P10.6)
  // ═════════════════════════════════════════════════════════════════════

  /// Opacity of non-focused markers / paths / buildings when Focus Mode is on.
  static const double nonFocusOpacity = 0.4;

  /// Opacity of focused + first-degree related elements.
  static const double focusOpacity = 1.0;

  // ═════════════════════════════════════════════════════════════════════
  // PERFORMANCE
  // ═════════════════════════════════════════════════════════════════════

  /// Maximum number of relationship paths animated simultaneously.
  /// Viewport-cull beyond this count (Rule 13).
  static const int maxVisibleAnimatedPaths = 20;

  /// MapLibre cluster radius (logical px).
  static const double clusterRadius = 50.0;

  /// Households are members within this many degrees of each other.
  /// 0.001° ≈ 111 meters at the equator.
  static const double householdEpsilon = 0.001;

  // ═════════════════════════════════════════════════════════════════════
  // TIMELINE (P10.7)
  // ═════════════════════════════════════════════════════════════════════

  /// Earliest year the timeline scrubber can show.
  static const int timelineMinYear = 1920;

  /// Auto-advance interval for the timeline Play button.
  static const Duration timelinePlayInterval = Duration(seconds: 2);

  // ═════════════════════════════════════════════════════════════════════
  // STATE PERSISTENCE (P10.9)
  // ═════════════════════════════════════════════════════════════════════

  /// Debounce window for saving camera position changes.
  static const Duration stateSaveDebounce = Duration(milliseconds: 500);

  /// SharedPreferences key prefix for per-family map session state.
  static const String stateKeyPrefix = 'map_session_';

  /// Schema version for the persisted MapSessionState JSON.
  static const int stateVersion = 1;

  // ═════════════════════════════════════════════════════════════════════
  // PROGRESSIVE LOADING (P10.8)
  // ═════════════════════════════════════════════════════════════════════

  /// If map tiles haven't arrived after this duration, show a "Still loading"
  /// indicator. Tune per Rule 16.
  static const Duration tilesLoadingWarning = Duration(seconds: 4);

  // ═════════════════════════════════════════════════════════════════════
  // P11.4 — OPACITIES (centralized per Rule 5 — no magic constants)
  // ═════════════════════════════════════════════════════════════════════

  /// Drop shadow opacity for avatar markers.
  static const double markerShadowOpacity = 0.35;

  /// Glow alpha for unselected avatar markers.
  static const double markerGlowAlphaNormal = 0.30;

  /// Glow alpha for selected avatar markers.
  static const double markerGlowAlphaSelected = 0.55;

  /// Background tint opacity for initials avatar fallback.
  static const double markerInitialsBgOpacity = 0.18;

  /// LIVE tier pulse ring opacity.
  static const double livePulseRingOpacity = 0.85;

  /// RECENT tier solid ring opacity.
  static const double recentRingOpacity = 0.70;

  /// STALE tier dimmed ring opacity.
  static const double staleRingOpacity = 0.50;

  /// LIVE tier pulse shimmer opacity (overlay path).
  static const double livePulseShimmerOpacity = 0.35;

  /// Cluster marker shadow opacity.
  static const double clusterShadowOpacity = 0.35;

  /// Household bottom-sheet shadow opacity.
  static const double householdSheetShadowOpacity = 0.40;

  /// Journey stop dot completed opacity.
  static const double journeyStopCompletedOpacity = 0.60;

  /// Journey stop dot active shimmer opacity.
  static const double journeyStopActiveShimmerOpacity = 0.40;

  /// Timeline scrubber container shadow opacity.
  static const double timelineShadowOpacity = 0.40;

  /// Timeline slider overlay opacity.
  static const double timelineSliderOverlayOpacity = 0.18;

  /// Building glow halo opacity (from style JSON — kept here for reference).
  static const double buildingGlowHaloOpacity = 0.65;

  /// Building extrusion opacity (from style JSON — kept here for reference).
  static const double buildingExtrusionOpacity = 0.95;

  /// Building circle fallback opacity (from style JSON — kept here for reference).
  static const double buildingCircleFallbackOpacity = 0.90;

  /// Building bottom-sheet chip background opacity.
  static const double buildingChipBgOpacity = 0.18;

  // ═════════════════════════════════════════════════════════════════════
  // P11.4 — COLORS (centralized per Rule 5)
  // ═════════════════════════════════════════════════════════════════════

  /// Gold ring color for selected avatar markers.
  static const Color markerSelectedRingColor = Color(0xFFE8B941);

  /// Teal pulse ring color for LIVE location tier.
  static const Color livePulseRingColor = Color(0xFF4ED9C7);

  /// Dim grey ring color for STALE location tier.
  static const Color staleRingColor = Color(0xFF8A8A8A);

  /// Dark circle background for avatar marker (contrast behind photo).
  static const Color markerBgColor = Color(0xFF1A1A22);

  /// Fog color for the atmospheric fog painter.
  static const Color fogColor = Color(0xFF1A2533);

  // ═════════════════════════════════════════════════════════════════════
  // P11.4 — DURATIONS (centralized per Rule 5)
  // ═════════════════════════════════════════════════════════════════════

  /// Photo decode timeout in the avatar marker generator.
  static const Duration photoDecodeTimeout = Duration(seconds: 2);

  /// Image stream completer timeout.
  static const Duration imageStreamTimeout = Duration(seconds: 3);

  // ═════════════════════════════════════════════════════════════════════
  // P11.6 — EMOTIONAL POLISH
  // ═════════════════════════════════════════════════════════════════════

  /// Pin fade-in stagger delay during cinematic entrance.
  static const Duration pinStaggerDelay = Duration(milliseconds: 50);

  /// Idle time before ambient camera drift starts (desktop/web only).
  static const Duration ambientMotionIdleDelay = Duration(seconds: 30);

  /// Ambient camera drift rate (degrees per second).
  static const double ambientDriftRate = 0.1;

  /// Ambient sound interval minimum (randomized between min and max).
  static const Duration ambientSoundMinInterval = Duration(seconds: 30);

  /// Ambient sound interval maximum.
  static const Duration ambientSoundMaxInterval = Duration(seconds: 60);

  /// Ambient sound volume (very low — opt-in only).
  static const double ambientSoundVolume = 0.10;

  /// P11.6 — Full rotation duration for the ambient drift (60 minutes).
  /// The ambient motion controller repeats its AnimationController over
  /// this duration so the camera completes one full bearing rotation
  /// (360°) per cycle. Tuned to be barely perceptible.
  static const Duration ambientDriftCycle = Duration(seconds: 3600);

  /// P11.7 — Skeleton shimmer opacity for the icon placeholder.
  static const double skeletonShimmerOpacity = 0.15;

  /// P11.4 — Cluster marker outer glow alpha (used in both the generator
  /// and the Flutter widget fallback). Matches the orange glow used on
  /// unselected avatar markers for visual consistency.
  static const double clusterGlowAlpha = 0.30;

  /// P10.8 — Warm ambient overlay color used by the polish overlay's
  /// ambient warmth painter. Same hex as `buildingImportantPlace` /
  /// `buildingCurrentHome` so the polish wash matches the family
  /// building palette.
  static const Color ambientWarmthColor = Color(0xFFE8612A);

  /// P10.8 — Vignette gradient midpoint intensity multiplier. The
  /// vignette paints three stops (transparent → 50% intensity → full
  /// intensity); this constant tunes the midpoint value.
  static const double vignetteMidpointMultiplier = 0.5;

  /// P10.8 — Fog gradient bottom-stop intensity multiplier. The fog
  /// paints top → transparent → bottom; this constant tunes the
  /// bottom stop (slightly dimmer than the top).
  static const double fogBottomStopMultiplier = 0.7;

  // ═════════════════════════════════════════════════════════════════════
  // P11.7 — LOADING PERFECTION
  // ═════════════════════════════════════════════════════════════════════

  /// Target time-to-first-paint for the map.
  static const Duration firstPaintTarget = Duration(milliseconds: 500);

  /// Minimum skeleton display time (avoid flash on fast loads).
  static const Duration minSkeletonDisplay = Duration(milliseconds: 200);

  /// Skeleton-to-map crossfade duration.
  static const Duration skeletonCrossfade = Duration(milliseconds: 300);

  // ═════════════════════════════════════════════════════════════════════
  // CONVENIENCE: HEX STRINGS for kinrel_dark_style.json
  // ═════════════════════════════════════════════════════════════════════
  // The map style JSON uses lowercase hex strings. Keep these in sync
  // with the Color constants above so a single source of truth exists
  // at the documentation level (the JSON itself is the runtime source).
  // ═════════════════════════════════════════════════════════════════════

  static const String hexBackground = '#0F1014';
  static const String hexLand = '#1B1A24';
  static const String hexWater = '#1A1E2A';
  static const String hexRoadMinor = '#2A2440';
  static const String hexRoadPrimary = '#3A3252';
  static const String hexRoadMotorway = '#4A3F63';
  static const String hexBuildingNormal = '#1C1B26';
  /// P12: generic building top color (vertical gradient).
  static const String hexBuildingNormalTop = '#2A2638';
  /// P12: generic building tall accent color.
  static const String hexBuildingNormalTall = '#352D44';
  static const String hexBuildingCurrentHome = '#E8612A';
  static const String hexBuildingChildhoodHome = '#F59240';
  static const String hexBuildingAncestralHome = '#917520';
  static const String hexBuildingBirthplace = '#F5B841';
  static const String hexBuildingWedding = '#E8612A';
  static const String hexBuildingMemorial = '#F59240';
  static const String hexBuildingFamilyBusiness = '#C44A18';
  static const String hexBuildingSchool = '#4E6984';
  static const String hexBuildingVacationHome = '#4E6984';
  static const String hexBuildingFamilyTemple = '#E8612A';
  static const String hexBuildingGrandparentsHome = '#F59240';
  static const String hexBuildingImportantPlace = '#E8612A';

  // ═════════════════════════════════════════════════════════════════════
  // P11.x — HILLSHADE (premium terrain depth)
  // ═════════════════════════════════════════════════════════════════════

  /// Hillshade shadow color (deep charcoal).
  static const String hexHillshadeShadow = '#0A0A0F';

  /// Hillshade highlight color (cool grey).
  static const String hexHillshadeHighlight = '#2A2A3A';

  /// Hillshade accent color — Kinrel orange tint on peaks.
  static const String hexHillshadeAccent = '#E8612A';

  /// Hillshade exaggeration (0.25 = subtle depth).
  static const double hillshadeExaggeration = 0.25;

  /// Hillshade max zoom.
  static const double hillshadeMaxZoom = 14.0;

  // ═════════════════════════════════════════════════════════════════════
  // P11.x — ROAD HIGH-ZOOM TINTS (Kinrel orange)
  // ═════════════════════════════════════════════════════════════════════

  /// Minor road base color (warmer than original).
  static const String hexRoadMinorV2 = '#2E2642';

  /// Primary road base color (warmer than original).
  static const String hexRoadPrimaryV2 = '#3E3656';

  /// Motorway road base color (warmer than original).
  static const String hexRoadMotorwayV2 = '#4E4468';

  /// Kinrel orange — applied to primary roads at zoom 14+.
  static const String hexRoadHighZoomTint = '#E8612A';

  /// Zoom threshold above which primary roads get the Kinrel orange tint.
  static const double roadPrimaryTintZoom = 14.0;

  /// Zoom threshold above which motorways get the Kinrel orange tint.
  static const double roadMotorwayTintZoom = 15.0;

  // ═════════════════════════════════════════════════════════════════════
  // P11.x — PARK / LAND WARMTH
  // ═════════════════════════════════════════════════════════════════════

  /// Park fill color (warm dark green, handcrafted for family palette).
  static const String hexPark = '#1F2620';

  /// Park fill opacity (reduced from 0.7 → 0.55 per master prompt).
  static const double parkOpacity = 0.55;

  /// Landcover opacity for wood/grass (reduced per master prompt).
  static const double landcoverOpacity = 0.55;

  // ═════════════════════════════════════════════════════════════════════
  // P11.x — WCAG AA LABEL CONTRAST
  // ═════════════════════════════════════════════════════════════════════

  /// Text halo width for all map labels (WCAG AA — 2px per master prompt).
  static const double labelHaloWidth = 2.0;

  /// Text halo color for all map labels (deep black per master prompt).
  static const String hexLabelHaloColor = '#0D0D0D';

  /// Text halo blur radius.
  static const double labelHaloBlur = 1.0;
}
