// lib/features/cameo/style/cameo_color_palette.dart
//
// KINREL CAMEO — Color Palette
//
// The single deterministic color source for every Cameo surface (live 3D,
// derived PNG, fallback portrait, Studio chrome, lighting tints, state
// overlays). Grounded in the existing KinrelColors brand system — NOT a
// parallel palette. Every token here either re-exports a KinrelColors
// value or derives from one via a documented transform, so the Cameo
// visual language is unmistakably Kinrel.
//
// SIGNATURE PAIR (from V2 §5.2 + the existing brand):
//   • Warm Ivory key light   — the soft, heirloom glow on every face
//   • Ember Rim              — the Burnt-Ember (#C44A18) hair-line that
//                              separates the character from the background
//
// These two are the recognizable Kinrel Cameo signature. They appear on
// every Cameo regardless of skin tone, clothing, age, or surface (live
// 3D, derived PNG, fallback portrait). Do not ship a Cameo without them.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';

/// Deterministic color palette for the Kinrel Cameo system.
///
/// All members are `const`. This class is the single source of truth —
/// painters, renderers, and widgets MUST source Cameo colors from here,
/// not from ad-hoc `Color(0xFF...)` literals. This keeps every Cameo
/// visually coherent and makes the signature identifiable without the logo.
@immutable
class CameoColorPalette {
  const CameoColorPalette._();

  // ── Signature Lighting Tints ────────────────────────────────────────
  //
  // These are the COLOR OF THE LIGHT, not the color of the material.
  // They tint whatever they illuminate. They are the Kinrel signature.

  /// Warm Ivory key light. Soft, heirloom, slightly cream.
  /// Used as the dominant face light on every Cameo.
  static const Color keyLightIvory = Color(0xFFFFF4E0);

  /// Cool fill light. A desaturated teal-white that fills shadows
  /// without muddying the ivory key. Keeps faces readable at UI size.
  static const Color fillLightCool = Color(0xFFD8E6E6);

  /// Ember Rim. The Burnt-Ember hair-line that separates character
  /// from background. Re-uses the brand ember so the rim reads as Kinrel.
  static const Color rimLightEmber = KinrelColors.ember;

  /// Warm ambient. A very low-intensity warm wash that lifts the
  /// shadow side without flattening the form.
  static const Color ambientWarm = Color(0xFF2A1F18);

  /// Image-Based Lighting tint. A neutral-warm that the HDRI environment
  /// casts on metallic and dielectric surfaces alike.
  static const Color iblTint = Color(0xFFE8D9C4);

  // ── Skin Tone Palette (V2 §17.4 — 10 tones) ─────────────────────────
  //
  // Each tone is a base hue + a roughness/melanin hint. The actual PBR
  // material (B3a) consumes these as the LUT anchor; the fallback
  // portrait painter ( CameoPortraitPainter ) consumes them directly as
  // the radial-gradient center color. Tones are calibrated to read as
  // dignified, never ashen, never oversaturated, on the warm-ivory key.

  /// Tone 1 — Lightest. Warm porcelain.
  static const Color skinTone1 = Color(0xFFF7E6D4);

  /// Tone 2 — Fair warm.
  static const Color skinTone2 = Color(0xFFF1D7BC);

  /// Tone 3 — Light wheat.
  static const Color skinTone3 = Color(0xFFE6C39A);

  /// Tone 4 — Medium-light.
  static const Color skinTone4 = Color(0xFFD9A878);

  /// Tone 5 — Medium (V2 §75.2 prototype tone).
  static const Color skinTone5 = Color(0xFFC68A52);

  /// Tone 6 — Medium-deep.
  static const Color skinTone6 = Color(0xFFAE6E3C);

  /// Tone 7 — Deep (V2 §76.1 criterion 11 swap target).
  static const Color skinTone7 = Color(0xFF8F5530);

  /// Tone 8 — Deep-rich.
  static const Color skinTone8 = Color(0xFF734226);

  /// Tone 9 — Darkest-brown.
  static const Color skinTone9 = Color(0xFF5A3019);

  /// Tone 10 — Deepest. Warm espresso.
  static const Color skinTone10 = Color(0xFF422318);

  /// All 10 skin tones in index order (1-based → index 0 = tone 1).
  static const List<Color> skinTones = <Color>[
    skinTone1,
    skinTone2,
    skinTone3,
    skinTone4,
    skinTone5,
    skinTone6,
    skinTone7,
    skinTone8,
    skinTone9,
    skinTone10,
  ];

  /// Returns a skin tone by 1-based index, clamped to [1, 10].
  static Color skinTone(int toneIndex) {
    if (toneIndex < 1) return skinTone1;
    if (toneIndex > 10) return skinTone10;
    return skinTones[toneIndex - 1];
  }

  // ── Hair Color Palette ──────────────────────────────────────────────
  //
  // Naturalistic Indian-first hair colors. No fantasy colors. Greying
  // is handled by mixing toward [hairGrey] per age band (V2 §15.5),
  // not by adding new swatches.

  static const Color hairJet = Color(0xFF1A1410);
  static const Color hairBlack = Color(0xFF2A2018);
  static const Color hairDarkBrown = Color(0xFF3D2A1C);
  static const Color hairBrown = Color(0xFF5A3E2A);
  static const Color hairAuburn = Color(0xFF6E3A22);
  static const Color hairGrey = Color(0xFFB8AEA4);
  static const Color hairWhite = Color(0xFFEDE6DC);

  static const List<Color> hairColors = <Color>[
    hairJet,
    hairBlack,
    hairDarkBrown,
    hairBrown,
    hairAuburn,
    hairGrey,
    hairWhite,
  ];

  // ── Eye Color Palette ───────────────────────────────────────────────

  static const Color eyeDarkBrown = Color(0xFF2A1A0E);
  static const Color eyeBrown = Color(0xFF4A2E18);
  static const Color eyeHazel = Color(0xFF6E4A28);
  static const Color eyeAmber = Color(0xFF8A5A2A);
  static const Color eyeGreen = Color(0xFF3A5A3A);

  static const List<Color> eyeColors = <Color>[
    eyeDarkBrown,
    eyeBrown,
    eyeHazel,
    eyeAmber,
    eyeGreen,
  ];

  // ── Scene Backdrop ──────────────────────────────────────────────────
  //
  // The vignette behind every Cameo. Dark, warm, heirloom — never pure
  // black, never cool grey. This is the "dark vignette (signature)"
  // from V2 §71.1.

  /// Vignette center — warm dark, never pure black.
  static const Color vignetteCenter = Color(0xFF1B1410);

  /// Vignette edge — deeper, slightly cooler, for the radial falloff.
  static const Color vignetteEdge = Color(0xFF0A0806);

  /// Vignette gradient (radial, center → edge).
  static const List<Color> vignetteGradient = <Color>[
    vignetteCenter,
    vignetteEdge,
  ];

  // ── State Overlay Tints (V2 §44 — UI overlays, NOT character mutation) ──
  //
  // These tint the BACKGROUND or the RIM, never the character's skin.
  // A birthday Cameo does not turn pink; the rim gains a marigold kiss.

  /// Birthday — marigold rim kiss.
  static const Color stateBirthday = Color(0xFFFFB347);

  /// Memorial — soft, reverent cool-ivory rim. Never sepia-candle
  /// unless the family explicitly chose candleGlow (V2 §16.3, §45).
  static const Color stateMemorialSoft = Color(0xFFD8E6E6);

  /// Memorial — candle glow (family-opted only).
  static const Color stateMemorialCandle = Color(0xFFFF9A4A);

  /// Festival — deep marigold + a hint of magenta.
  static const Color stateFestival = Color(0xFFE8612A);

  /// Wedding — rose gold.
  static const Color stateWedding = Color(0xFFE8B4A8);

  /// New baby — soft marigold.
  static const Color stateNewBaby = Color(0xFFFFD08A);

  /// Graduation — warm gold.
  static const Color stateGraduation = KinrelColors.gold;

  // ── Clothing Neutral Base ───────────────────────────────────────────
  //
  // A restrained neutral clothing palette so the face and the ivory key
  // remain the focal point. Cultural garments (saree, kurta, dhoti) use
  // their own production colors (Art A4); these neutrals are for
  // undergarments, generic tees, and fallback wardrobe.

  static const Color clothIvory = Color(0xFFEDE2CC);
  static const Color clothSand = Color(0xFFD4C4A8);
  static const Color clothClay = Color(0xFFA88A6A);
  static const Color clothSlate = Color(0xFF4A4650);
  static const Color clothCharcoal = Color(0xFF2A282E);

  // ── Metal / Jewellery ───────────────────────────────────────────────

  /// Polished gold for earrings, mangalsutra, bangles.
  static const Color metalGold = KinrelColors.gold;

  /// Warm highlight on gold.
  static const Color metalGoldHighlight = Color(0xFFFFE8A8);

  /// Polished silver.
  static const Color metalSilver = Color(0xFFC8C8D0);

  /// Copper (used for regional jewelry).
  static const Color metalCopper = Color(0xFFB87333);

  // ── Derived Convenience ─────────────────────────────────────────────

  /// The signature pair, in render order: key first, rim second.
  static const List<Color> signaturePair = <Color>[
    keyLightIvory,
    rimLightEmber,
  ];

  /// True if a color is approximately one of the signature colors.
  /// Used by quality gates (CameoQualityGates) to verify a render
  /// actually carries the Kinrel signature.
  static bool isSignatureColor(Color c) {
    return _approx(c, keyLightIvory, tolerance: 12) ||
        _approx(c, rimLightEmber, tolerance: 12);
  }

  static bool _approx(Color a, Color b, {required int tolerance}) {
    return (a.red - b.red).abs() <= tolerance &&
        (a.green - b.green).abs() <= tolerance &&
        (a.blue - b.blue).abs() <= tolerance;
  }
}
