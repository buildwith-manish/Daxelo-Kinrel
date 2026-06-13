# Task 1 — K-Graph Blueprint Utility & Constants Files

**Agent**: main  
**Date**: 2026-03-05  
**Task ID**: 1

## Summary

Created 3 Dart files following the V2.1 K-Graph Blueprint specifications exactly.

## Files Created

### 1. `lib/shared/utils/node_colors.dart`
- **`RelationshipType` enum**: 10 values — `self`, `parent`, `spouse`, `sibling`, `child`, `grandparent`, `auntUncle`, `cousin`, `inLaw`, `extended`
- **`NodeColorSet` class**: Immutable triplet of `ring`, `background`, `glow` colors
- **`getNodeColors()` function**: Switch-based lookup mapping each `RelationshipType` to its `NodeColorSet`, using `KinrelColors` constants from `brand_colors.dart`
- **`relationshipTypeFromKey()` function**: Maps 40+ common kinship key strings (father, mother, husband, wife, paternal_grandfather, etc.) to their `RelationshipType` enum values. Returns `null` for unknown keys.
- Uses `withValues(alpha:)` instead of deprecated `withOpacity()`
- Imports from `../../core/constants/brand_colors.dart`

### 2. `lib/core/constants/animation_constants.dart`
- **`GraphAnimations` class** with private constructor (static-only access)
- Entry animations: `nodeEntryDuration` (600ms), `nodeEntryStaggerMs` (120ms)
- Pulse animations: `selfPulseDuration` (3000ms), `selectedGlowPulseDuration` (2500ms)
- Rotating ring: `rotatingRingDuration` (8s)
- Edge transitions: `edgeOpacityTransition` (350ms)
- Info card: `infoCardEntry` (400ms)
- Ambient orbs: `orb1Duration` (8s), `orb2Duration` (10s), `orb3Duration` (7s), `orb2Delay` (2s), `orb3Delay` (4s)
- Dimming: `dimOpacityDuration` (400ms)
- Curves: `entryCurve` (Cubic(0.22, 1.0, 0.36, 1.0)), `pulseCurve` (Curves.easeInOut), `infoCardCurve` (Curves.elasticOut)

### 3. `lib/core/constants/graph_canvas_config.dart`
- **`GraphCanvasConfig` class** with private constructor (static-only access)
- Canvas dimensions: `canvasWidth` (1400.0), `canvasHeight` (920.0)
- Zoom constraints: `minZoom` (0.3), `maxZoom` (2.5), `defaultZoom` (1.0), `zoomStep` (0.15), `wheelZoomStep` (0.07)
- LOD threshold: `lodMinimalZoom` (0.4)
- Grid pattern: `gridSpacing` (40.0), `gridDotRadius` (1.0)
- Node dimensions: `selfNodeSize` (88.0), `defaultNodeSize` (76.0), ring widths, `glowExtent`, `badgeSize`
- Generation Y positions: `{0: 140.0, 1: 350.0, 2: 580.0, 3: 780.0}` with fallback spacing (200.0)
- Horizontal spacing: `spouseGap` (150.0), `siblingGap` (180.0), `branchGap` (280.0)

## Design Decisions
- All color values sourced from existing `KinrelColors` constants in `brand_colors.dart` rather than duplicating hex values
- Used `withValues(alpha:)` per project requirement (Flutter 3.27+ API)
- All classes use private constructors to enforce static-only usage
- Comprehensive dartdoc comments with usage examples
- File header comments reference the V2.1 K-Graph Blueprint section numbers
