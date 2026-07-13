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

  /// Base background of the dark map.
  static const Color background = Color(0xFF131416);

  /// Land color (parks, land-use polygons).
  static const Color land = Color(0xFF191B2C);

  /// Water bodies.
  static const Color water = Color(0xFF162335);

  /// Minor / residential roads.
  static const Color roadMinor = Color(0xFF2A2440);

  /// Primary roads.
  static const Color roadPrimary = Color(0xFF3A3252);

  /// Motorways / highways.
  static const Color roadMotorway = Color(0xFF4A3F63);

  /// Generic non-family buildings.
  static const Color buildingNormal = Color(0xFF1F1B2E);

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

  /// Important family place — default warm.
  static const Color buildingImportantPlace = Color(0xFFE8612A);

  // ═════════════════════════════════════════════════════════════════════
  // AVATAR MARKER SIZES (P10.3)
  // ═════════════════════════════════════════════════════════════════════

  /// Diameter of an unselected avatar marker (logical px).
  static const double markerNormalSize = 40.0;

  /// Diameter of a selected avatar marker.
  static const double markerSelectedSize = 56.0;

  /// Ring stroke width for an unselected marker.
  static const double markerRingWidthNormal = 2.0;

  /// Ring stroke width for a selected marker (gold).
  static const double markerRingWidthSelected = 3.0;

  /// Outer glow blur radius (unselected).
  static const double markerGlowBlurNormal = 6.0;

  /// Outer glow blur radius (selected).
  static const double markerGlowBlurSelected = 12.0;

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

  /// Vignette intensity at the corners.
  static const double vignetteOpacity = 0.4;

  /// Atmospheric fog opacity (barely visible).
  static const double fogOpacity = 0.05;

  /// Warm ambient lighting overlay opacity.
  static const double ambientWarmthOpacity = 0.03;

  // ═════════════════════════════════════════════════════════════════════
  // ZOOM THRESHOLDS
  // ═════════════════════════════════════════════════════════════════════

  /// Below this zoom, 3D building extrusion is hidden for performance.
  static const double buildingExtrusionMinZoom = 15.0;

  /// Above this zoom, household clustering is disabled (show individuals).
  static const double clusterMaxZoom = 14.0;

  /// Below this zoom, secondary POIs (small landmarks) are hidden.
  static const double secondaryPoiMinZoom = 14.0;

  /// Minimum zoom the camera will use when entering Focus Mode.
  static const double focusMinZoom = 13.0;

  /// Camera pitch (tilt) for Focus Mode and cinematic entrance.
  static const double focusPitch = 45.0;

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
  // CONVENIENCE: HEX STRINGS for kinrel_dark_style.json
  // ═════════════════════════════════════════════════════════════════════
  // The map style JSON uses lowercase hex strings. Keep these in sync
  // with the Color constants above so a single source of truth exists
  // at the documentation level (the JSON itself is the runtime source).
  // ═════════════════════════════════════════════════════════════════════

  static const String hexBackground = '#131416';
  static const String hexLand = '#191B2C';
  static const String hexWater = '#162335';
  static const String hexRoadMinor = '#2A2440';
  static const String hexRoadPrimary = '#3A3252';
  static const String hexRoadMotorway = '#4A3F63';
  static const String hexBuildingNormal = '#1F1B2E';
  static const String hexBuildingCurrentHome = '#E8612A';
  static const String hexBuildingChildhoodHome = '#F59240';
  static const String hexBuildingAncestralHome = '#917520';
  static const String hexBuildingBirthplace = '#F5B841';
  static const String hexBuildingWedding = '#E8612A';
  static const String hexBuildingMemorial = '#F59240';
  static const String hexBuildingFamilyBusiness = '#C44A18';
  static const String hexBuildingSchool = '#4E6984';
  static const String hexBuildingImportantPlace = '#E8612A';
}
