// lib/features/cameo/style/cameo_expression_catalog.dart
//
// KINREL CAMEO — Facial Expression Catalog
//
// Deterministic expression presets governing every Cameo face.
// V2 §33 — expression is a CharacterState (NOT a character mutation).
// Expressions are subtle and naturalistic, never uncanny:
//   • A smile is a slight lip-corner lift + tiny eye crinkle — never
//     a grinned vector mask.
//   • A blink is a 110ms lid close + 220ms lid open — never a sticker.
//   • A reverent expression lowers the lid 30% and softens the brow —
//     never a frozen stare.
//
// Every expression is defined as a Morph Target Weight Map (MTWM):
// a map from morph target name → weight in [0, 1]. The 3D runtime
// (B3a) applies these to the SkinnedMesh; the fallback painter
// (CameoPortraitPainter) approximates them in 2D.

import 'package:flutter/material.dart';

/// A single facial expression, defined as morph target weights.
@immutable
class CameoExpression {
  const CameoExpression({
    required this.id,
    required this.displayName,
    required this.morphWeights,
    this.blinkOverride = false,
    this.saccadeOverride = const Offset(0, 0),
  });

  final String id;
  final String displayName;

  /// Map from morph target name → weight in [0, 1].
  /// Unknown morph names are ignored by the resolver (graceful).
  final Map<String, double> morphWeights;

  /// If true, the eyes are held closed (e.g., for a blink frame).
  final bool blinkOverride;

  /// Fixed iris offset (overrides saccade). Used for "looking at" cues.
  final Offset saccadeOverride;

  /// Linear blend between two expressions (used for transitions).
  CameoExpression lerpTo(CameoExpression other, double t) {
    final keys = <String>{...morphWeights.keys, ...other.morphWeights.keys};
    final blended = <String, double>{};
    for (final k in keys) {
      final a = morphWeights[k] ?? 0.0;
      final b = other.morphWeights[k] ?? 0.0;
      blended[k] = a + (b - a) * t;
    }
    return CameoExpression(
      id: t < 0.5 ? id : other.id,
      displayName: t < 0.5 ? displayName : other.displayName,
      morphWeights: blended,
      blinkOverride: t < 0.5 ? blinkOverride : other.blinkOverride,
      saccadeOverride: Offset(
        saccadeOverride.dx +
            (other.saccadeOverride.dx - saccadeOverride.dx) * t,
        saccadeOverride.dy +
            (other.saccadeOverride.dy - saccadeOverride.dy) * t,
      ),
    );
  }
}

/// The deterministic library of approved Cameo expressions.
///
/// A surface must pick from this catalog; ad-hoc expressions are
/// forbidden by the quality gates. New expressions must be added here
/// (with a code review) so the Kinrel expression range stays coherent.
@immutable
class CameoExpressionCatalog {
  const CameoExpressionCatalog._();

  /// Neutral — the resting face. Used 90% of the time.
  static const CameoExpression neutral = CameoExpression(
    id: 'neutral',
    displayName: 'Neutral',
    morphWeights: <String, double>{'brow_inner_up': 0.05, 'mouth_relax': 0.85},
  );

  /// Slight smile — the default Kinrel warmth. NEVER a full grin.
  static const CameoExpression slightSmile = CameoExpression(
    id: 'slight_smile',
    displayName: 'Slight Smile',
    morphWeights: <String, double>{
      'mouth_corner_up': 0.32,
      'cheek_raise': 0.18,
      'eye_crinkle': 0.12,
      'brow_inner_up': 0.06,
    },
  );

  /// Gentle smile — for happy family moments.
  static const CameoExpression gentleSmile = CameoExpression(
    id: 'gentle_smile',
    displayName: 'Gentle Smile',
    morphWeights: <String, double>{
      'mouth_corner_up': 0.48,
      'cheek_raise': 0.28,
      'eye_crinkle': 0.20,
      'brow_inner_up': 0.08,
    },
  );

  /// Reverent — for memorial / tribute contexts. Lowered lid, soft brow.
  static const CameoExpression reverent = CameoExpression(
    id: 'reverent',
    displayName: 'Reverent',
    morphWeights: <String, double>{
      'upper_lid_lower': 0.30,
      'brow_inner_up': 0.12,
      'mouth_relax': 0.70,
      'mouth_corner_down': 0.06,
    },
  );

  /// Soft surprise — for "on this day" reveals.
  static const CameoExpression softSurprise = CameoExpression(
    id: 'soft_surprise',
    displayName: 'Soft Surprise',
    morphWeights: <String, double>{
      'brow_inner_up': 0.34,
      'brow_outer_up': 0.18,
      'eye_widen': 0.20,
      'mouth_relax': 0.60,
    },
  );

  /// Tender — for new-baby / wedding family events.
  static const CameoExpression tender = CameoExpression(
    id: 'tender',
    displayName: 'Tender',
    morphWeights: <String, double>{
      'mouth_corner_up': 0.28,
      'cheek_raise': 0.32,
      'eye_crinkle': 0.24,
      'upper_lid_lower': 0.12,
      'brow_inner_up': 0.10,
    },
  );

  /// Blink — single frame; used by the animation controller.
  static const CameoExpression blink = CameoExpression(
    id: 'blink',
    displayName: 'Blink',
    morphWeights: <String, double>{'eye_close': 1.0},
    blinkOverride: true,
  );

  /// All approved expressions in deterministic order.
  static const List<CameoExpression> all = <CameoExpression>[
    neutral,
    slightSmile,
    gentleSmile,
    reverent,
    softSurprise,
    tender,
    blink,
  ];

  /// Look up an expression by id. Returns [neutral] as the safe default.
  static CameoExpression byId(String id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return neutral;
  }

  /// Returns the default expression for a FamilyEventState.
  /// These pair with the lighting preset for the same state.
  static CameoExpression defaultForEvent(String? eventId) {
    switch (eventId) {
      case 'birthday':
      case 'graduation':
      case 'festival':
        return gentleSmile;
      case 'wedding':
      case 'new_baby':
        return tender;
      case 'memorial':
        return reverent;
      case null:
      default:
        return slightSmile;
    }
  }
}
