// lib/features/cameo/style/cameo_accessibility_rules.dart
//
// KINREL CAMEO — Accessibility Rules
//
// Deterministic a11y rules for every Cameo surface (V2 §66, §67, §70).
// These rules are consumed by the CameoAvatar widget and by the 3D
// runtime to ensure:
//   • Screen readers announce a Cameo correctly (name + age band +
//     expression + relationship context).
//   • Reduced motion disables ALL animation (V2 §67).
//   • Color contrast meets WCAG AA on every surface.
//   • Children's Cameos cannot have adult traits (V2 §70.1).
//   • Children's Cameos are not shareable outside family (V2 §70.2).
//   • Deceased minors default to softLight memorial, never candleGlow
//     (V2 §70.3).

import 'package:flutter/material.dart';

import '../../../core/constants/wcag_contrast.dart' as wcag;
import 'cameo_shape_language.dart';

/// Deterministic a11y rules for a Cameo surface.
@immutable
class CameoAccessibilityRules {
  const CameoAccessibilityRules({
    required this.surfaceId,
    required this.minContrastRatio,
    required this.requiresSemanticLabel,
    required this.allowsTraitEditing,
    required this.allowsSharing,
  });

  final String surfaceId;

  /// Minimum WCAG contrast ratio for text overlaid on the Cameo.
  final double minContrastRatio;

  /// Whether the surface requires a semantic label (e.g., screen reader).
  final bool requiresSemanticLabel;

  /// Whether the user can edit traits on this surface.
  final bool allowsTraitEditing;

  /// Whether the Cameo can be shared from this surface.
  final bool allowsSharing;

  /// Builds the semantic label for a Cameo, given its context.
  /// Example: "Cameo of Aaji, elder, slight smile, grandmother."
  static String buildSemanticLabel({
    required String personName,
    required CameoAgeBand ageBand,
    required String expressionLabel,
    String? relationshipLabel,
    bool isDeceased = false,
    String? memorialAtmosphere,
  }) {
    final parts = <String>['Cameo of $personName'];

    if (isDeceased) {
      parts.add('in memoriam');
    }
    parts.add(ageBand.semanticLabel);
    parts.add(expressionLabel);
    if (relationshipLabel != null && relationshipLabel.isNotEmpty) {
      parts.add(relationshipLabel);
    }
    if (memorialAtmosphere != null && memorialAtmosphere.isNotEmpty) {
      parts.add('memorial $memorialAtmosphere');
    }

    return '${parts.join(', ')}.';
  }

  /// Returns true if a foreground/background color pair meets contrast.
  static bool meetsContrast(
    Color foreground,
    Color background, {
    required double minRatio,
  }) {
    final ratio = wcag.contrastRatio(foreground, background);
    return ratio >= minRatio;
  }
}

/// Child-safety rules (V2 §70).
@immutable
class CameoChildSafetyRules {
  const CameoChildSafetyRules._();

  /// Returns true if the age band is a minor (baby, child, teenager).
  static bool isMinor(CameoAgeBand band) {
    return band == CameoAgeBand.baby ||
        band == CameoAgeBand.child ||
        band == CameoAgeBand.teenager;
  }

  /// Traits that are FORBIDDEN for minor Cameos (V2 §70.1).
  static const List<String> forbiddenTraitsForMinors = <String>[
    'facial_hair_beard',
    'facial_hair_mustache',
    'facial_hair_stubble',
    'accessory_sindoor_non_wedding',
    'jewellery_heavy_earrings',
    'jewellery_mangalsutra',
  ];

  /// Returns true if a trait id is allowed for the given age band.
  static bool isTraitAllowedForAgeBand(String traitId, CameoAgeBand band) {
    if (!isMinor(band)) return true;
    return !forbiddenTraitsForMinors.contains(traitId);
  }

  /// Returns the default memorial atmosphere for a deceased person.
  /// V2 §70.3: deceased minors default to softLight (not candleGlow).
  /// V2 §16.3: deceased adults default to softLight too (candleGlow is
  /// family-opted only).
  static String defaultMemorialAtmosphere(CameoAgeBand band) {
    return 'softLight'; // always softLight by default; candleGlow is family-opted
  }

  /// V2 §70.2: minors' Cameos are forced to privacy level 'family'.
  static const String minorPrivacyLevel = 'family';
}

/// The deterministic library of approved a11y rules.
@immutable
class CameoAccessibilityLibrary {
  const CameoAccessibilityLibrary._();

  /// Studio — full a11y, trait editing on, sharing off (Studio is
  /// edit-only; sharing happens elsewhere).
  static const CameoAccessibilityRules studio = CameoAccessibilityRules(
    surfaceId: 'studio',
    minContrastRatio: 4.5, // WCAG AA normal text
    requiresSemanticLabel: true,
    allowsTraitEditing: true,
    allowsSharing: false,
  );

  /// Profile hero — a11y on, no editing (tap to open Studio), no sharing.
  static const CameoAccessibilityRules profileHero = CameoAccessibilityRules(
    surfaceId: 'profile_hero',
    minContrastRatio: 4.5,
    requiresSemanticLabel: true,
    allowsTraitEditing: false,
    allowsSharing: false,
  );

  /// Family Map marker — a11y on, no editing, no sharing.
  static const CameoAccessibilityRules mapMarker = CameoAccessibilityRules(
    surfaceId: 'map_marker',
    minContrastRatio: 4.5,
    requiresSemanticLabel: true,
    allowsTraitEditing: false,
    allowsSharing: false,
  );

  /// Family Graph node — a11y on, no editing, no sharing.
  static const CameoAccessibilityRules graphNode = CameoAccessibilityRules(
    surfaceId: 'graph_node',
    minContrastRatio: 4.5,
    requiresSemanticLabel: true,
    allowsTraitEditing: false,
    allowsSharing: false,
  );

  /// Chat avatar — a11y on, no editing, no sharing.
  static const CameoAccessibilityRules chatAvatar = CameoAccessibilityRules(
    surfaceId: 'chat_avatar',
    minContrastRatio: 4.5,
    requiresSemanticLabel: true,
    allowsTraitEditing: false,
    allowsSharing: false,
  );

  /// Journey cinematic — a11y on (described), no editing, no sharing.
  static const CameoAccessibilityRules journey = CameoAccessibilityRules(
    surfaceId: 'journey',
    minContrastRatio: 4.5,
    requiresSemanticLabel: true,
    allowsTraitEditing: false,
    allowsSharing: false,
  );

  /// Timeline card — a11y on, no editing, no sharing.
  static const CameoAccessibilityRules timelineCard = CameoAccessibilityRules(
    surfaceId: 'timeline_card',
    minContrastRatio: 4.5,
    requiresSemanticLabel: true,
    allowsTraitEditing: false,
    allowsSharing: false,
  );

  /// All approved a11y presets.
  static const List<CameoAccessibilityRules> all = <CameoAccessibilityRules>[
    studio,
    profileHero,
    mapMarker,
    graphNode,
    chatAvatar,
    journey,
    timelineCard,
  ];

  /// Look up by surface id. Returns [studio] as the safe default.
  static CameoAccessibilityRules byId(String surfaceId) {
    for (final a in all) {
      if (a.surfaceId == surfaceId) return a;
    }
    return studio;
  }
}
