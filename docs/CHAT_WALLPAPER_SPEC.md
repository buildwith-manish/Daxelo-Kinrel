# Kinrel Chat Wallpaper System Spec

## Overview

The Kinrel chat wallpaper system provides a set of curated pattern and
solid-color backgrounds for direct and group chats. All wallpapers use
flat rendering (no gradients, no blur, no shadows, no Opacity widgets in
flat mode) and are shared between group and direct chats.

## Approved Constellation Geometry (DO NOT CHANGE)

- 7 nodes at normalized coordinates:
  `(0.08,0.10) (0.26,0.05) (0.70,0.14) (0.14,0.35) (0.88,0.40)
  (0.22,0.72) (0.62,0.88)`
- 5 connection paths: `[0,1,2] [3,4] [5,6] [1,3] [2,4]`
- Lines: `ChatUi.wallLine` (#30385F) at alpha 0.8, stroke 1.6 dp
- Nodes: `ChatUi.wallDot` (#4A5275) at alpha 0.9, radius 2.5 dp
- Background: `ChatUi.chatBackground` (#0F111A)
- `shouldRepaint: false` inside a `RepaintBoundary`

## Palette System (wallpaper_palette.dart)

### Intensity

| Preset | Line alpha | Stroke | Dot alpha | Dot radius |
|--------|-----------|--------|-----------|------------|
| Standard | 0.8 | 1.6 | 0.9 | 2.5 |
| Subtle | 0.5 | 1.2 | 0.6 | 2.0 |

### Pattern alpha factor

| Pattern | Alpha factor |
|---------|-------------|
| Constellation | 1.0 |
| Branches | 0.7 |
| Contours | 0.6 |
| Kolam | 0.6 |

### tintWallColor(base, tint)

Pure function that shifts a base color's hue toward a tint color
without changing its lightness. Algorithm:
1. Convert base and tint to HSL.
2. Result hue = tint hue.
3. Result saturation = min(tint saturation, 0.55).
4. Result lightness = base lightness (preserves brightness/contrast).
5. Result alpha = 1.0 (opaque).
6. tint = null returns base exactly.

## Pattern Painters (wallpaper_patterns.dart + constellation_pattern.dart)

### Constellation
- File: `constellation_pattern.dart`
- 7 nodes, 5 paths (see approved geometry above)
- Draw ops per frame: 5 drawLine + 7 drawCircle = **12 ops**

### Branches
- File: `wallpaper_patterns.dart`
- 1 trunk cubic + 5 branch cubics + 5 tip dots
- Draw ops per frame: 6 drawPath + 5 drawCircle = **11 ops**

### Contours
- File: `wallpaper_patterns.dart`
- 6 wave paths (cubic + smooth continuation), no dots
- Draw ops per frame: 6 drawPath = **6 ops**

### Kolam lattice
- File: `wallpaper_patterns.dart`
- 36 dp tile rendered once into a `ui.Image` with 5 dots (corners +
  center, radius 1.8) + 1 diamond path, then tiled via `ImageShader`
- Draw ops per frame: 1 drawRect (ImageShader) = **1 op** (after
  initial tile generation, which happens once)
- Falls back to Constellation on low-RAM devices
- Max 2 cached tile images (keyed by palette + pixel ratio)

## Themes (chat_background_theme.dart)

### Pattern themes (have a pattern painter)

| ID | Name | Pattern | Base color |
|----|------|---------|------------|
| constellation | Constellation | Constellation | chatBackground (#0F111A) |
| branches | Branches | Branches | chatBackground |
| kolam | Kolam lattice | Kolam | chatBackground |
| contours | Contours | Contours | chatBackground |

### Solid themes (no pattern)

| ID | Name | Base color |
|----|------|------------|
| ember | Ember | chatBackgroundEmber (#15100E) |
| ink | Ink | chatBackgroundInk (#0D1120) |

### Legacy themes (existing, unchanged)

midnight, aurora, ocean, forest, sunset, space, luxuryDark, twilight

## Settings (wallpaper_settings_provider.dart)

| Setting | Key | Default | Values |
|---------|-----|---------|--------|
| Match relationship color | wallpaper_match_relationship | true | bool |
| Contrast | wallpaper_contrast | standard | standard / subtle |

- Match relationship: when on, direct chats tint the pattern toward
  the other person's kinship color. Group chats are always neutral.
- Contrast: standard (approved values) or subtle (quieter alphas +
  thinner strokes). Never affects solids or image wallpapers.

## Relationship Tint (direct chats only)

- Computed in `ChatScreen._resolveWallpaperTint(ref)`.
- Only when: `widget.isDirectChat && settings.matchRelationship &&
  widget.directOtherUserId != null`.
- Resolves the other person's relationship key via the existing
  `relationshipKeyProvider`, classifies it via `KinshipEdgeClassifier`,
  and maps to a color via `kinshipCategoryColor`.
- If the relationship is not resolved yet, passes null (neutral) and
  updates when it resolves (one repaint).
- Group chats always pass null.
- Never triggers a new network request.

## Color Tokens (chat_ui_tokens.dart)

| Token | Value | Purpose |
|-------|-------|---------|
| chatBackground | #0F111A | Dark navy-blue base |
| chatBackgroundEmber | #15100E | Warm ember solid |
| chatBackgroundInk | #0D1120 | Deep ink blue solid |
| wallLine | #30385F | Restrained blue-indigo lines |
| wallDot | #4A5275 | Brighter blue-indigo nodes |
