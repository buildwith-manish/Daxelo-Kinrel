// lib/features/cameo/data/cameo_definition.dart
//
// KINREL CAMEO — Character Definition Model
//
// The single source of truth for a Cameo character's appearance.
// V2 §26 — CameoDefinition V2 is the single source of truth.
// Derived PNGs are cache artifacts, regeneratable, never authoritative.
//
// This is a pure data model. It does NOT depend on any renderer.
// The renderer consumes this definition to build a 3D scene.

import 'package:flutter/foundation.dart';

/// The gender model for a Cameo character.
enum CameoGender { male, female, nonBinary, unspecified }

/// Personality vector (V2 §2.4) — drives idle animation variation.
@immutable
class CameoPersonality {
  const CameoPersonality({
    this.warmth = 0.5,
    this.reserve = 0.5,
    this.playfulness = 0.5,
    this.dignity = 0.5,
  });

  /// Higher = more frequent smile baseline + double-blinks.
  final double warmth;

  /// Higher = less head sway, slower saccades.
  final double reserve;

  /// Higher = more frequent soft_surprise micro-expressions.
  final double playfulness;

  /// Higher = less micro-motion overall, more reverent lid-lowers.
  final double dignity;

  /// Returns true if all values are in [0, 1].
  bool get isValid =>
      warmth >= 0 &&
      warmth <= 1 &&
      reserve >= 0 &&
      reserve <= 1 &&
      playfulness >= 0 &&
      playfulness <= 1 &&
      dignity >= 0 &&
      dignity <= 1;

  Map<String, dynamic> toJson() => {
    'warmth': warmth,
    'reserve': reserve,
    'playfulness': playfulness,
    'dignity': dignity,
  };

  factory CameoPersonality.fromJson(Map<String, dynamic> json) =>
      CameoPersonality(
        warmth: (json['warmth'] as num?)?.toDouble() ?? 0.5,
        reserve: (json['reserve'] as num?)?.toDouble() ?? 0.5,
        playfulness: (json['playfulness'] as num?)?.toDouble() ?? 0.5,
        dignity: (json['dignity'] as num?)?.toDouble() ?? 0.5,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameoPersonality &&
          warmth == other.warmth &&
          reserve == other.reserve &&
          playfulness == other.playfulness &&
          dignity == other.dignity;

  @override
  int get hashCode => Object.hash(warmth, reserve, playfulness, dignity);
}

/// Memorial preferences (V2 §45) — family-controlled, never automatic.
@immutable
class CameoMemorialPreferences {
  const CameoMemorialPreferences({
    this.atmosphere = 'softLight',
    this.candleGlow = false,
  });

  /// 'softLight' (default) or 'candleGlow' (family-opted only).
  final String atmosphere;

  /// Candle glow is NEVER automatic. Family must explicitly opt in.
  /// Deceased minors ALWAYS default to softLight (never candleGlow).
  final bool candleGlow;

  bool get isValid => atmosphere == 'softLight' || atmosphere == 'candleGlow';

  Map<String, dynamic> toJson() => {
    'atmosphere': atmosphere,
    'candleGlow': candleGlow,
  };

  factory CameoMemorialPreferences.fromJson(Map<String, dynamic> json) =>
      CameoMemorialPreferences(
        atmosphere: json['atmosphere'] as String? ?? 'softLight',
        candleGlow: json['candleGlow'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameoMemorialPreferences &&
          atmosphere == other.atmosphere &&
          candleGlow == other.candleGlow;

  @override
  int get hashCode => Object.hash(atmosphere, candleGlow);
}

/// The complete definition of a Kinrel Cameo character.
///
/// This is V2 §26 — CameoDefinition V2. It is the single source of
/// truth for a character's appearance. The 3D renderer consumes this
/// to build a scene; the portrait pipeline uses it to compute cache
/// keys; the fallback painter uses a subset for 2D rendering.
///
/// Versioning: [schemaVersion] allows migration from V1 to V2+.
/// The [CameoMigrator] (future) will handle version upgrades.
@immutable
class CameoDefinition {
  const CameoDefinition({
    required this.id,
    required this.personId,
    required this.familyId,
    required this.schemaVersion,
    required this.gender,
    required this.ageBandIndex,
    required this.skinToneIndex,
    this.hairStyleId,
    this.facialHairStyleId,
    this.glassesId,
    this.clothingId,
    this.headwearId,
    this.jewelleryIds = const [],
    this.accessoryIds = const [],
    this.expressionId,
    this.poseId,
    this.personality = const CameoPersonality(),
    this.memorialPreferences = const CameoMemorialPreferences(),
    this.isDeceased = false,
    this.assetPackVersion = '1.0.0',
    this.updatedAt,
  });

  /// Unique ID for this definition (typically = personId).
  final String id;

  /// The person this Cameo represents.
  final String personId;

  /// The family this person belongs to.
  final String familyId;

  /// Schema version for migration (V2 = 2).
  final int schemaVersion;

  /// Gender — drives body mesh selection.
  final CameoGender gender;

  /// Age band index (0=baby, 1=child, 2=teenager, 3=youngAdult,
  /// 4=adult, 5=middleAged, 6=senior, 7=elder).
  final int ageBandIndex;

  /// Skin tone index (0-9, from CameoColorPalette).
  final int skinToneIndex;

  /// Hair style ID (null = bald/default).
  final String? hairStyleId;

  /// Facial hair style ID (null = clean-shaven).
  final String? facialHairStyleId;

  /// Glasses ID (null = no glasses).
  final String? glassesId;

  /// Clothing item ID.
  final String? clothingId;

  /// Headwear ID (null = none).
  final String? headwearId;

  /// Jewellery IDs (0 or more).
  final List<String> jewelleryIds;

  /// Accessory IDs (0 or more).
  final List<String> accessoryIds;

  /// Default expression ID (from CameoExpressionCatalog).
  final String? expressionId;

  /// Default pose ID (from CameoPoseCatalog).
  final String? poseId;

  /// Personality vector — drives idle animation.
  final CameoPersonality personality;

  /// Memorial preferences (only relevant if isDeceased).
  final CameoMemorialPreferences memorialPreferences;

  /// Whether this person is deceased.
  final bool isDeceased;

  /// Asset pack version — bump when GLB assets change to invalidate cache.
  final String assetPackVersion;

  /// Last update timestamp (ISO 8601).
  final String? updatedAt;

  /// Computes a deterministic hash of this definition for cache keys.
  /// Same definition → same hash. Any change → different hash.
  String get definitionHash {
    final parts = <String>[
      'v$schemaVersion',
      gender.name,
      'age$ageBandIndex',
      'skin$skinToneIndex',
      hairStyleId ?? 'none',
      facialHairStyleId ?? 'none',
      glassesId ?? 'none',
      clothingId ?? 'none',
      headwearId ?? 'none',
      jewelleryIds.join(','),
      accessoryIds.join(','),
      expressionId ?? 'default',
      poseId ?? 'default',
      'p${personality.warmth}${personality.reserve}${personality.playfulness}${personality.dignity}',
      if (isDeceased)
        'mem${memorialPreferences.atmosphere}${memorialPreferences.candleGlow}',
      'apv$assetPackVersion',
    ];
    return parts.join('|');
  }

  /// Returns true if this definition is valid (all fields in range).
  bool get isValid {
    if (id.isEmpty || personId.isEmpty || familyId.isEmpty) return false;
    if (schemaVersion < 1) return false;
    if (ageBandIndex < 0 || ageBandIndex > 7) return false;
    if (skinToneIndex < 0 || skinToneIndex > 9) return false;
    if (!personality.isValid) return false;
    if (isDeceased && !memorialPreferences.isValid) return false;
    // Deceased minors cannot have candleGlow.
    if (isDeceased &&
        memorialPreferences.candleGlow &&
        (ageBandIndex == 0 || ageBandIndex == 1)) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'personId': personId,
    'familyId': familyId,
    'schemaVersion': schemaVersion,
    'gender': gender.name,
    'ageBandIndex': ageBandIndex,
    'skinToneIndex': skinToneIndex,
    'hairStyleId': hairStyleId,
    'facialHairStyleId': facialHairStyleId,
    'glassesId': glassesId,
    'clothingId': clothingId,
    'headwearId': headwearId,
    'jewelleryIds': jewelleryIds,
    'accessoryIds': accessoryIds,
    'expressionId': expressionId,
    'poseId': poseId,
    'personality': personality.toJson(),
    'memorialPreferences': memorialPreferences.toJson(),
    'isDeceased': isDeceased,
    'assetPackVersion': assetPackVersion,
    'updatedAt': updatedAt,
  };

  factory CameoDefinition.fromJson(Map<String, dynamic> json) {
    return CameoDefinition(
      id: json['id'] as String? ?? '',
      personId: json['personId'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      gender: CameoGender.values.firstWhere(
        (e) => e.name == json['gender'],
        orElse: () => CameoGender.unspecified,
      ),
      ageBandIndex: json['ageBandIndex'] as int? ?? 4,
      skinToneIndex: json['skinToneIndex'] as int? ?? 5,
      hairStyleId: json['hairStyleId'] as String?,
      facialHairStyleId: json['facialHairStyleId'] as String?,
      glassesId: json['glassesId'] as String?,
      clothingId: json['clothingId'] as String?,
      headwearId: json['headwearId'] as String?,
      jewelleryIds:
          (json['jewelleryIds'] as List<dynamic>?)?.cast<String>() ?? [],
      accessoryIds:
          (json['accessoryIds'] as List<dynamic>?)?.cast<String>() ?? [],
      expressionId: json['expressionId'] as String?,
      poseId: json['poseId'] as String?,
      personality: json['personality'] != null
          ? CameoPersonality.fromJson(
              json['personality'] as Map<String, dynamic>,
            )
          : const CameoPersonality(),
      memorialPreferences: json['memorialPreferences'] != null
          ? CameoMemorialPreferences.fromJson(
              json['memorialPreferences'] as Map<String, dynamic>,
            )
          : const CameoMemorialPreferences(),
      isDeceased: json['isDeceased'] as bool? ?? false,
      assetPackVersion: json['assetPackVersion'] as String? ?? '1.0.0',
      updatedAt: json['updatedAt'] as String?,
    );
  }

  CameoDefinition copyWith({
    String? id,
    String? personId,
    String? familyId,
    int? schemaVersion,
    CameoGender? gender,
    int? ageBandIndex,
    int? skinToneIndex,
    String? hairStyleId,
    String? facialHairStyleId,
    String? glassesId,
    String? clothingId,
    String? headwearId,
    List<String>? jewelleryIds,
    List<String>? accessoryIds,
    String? expressionId,
    String? poseId,
    CameoPersonality? personality,
    CameoMemorialPreferences? memorialPreferences,
    bool? isDeceased,
    String? assetPackVersion,
    String? updatedAt,
  }) {
    return CameoDefinition(
      id: id ?? this.id,
      personId: personId ?? this.personId,
      familyId: familyId ?? this.familyId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      gender: gender ?? this.gender,
      ageBandIndex: ageBandIndex ?? this.ageBandIndex,
      skinToneIndex: skinToneIndex ?? this.skinToneIndex,
      hairStyleId: hairStyleId ?? this.hairStyleId,
      facialHairStyleId: facialHairStyleId ?? this.facialHairStyleId,
      glassesId: glassesId ?? this.glassesId,
      clothingId: clothingId ?? this.clothingId,
      headwearId: headwearId ?? this.headwearId,
      jewelleryIds: jewelleryIds ?? this.jewelleryIds,
      accessoryIds: accessoryIds ?? this.accessoryIds,
      expressionId: expressionId ?? this.expressionId,
      poseId: poseId ?? this.poseId,
      personality: personality ?? this.personality,
      memorialPreferences: memorialPreferences ?? this.memorialPreferences,
      isDeceased: isDeceased ?? this.isDeceased,
      assetPackVersion: assetPackVersion ?? this.assetPackVersion,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameoDefinition &&
          id == other.id &&
          definitionHash == other.definitionHash;

  @override
  int get hashCode => definitionHash.hashCode;
}
