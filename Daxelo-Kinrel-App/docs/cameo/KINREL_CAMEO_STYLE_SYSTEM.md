# KINREL CAMEO — STYLE SYSTEM

> **Status:** Production-ready foundational layer. This is the deterministic Kinrel Cameo style system + the "no 3D Cameo yet" fallback portrait. The 3D character rendering itself remains gated behind the V2 B1 prototype (Blender art + `three_js`).
> **Repository:** `buildwith-manish/Daxelo-Kinrel`
> **Source plan:** `KINREL_CAMEO_PRODUCTION_PLAN_V2.md` (V2 §1–§90)
> **Implementation prompt:** `KINREL_AUDIT_TO_PRODUCTION_IMPLEMENTATION_PROMPT.md`
> **Location:** `Daxelo-Kinrel-App/lib/features/cameo/`

---

## 1. What this is

The **`KINREL_CAMEO_STYLE_SYSTEM`** is the single deterministic governor for every Kinrel Cameo — live 3D, derived PNG, and the fallback portrait that ships today. It encodes the Kinrel visual language as concrete, importable Dart tokens and rules so that all current and future Cameos share the same recognizable identity.

This is NOT the 3D character renderer. The 3D renderer (V2 B3 — `three_js` + Blender GLBs) is gated behind the B1 prototype (Blender artist + 17 PASS criteria on Android/iOS/Web). What ships here is:

1. **The style system** — every visual token, lighting recipe, animation tuning, camera rule, responsive rule, accessibility rule, and quality gate. The 3D runtime will consume this directly when it ships.
2. **`CameoAvatar`** — a designed, deterministic, cinematic Kinrel portrait widget that renders the same visual language today, in 2D via `CustomPainter`. It is the V2 §3.6 / §39.3 fallback, built now. It is NOT a placeholder, NOT an emoji, NOT a stock avatar — it is a hand-tuned Kinrel portrait with the warm ivory + ember rim signature, soft rounded silhouette, age-aware skin and hair, subtle breathing / blink / saccade animation, full reduced-motion support, responsive scaling, and a dignified monogram fallback if the painter ever throws.

---

## 2. The Kinrel Cameo signature

Every Cameo — regardless of surface, age, skin tone, clothing, or state — carries the **signature pair**:

| Element | Color | Role |
|---|---|---|
| **Warm Ivory Key Light** | `CameoColorPalette.keyLightIvory` (`#FFF4E0`) | The soft, heirloom glow on every face |
| **Ember Rim** | `CameoColorPalette.rimLightEmber` (`#C44A18`, re-uses `KinrelColors.ember`) | The hair-line that separates character from background |

A Cameo without this pair is not a Kinrel Cameo. The quality gates (`CameoQualityGates.verifySignaturePairPresent`) enforce this on every lighting preset.

---

## 3. What the style system governs

Per the request, one reusable deterministic system governs:

| Dimension | File | V2 source |
|---|---|---|
| Character design | `cameo_shape_language.dart` | V2 §11, §71 |
| Shape language | `cameo_shape_language.dart` | V2 §5, §11, §71 |
| Facial expression range | `cameo_expression_catalog.dart` | V2 §33 |
| Poses | `cameo_pose_catalog.dart` | V2 §5.5, §30 |
| Camera rules | `cameo_camera_rules.dart` | V2 §30 |
| Lighting | `cameo_lighting_presets.dart` | V2 §5.2, §31 |
| Materials | `cameo_material_specs.dart` | V2 §17, §18, §19, §22, §25 |
| Scene density | `cameo_scene_density_rules.dart` | V2 §5.6, §44 |
| Animation behavior | `cameo_animation_curves.dart` | V2 §32, §67 |
| Accessibility | `cameo_accessibility_rules.dart` | V2 §66, §67, §70 |
| Responsive scaling | `cameo_responsive_rules.dart` | (request) |
| Quality constraints | `cameo_quality_gates.dart` | (this system) |
| Color | `cameo_color_palette.dart` | V2 §5, §17, §71 |

The single entry point is **`CameoStyleSystem.resolve(...)`**, which returns a `ResolvedCameoStyle` containing every resolved token a painter or renderer needs.

---

## 4. The seven approved surfaces

A Cameo surface is a place a Cameo appears. Each surface has its own camera, lighting, animation, responsive, scene-density, and a11y profile. The approved surfaces:

| Surface ID | Live 3D? | Default Lighting | Animation | Camera Frame |
|---|---|---|---|---|
| `studio` | Yes | `studio` | Full subtle motion | Bust |
| `profile_hero` | Yes | `profile_hero` | Motion minus camera drift | Bust |
| `journey` | Yes | `journey` | Full + scripted camera | Full |
| `map_marker` | No (derived PNG) | `derivedPng` | Static | Portrait |
| `graph_node` | No (derived PNG) | `derivedPng` | Static | Portrait |
| `chat_avatar` | No (derived PNG) | `derivedPng` | Static | Portrait |
| `timeline_card` | No (derived PNG) | `derivedPng` | Static | Portrait |

**Hard rule (V2 §1.9, enforced by `CameoQualityGates.verifyNoBannedSurfaces`):** Live 3D is allowed ONLY on `studio`, `profile_hero`, and `journey`. The other four surfaces are derived PNG only. This is what makes 50 Map markers and 200 Graph nodes performant.

---

## 5. The 8 age bands

`CameoAgeBand` enum (V2 §15.3): `baby`, `child`, `teenager`, `youngAdult`, `adult`, `middleAged`, `senior`, `elder`. Each band deterministically shifts:

- **Head width** (`CameoShapeLanguage.headWidthScaleForAgeBand`) — babies have larger heads relative to body; elders slightly narrower.
- **Jaw softness** (`CameoShapeLanguage.jawSoftnessForAgeBand`) — jaws soften with age; babies are roundest.
- **Posture droop** (`CameoShapeLanguage.postureDroopForAgeBand`) — posture softens with age, never cartoonishly.
- **Skin roughness + subsurface** (`CameoSkinMaterial.aged`) — skin gets rougher and less subsurface with age (V2 §15.4).
- **Hair greying** (`CameoMaterialLibrary.greyingForAgeBand`) — hair greys per age band (V2 §15.5).
- **Default pose** (`CameoPoseCatalog.defaultForAgeBand`) — children centered; adults three-quarter; elders dignified stooped.

---

## 6. Memorial (V2 §16.3, §45, §70.3)

Memorial is **family-controlled, never automatic**. The default memorial atmosphere for any deceased person — including deceased minors — is **`softLight`**. `candleGlow` is family-opted only. `CameoQualityGates.verifyMemorialDefaults` enforces this.

The lighting presets:
- `CameoLightingPresets.memorialSoft` — soft reverent cool-ivory rim. The default.
- `CameoLightingPresets.memorialCandle` — candle glow. Family-opted only.
- `CameoLightingPresets.memorialFor(atmosphere)` — the resolver. `null` / `'softLight'` → memorialSoft; `'candleGlow'` → memorialCandle; `'none'` → derivedPng.

---

## 7. Child safety (V2 §70)

`CameoChildSafetyRules`:
- `isMinor(band)` — true for baby / child / teenager.
- `forbiddenTraitsForMinors` — facial hair, non-wedding sindoor, heavy earrings, mangalsutra.
- `isTraitAllowedForAgeBand(traitId, band)` — the gate. Returns false for forbidden traits on minors.
- `defaultMemorialAtmosphere(band)` — always `'softLight'` (V2 §70.3: deceased minors default to softLight, never candleGlow).
- `minorPrivacyLevel` — `'family'` (V2 §70.2: minors' Cameos forced to family privacy).

`CameoQualityGates.verifyChildSafetyRules` iterates every minor band × every forbidden trait and verifies the gate rejects it.

---

## 8. Animation (V2 §32, §67)

Premium, subtle, restrained motion ONLY. `CameoAnimationCurves` per surface:

- **Breathing:** 4s sine wave, 0.6px chest rise at UI size. Period never shorter than 3.5s.
- **Blink:** 110ms close + 220ms open. Random interval 3.2–6.0s. Never shorter than 3.0s.
- **Saccades:** 80ms micro-move, random interval 1.6–3.4s. Magnitude capped at 0.6mm.
- **Head sway:** 8s sine wave, 0.4° amplitude. Never more.
- **Camera idle drift:** 60s orbit, 1.2° amplitude. Off on dense surfaces.

**Under reduced motion** (`CameoAnimationCurves.asReducedMotion`): all motion stopped; transitions snap instantly. Real 3D rendering stays (character is still 3D, just static).

**Forbidden** (V2 §1, enforced by `CameoQualityGates.verifyAnimationWithinBounds`):
- Bounce / overshoot curves on the character.
- Game-idle weight-shift loops.
- "Look at camera then look away" head animation loops.
- Lip-sync without audio.
- Procedural fidgeting.

---

## 9. Responsive (request: no clipping, stretching, accidental zoom, overflow, layout shift, broken aspect ratios, forced viewport)

`CameoResponsiveRules` per surface. Safety invariants (enforced by `CameoQualityGates.verifyResponsiveSafetyInvariants`):
- `allowStretch` — **always false**.
- `allowCrop` — **always false**.
- `allowViewportForce` — **always false**.

The Cameo fits its container while preserving aspect ratio, clamped to per-breakpoint max sizes (desktop / tablet / mobile). Letterboxing fills the remainder with the warm vignette.

---

## 10. Accessibility (V2 §66, §67)

`CameoAccessibilityRules` per surface:
- `requiresSemanticLabel` — true everywhere.
- `minContrastRatio` — 4.5 (WCAG AA normal text).
- `allowsTraitEditing` — true only on Studio.
- `allowsSharing` — false on all surfaces (sharing happens elsewhere).

`CameoAccessibilityRules.buildSemanticLabel(...)` produces e.g. `"Cameo of Aaji, in memoriam, elder, reverent, grandmother, memorial softLight."`

Reduced motion is read from `MediaQuery.disableAnimationsOf(context)` and routed through `CameoAnimationPresets.resolve(reduceMotion: ...)`.

---

## 11. The fallback portrait (`CameoAvatar` + `CameoPortraitPainter`)

`CameoAvatar` is the production-grade widget that renders the deterministic Kinrel fallback portrait. It:

1. Resolves a complete `ResolvedCameoStyle` via `CameoStyleSystem.resolve`.
2. Scales responsively per `CameoResponsiveRules` — never clips, never stretches.
3. Paints via `CameoPortraitPainter` — warm ivory key + ember rim, soft rounded silhouette, age-aware skin/hair, vignette backdrop, expression-aware mouth.
4. Animates subtly (breathing + blink + saccade) when enabled, with full reduced-motion support via a `Ticker` that stops when motion is off.
5. Provides a screen-reader semantic label.
6. Fails gracefully: a dignified monogram fallback (initials on vignette) if the painter ever throws — never a broken-image icon.

It is the V2 §3.6 / §39.3 fallback, built today. When the B1 prototype gate passes and real 3D characters replace it, this widget remains as the offline / load-failure / no-Cameo fallback for the lifetime of the app.

---

## 12. Wiring into the existing app

The existing `CachedAvatar` and `InitialsAvatar` widgets (in `lib/core/widgets/cached_avatar.dart`) now accept an optional `cameoFallback` parameter of type `CameoFallbackConfig`.

- **When `imageUrl` is null/empty AND `cameoFallback` is provided** → renders `CameoAvatar`.
- **When `imageUrl` is null/empty AND `cameoFallback` is null** → legacy person-icon / initials fallback (100% preserved).
- **When `imageUrl` is non-null** → existing image path (100% preserved, `cameoFallback` ignored).

This is the minimal, non-breaking wiring. The 12 existing `CachedAvatar` call sites in the repo are untouched.

---

## 13. Quality gates (CI-checkable)

`CameoQualityGates.verifyAll()` runs 9 structural checks:

1. `signature_pair_present` — every lighting preset carries ivory key + ember rim.
2. `responsive_safety_invariants` — no preset allows stretch/crop/viewport-force.
3. `child_safety_rules` — minor bands reject forbidden traits.
4. `memorial_defaults` — defaults are softLight, never candleGlow.
5. `no_banned_live_3d_surfaces` — Map/Graph/Chat/Timeline are derived PNG only.
6. `expression_catalog_in_range` — morph weights in [0, 1].
7. `animation_within_bounds` — no bouncing, no flutter, no oversized drift.
8. `camera_frames_valid` — FOV in [24°, 35°], zoom in [0.5×, 2.0×].
9. `scene_density_bounded` — face width in [0.28, 0.65], no foreground clutter.

CI should run `flutter test test/features/cameo/style/cameo_style_system_test.dart` on every PR that touches `lib/features/cameo/`. The test file verifies all 9 gates pass + the resolver produces a complete `ResolvedCameoStyle` for all 7 surfaces × 8 age bands (56 combinations).

---

## 14. What remains gated (honest scope)

This deliverable does NOT include:
- The Blender character art (base mesh, skeleton, 24 face morphs, 8 age morphs, hair, clothing, jewellery, accessories).
- The `three_js` runtime integration (V2 B3a).
- The Cameo Studio UI (V2 B5).
- The PortraitRenderPipeline for derived PNGs (V2 B4).
- The backend endpoint + sync (V2 B6).
- The Family Map / Graph / Profile / Journey / Timeline / Chat integrations (V2 B7–B10).
- The performance hardening to 60 FPS on Samsung A12 (V2 B11).
- The Fair Pricing verification (V2 B12).

All of the above are gated behind the B1 prototype (Blender artist + 17 PASS criteria on Android/iOS/Web) per the approved `KINREL_AUDIT_TO_PRODUCTION_IMPLEMENTATION_PROMPT.md`. The style system + `CameoAvatar` shipped here is the foundational layer that ALL of those batches will consume directly — no rework, no parallel system.

---

## 15. File manifest

```
lib/features/cameo/
├── cameo.dart                                       # public barrel
├── style/
│   ├── cameo_style_system.dart                      # the single deterministic governor
│   ├── cameo_color_palette.dart                     # signature pair + 10 skin tones + state tints
│   ├── cameo_shape_language.dart                    # proportions, eye geometry, silhouette rules + CameoAgeBand
│   ├── cameo_lighting_presets.dart                  # 6 presets (studio, profile, journey, derivedPng, memorialSoft, memorialCandle)
│   ├── cameo_material_specs.dart                    # skin/hair/eye/cloth/metal PBR params
│   ├── cameo_expression_catalog.dart                # 7 expressions (neutral, slightSmile, gentleSmile, reverent, softSurprise, tender, blink)
│   ├── cameo_pose_catalog.dart                      # 5 poses (centered, threeQuarter, dignified, dignifiedStooped, journeyWalk)
│   ├── cameo_camera_rules.dart                      # 7 camera presets per surface
│   ├── cameo_scene_density_rules.dart               # 7 scene-density presets per surface
│   ├── cameo_animation_curves.dart                  # 7 animation presets + reduced-motion + low-tier
│   ├── cameo_responsive_rules.dart                  # 7 responsive presets + breakpoint helper
│   ├── cameo_accessibility_rules.dart               # 7 a11y presets + child-safety rules + semantic-label builder
│   └── cameo_quality_gates.dart                     # 9 CI-checkable quality gates
└── presentation/
    ├── painters/
    │   └── cameo_portrait_painter.dart              # the deterministic Kinrel fallback portrait
    └── widgets/
        ├── cameo_avatar.dart                        # the production-grade Cameo widget
        └── cameo_fallback_config.dart               # the optional config for CachedAvatar/InitialsAvatar

test/features/cameo/
├── style/
│   └── cameo_style_system_test.dart                 # 56-combo resolver test + 9 quality gates + catalog tests
└── presentation/
    └── cameo_avatar_test.dart                       # widget mount + semantics + CachedAvatar wiring + no-regression

lib/core/widgets/cached_avatar.dart                  # MODIFIED: + optional cameoFallback param (no regression)

docs/cameo/
└── KINREL_CAMEO_STYLE_SYSTEM.md                     # this file
```

---

## 16. Usage

### Standalone CameoAvatar

```dart
import 'package:kinrel/features/cameo/cameo.dart';

CameoAvatar(
  personName: 'Aaji',
  ageBand: CameoAgeBand.elder,
  skinToneIndex: 7,
  surfaceId: 'profile_hero',
  isDeceased: true,
  memorialAtmosphere: 'softLight',
)
```

### CachedAvatar with Cameo fallback (opt-in, no regression)

```dart
import 'package:kinrel/core/widgets/cached_avatar.dart';
import 'package:kinrel/features/cameo/cameo.dart';

CachedAvatar(
  imageUrl: person.photoUrl,
  radius: 32,
  cameoFallback: person.photoUrl == null
      ? CameoFallbackConfig(
          personName: person.name,
          ageBand: _ageBandFromPerson(person),
          skinToneIndex: person.cameoSkinTone ?? 5,
          surfaceId: 'profile_hero',
          isDeceased: person.isDeceased,
        )
      : null,
)
```

### Programmatic style resolution (for future 3D runtime)

```dart
import 'package:kinrel/features/cameo/cameo.dart';

final resolved = CameoStyleSystem.resolve(
  surfaceId: 'studio',
  personName: 'Aaji',
  ageBand: CameoAgeBand.elder,
  skinToneIndex: 7,
  breakpoint: cameoBreakpointForWidth(viewportWidth),
  containerSize: viewportSize,
);

// resolved.lighting        → CameoLightingPreset (key, fill, rim, ambient, ibl, accent)
// resolved.camera          → CameoCameraRules (fov, yaw/pitch/zoom ranges)
// resolved.animation       → CameoAnimationCurves (breathing, blink, saccade timings)
// resolved.responsive      → CameoResponsiveRules (aspect, sizes, safety invariants)
// resolved.sceneDensity    → CameoSceneDensityRules (face width, vignette, floor)
// resolved.accessibility   → CameoAccessibilityRules (contrast, semantic label)
// resolved.skinMaterial    → CameoSkinMaterial (base, roughness, SSS)
// resolved.expression      → CameoExpression (morph weights)
// resolved.pose            → CameoPose (bone rotations)
// resolved.effectiveRenderSize → Size
// resolved.semanticLabel   → String
```

### Quality gate verification (CI)

```dart
import 'package:kinrel/features/cameo/cameo.dart';

final report = CameoStyleSystem.verifyAll();
if (!report.allPassed) {
  print(report);
  exit(1);
}
```
