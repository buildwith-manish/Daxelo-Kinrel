// lib/features/cameo/style/cameo_shape_language.dart
//
// KINREL CAMEO — Shape Language
//
// The deterministic rules that make every Cameo read as the SAME
// character world: soft, rounded, sculptural, heirloom — never game-y,
// never mascot-y, never stock-avatar flat.
//
// These rules are consumed by:
//   • The 3D base mesh artist (Art A1) — topology edge loops, joint
//     radii, silhouette targets.
//   • The fallback portrait painter (CameoPortraitPainter) — the
//     silhouette it paints MUST match these rules so the fallback reads
//     as the same world as the eventual 3D character.
//   • The quality gates (CameoQualityGates) — verifies the rendered
//     silhouette respects the radius/aspect budget.
//
// PRINCIPLE: A Cameo is a LIVING FAMILY MINIATURE (V2 §4). It is a
// sculpted heirloom portrait, not a sticker. Softness comes from
// large radius transitions and gentle curvature, not from blur.

import 'package:flutter/material.dart';

import 'cameo_color_palette.dart';

/// Deterministic shape-language rules for every Kinrel Cameo.
@immutable
class CameoShapeLanguage {
  const CameoShapeLanguage._();

  // ── Head Proportions (V2 §11.2, §71.1 — naturalistic 1:7) ───────────
  //
  // Naturalistic, not chibi. 1:7 head-to-body ratio (V2 §71.1).
  // The head is the focal point at UI size, so the head fill and the
  // jaw roundness are the most recognizable Cameo signals.

  /// Head-to-body ratio. 1:7 naturalistic (V2 §71.1).
  /// Bitmoji ≈ 1:3 (exaggerated) — explicitly NOT Kinrel.
  static const double headToBodyRatio = 1.0 / 7.0;

  /// Head width as a fraction of head height (slightly narrower than
  /// round; dignified, not cartoonish).
  static const double headWidthToHeight = 0.72;

  /// Jaw corner radius as a fraction of head width. Soft but not
  /// infantile — the jaw reads as sculpted, not as a bean.
  static const double jawRadiusFraction = 0.32;

  /// Cheekbone prominence (0 = flat, 1 = sharp). Kinrel is mid-low:
  /// soft, warm, with structure visible under the ivory key.
  static const double cheekboneProminence = 0.38;

  /// Brow ridge prominence. Low-mid: present but never blocky.
  static const double browRidgeProminence = 0.34;

  /// Nose bridge width fraction (of head width). Narrow-soft.
  static const double noseBridgeWidthFraction = 0.085;

  /// Lip fullness (0 = thin, 1 = full). Mid — naturalistic, not stylized.
  static const double lipFullness = 0.5;

  // ── Eye Geometry (V2 §18 — readable eye direction) ──────────────────
  //
  // The eyes carry the emotion. They are the second-most recognizable
  // Kinrel signal after the ivory+ember lighting. Readable eye
  // direction (V2 request) means: iris visible, catchlight present,
  // sclera warm (never pure white), upper lid naturally hooded.

  /// Eye width as a fraction of head width. One eye-width between
  /// the eyes (classical proportion) — reads as natural, not stylized.
  static const double eyeWidthFraction = 0.22;

  /// Eye height as a fraction of eye width. Almond — not round.
  static const double eyeHeightToWidth = 0.42;

  /// Iris diameter as a fraction of eye width. Large enough to read
  /// direction at UI size; small enough to avoid anime.
  static const double irisDiameterFraction = 0.62;

  /// Catchlight radius as a fraction of iris diameter. Tiny, sharp,
  /// top-left (matches GraphLighting.lightSource).
  static const double catchlightRadiusFraction = 0.18;

  /// Sclera color — warm, never pure white. Pure white reads as
  /// uncanny / health-issue. This is a desaturated ivory.
  static const Color scleraColor = Color(0xFFF2EADC);

  /// Upper-lid hood fraction (0 = none, 1 = fully hooded). Naturalistic
  /// mid — the lid reads as a soft shadow, not a sticker line.
  static const double upperLidHoodFraction = 0.28;

  // ── Body Silhouette (V2 §21 — soft rounded geometry) ───────────────
  //
  // Soft rounded geometry is the explicit design directive. Shoulders
  // are rounded, not square; the torso tapers gently; limbs have
  // visible but soft muscle/fat distribution; no sharp angles.

  /// Shoulder corner radius as a fraction of shoulder width.
  static const double shoulderRadiusFraction = 0.42;

  /// Shoulder width as a fraction of head width (naturalistic).
  static const double shoulderToHeadWidth = 2.2;

  /// Torso taper (0 = cylindrical, 1 = sharply V-tapered). Kinrel is
  /// gentle — a soft V for adults, near-cylindrical for children.
  static const double torsoTaperAdult = 0.22;
  static const double torsoTaperChild = 0.06;

  /// Limb softness (0 = skeletal, 1 = padded). Kinrel is mid-high:
  /// the limbs read as flesh, not as sticks.
  static const double limbSoftness = 0.62;

  // ── Hair Silhouette (V2 §19 — hair cards, real geometry) ───────────
  //
  // Hair is real geometry in 3D (hair cards, V2 §19.2). In the fallback
  // painter, hair is a soft silhouette that respects these rules so it
  // reads as the same hair world.

  /// Hair volume above skull as a fraction of head height.
  static const double hairVolumeFraction = 0.14;

  /// Hair silhouette edge softness (0 = hard, 1 = wispy). Kinrel is
  /// soft — wispy edges, never helmet hair.
  static const double hairEdgeSoftness = 0.55;

  /// Hair part straightness (0 = messy, 1 = ruler-straight). Kinrel
  /// is natural — soft part, never surgical.
  static const double hairPartStraightness = 0.40;

  // ── Clothing Silhouette (V2 §22 — modular skinned meshes) ──────────
  //
  // Clothing follows the body, never replaces it. Drape is soft;
  /// folds are few and large; no busy micro-folds.

  /// Clothing drape factor (0 = skin-tight, 1 = free-flowing).
  /// Indian garments (saree, dhoti, kurta) lean high; western lean low.
  static const double drapeIndian = 0.72;
  static const double drapeWestern = 0.22;

  /// Fold count budget per garment (large readable folds only).
  static const int foldBudgetPerGarment = 5;

  // ── Age Band Shape Shifts (V2 §15 — real age progression) ───────────
  //
  // Each age band shifts the silhouette deterministically. These are
  // consumed by the 3D age morphs (Art A2) and by the fallback painter
  // (which picks a different silhouette template per band).

  /// Returns the head-width scale for an age band (1.0 = adult).
  /// Babies have larger heads relative to body; elders slightly narrower.
  static double headWidthScaleForAgeBand(CameoAgeBand band) {
    switch (band) {
      case CameoAgeBand.baby:        return 1.18;
      case CameoAgeBand.child:       return 1.10;
      case CameoAgeBand.teenager:    return 1.04;
      case CameoAgeBand.youngAdult:  return 1.00;
      case CameoAgeBand.adult:       return 0.99;
      case CameoAgeBand.middleAged:  return 0.98;
      case CameoAgeBand.senior:      return 0.97;
      case CameoAgeBand.elder:       return 0.96;
    }
  }

  /// Returns the jaw softness for an age band (1.0 = young-adult baseline).
  /// Jaws soften with age; babies are roundest.
  static double jawSoftnessForAgeBand(CameoAgeBand band) {
    switch (band) {
      case CameoAgeBand.baby:        return 1.30;
      case CameoAgeBand.child:       return 1.18;
      case CameoAgeBand.teenager:    return 1.06;
      case CameoAgeBand.youngAdult:  return 1.00;
      case CameoAgeBand.adult:       return 0.94;
      case CameoAgeBand.middleAged:  return 0.88;
      case CameoAgeBand.senior:      return 0.82;
      case CameoAgeBand.elder:       return 0.76;
    }
  }

  /// Returns the posture droop for an age band (0 = upright, 1 = stooped).
  /// V2 §15.7 — posture softens with age, never cartoonishly.
  static double postureDroopForAgeBand(CameoAgeBand band) {
    switch (band) {
      case CameoAgeBand.baby:        return 0.00;
      case CameoAgeBand.child:       return 0.00;
      case CameoAgeBand.teenager:    return 0.02;
      case CameoAgeBand.youngAdult:  return 0.04;
      case CameoAgeBand.adult:       return 0.08;
      case CameoAgeBand.middleAged:  return 0.14;
      case CameoAgeBand.senior:      return 0.22;
      case CameoAgeBand.elder:       return 0.30;
    }
  }
}

/// The 8 age bands (V2 §15.3). Used across shape language, lighting,
/// and animation. Deterministic enum — no stringly-typed age bands.
enum CameoAgeBand {
  baby,       // 0–2
  child,      // 3–12
  teenager,   // 13–17
  youngAdult, // 18–29
  adult,      // 30–44
  middleAged, // 45–59
  senior,     // 60–74
  elder,      // 75+
}

/// Extension: human-readable label (used by a11y semantic labels).
extension CameoAgeBandLabel on CameoAgeBand {
  String get semanticLabel {
    switch (this) {
      case CameoAgeBand.baby:        return 'baby';
      case CameoAgeBand.child:       return 'child';
      case CameoAgeBand.teenager:    return 'teenager';
      case CameoAgeBand.youngAdult:  return 'young adult';
      case CameoAgeBand.adult:       return 'adult';
      case CameoAgeBand.middleAged:  return 'middle-aged';
      case CameoAgeBand.senior:      return 'senior';
      case CameoAgeBand.elder:       return 'elder';
    }
  }
}
