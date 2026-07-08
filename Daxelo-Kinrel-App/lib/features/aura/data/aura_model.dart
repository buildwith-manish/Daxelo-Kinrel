// lib/features/aura/data/aura_model.dart
//
// AURA — Ancestral Unified Relationship Archetype
// Pure data models mirroring the JSON shape returned by the backend
// AURA endpoints (see server/src/aura/aura-query.service.ts).
//
// Endpoints (all require JWT auth):
//   GET /aura/:familyId          → AuraModel
//   GET /aura/:familyId/roles    → { familyId, roles: List<RoleGlyph> }
//   GET /aura/:familyId/history  → { familyId, history: List<AuraHistorySnapshot> }
//
// These models are NOT generated — they are hand-written so the Flutter
// client owns the contract independently of any code generator.

import 'dart:convert';

/// Inner pattern drawn at the centre of the AURA symbol.
/// Mirrors `InnerPattern` from aura-parameter-generator.service.ts.
enum AuraInnerPattern {
  lotus,
  grid,
  diamond,
  star,
  web,
  spiral;

  /// Parse from the backend string. Falls back to [lotus] for unknown
  /// values so a future backend addition never crashes the client.
  static AuraInnerPattern fromString(String? value) {
    switch (value) {
      case 'lotus':
        return AuraInnerPattern.lotus;
      case 'grid':
        return AuraInnerPattern.grid;
      case 'diamond':
        return AuraInnerPattern.diamond;
      case 'star':
        return AuraInnerPattern.star;
      case 'web':
        return AuraInnerPattern.web;
      case 'spiral':
        return AuraInnerPattern.spiral;
      default:
        return AuraInnerPattern.lotus;
    }
  }

  String toJson() => name;
}

/// One of the 6 family archetypes. Mirrors `ArchetypeKey` from
/// archetype-classifier.service.ts.
enum ArchetypeType {
  banyan,
  riverDelta,
  confluence,
  spine,
  lotus,
  forest;

  static ArchetypeType fromString(String? value) {
    switch (value) {
      case 'banyan':
        return ArchetypeType.banyan;
      case 'river_delta':
        return ArchetypeType.riverDelta;
      case 'confluence':
        return ArchetypeType.confluence;
      case 'spine':
        return ArchetypeType.spine;
      case 'lotus':
        return ArchetypeType.lotus;
      case 'forest':
        return ArchetypeType.forest;
      default:
        return ArchetypeType.lotus;
    }
  }

  /// Backend wire format uses snake_case (e.g. `river_delta`).
  String get wireKey {
    switch (this) {
      case ArchetypeType.banyan:
        return 'banyan';
      case ArchetypeType.riverDelta:
        return 'river_delta';
      case ArchetypeType.confluence:
        return 'confluence';
      case ArchetypeType.spine:
        return 'spine';
      case ArchetypeType.lotus:
        return 'lotus';
      case ArchetypeType.forest:
        return 'forest';
    }
  }
}

/// Visual symbol parameters for a family's AURA. Mirrors the `symbol`
/// block of the GET /aura/:familyId response.
class AuraSymbolParameters {
  const AuraSymbolParameters({
    required this.ringCount,
    required this.spokeCount,
    required this.innerPatternType,
    required this.outerRingRadiusPct,
    required this.patternComplexity,
    required this.primaryColorHex,
    required this.secondaryColorHex,
    required this.accentColorHex,
    required this.pulseSpeedMs,
  });

  final int ringCount; // 1–8
  final int spokeCount; // 3–12
  final AuraInnerPattern innerPatternType;
  final double outerRingRadiusPct; // 0.50–0.95
  final int patternComplexity; // 1–10
  final String primaryColorHex; // #RRGGBB
  final String secondaryColorHex;
  final String accentColorHex;
  final int pulseSpeedMs; // 2000–6000

  factory AuraSymbolParameters.fromJson(Map<String, dynamic> json) {
    return AuraSymbolParameters(
      ringCount: _readInt(json, 'ringCount', 2),
      spokeCount: _readInt(json, 'spokeCount', 4),
      innerPatternType:
          AuraInnerPattern.fromString(json['innerPatternType'] as String?),
      outerRingRadiusPct:
          _readDouble(json, 'outerRingRadiusPct', 0.85),
      patternComplexity: _readInt(json, 'patternComplexity', 3),
      primaryColorHex:
          (json['primaryColorHex'] as String?) ?? '#C8853A',
      secondaryColorHex:
          (json['secondaryColorHex'] as String?) ?? '#6B3FA0',
      accentColorHex:
          (json['accentColorHex'] as String?) ?? '#2D8A4E',
      pulseSpeedMs: _readInt(json, 'pulseSpeedMs', 3000),
    );
  }

  Map<String, dynamic> toJson() => {
        'ringCount': ringCount,
        'spokeCount': spokeCount,
        'innerPatternType': innerPatternType.toJson(),
        'outerRingRadiusPct': outerRingRadiusPct,
        'patternComplexity': patternComplexity,
        'primaryColorHex': primaryColorHex,
        'secondaryColorHex': secondaryColorHex,
        'accentColorHex': accentColorHex,
        'pulseSpeedMs': pulseSpeedMs,
      };

  AuraSymbolParameters copyWith({
    int? ringCount,
    int? spokeCount,
    AuraInnerPattern? innerPatternType,
    double? outerRingRadiusPct,
    int? patternComplexity,
    String? primaryColorHex,
    String? secondaryColorHex,
    String? accentColorHex,
    int? pulseSpeedMs,
  }) =>
      AuraSymbolParameters(
        ringCount: ringCount ?? this.ringCount,
        spokeCount: spokeCount ?? this.spokeCount,
        innerPatternType: innerPatternType ?? this.innerPatternType,
        outerRingRadiusPct:
            outerRingRadiusPct ?? this.outerRingRadiusPct,
        patternComplexity: patternComplexity ?? this.patternComplexity,
        primaryColorHex: primaryColorHex ?? this.primaryColorHex,
        secondaryColorHex: secondaryColorHex ?? this.secondaryColorHex,
        accentColorHex: accentColorHex ?? this.accentColorHex,
        pulseSpeedMs: pulseSpeedMs ?? this.pulseSpeedMs,
      );
}

/// Raw graph metrics snapshot, surfaced for the timeline + debugging UI.
class AuraMetrics {
  const AuraMetrics({
    required this.memberCount,
    required this.generationDepth,
    required this.edgeCount,
    required this.clusteringCoefficient,
    required this.graphDiameter,
    required this.avgDegree,
    required this.distinctLineages,
    required this.languageDistribution,
    required this.maxBetweennessNode,
    required this.rootNode,
  });

  final int memberCount;
  final int generationDepth;
  final int edgeCount;
  final double clusteringCoefficient;
  final int graphDiameter;
  final double avgDegree;
  final int distinctLineages;
  final Map<String, double> languageDistribution;
  final String? maxBetweennessNode;
  final String? rootNode;

  factory AuraMetrics.fromJson(Map<String, dynamic> json) {
    final rawDist = json['languageDistribution'];
    final Map<String, double> dist = {};
    if (rawDist is Map) {
      rawDist.forEach((key, value) {
        if (value is num) {
          dist[key.toString()] = value.toDouble();
        } else {
          dist[key.toString()] = double.tryParse(value.toString()) ?? 0.0;
        }
      });
    }
    return AuraMetrics(
      memberCount: _readInt(json, 'memberCount', 0),
      generationDepth: _readInt(json, 'generationDepth', 1),
      edgeCount: _readInt(json, 'edgeCount', 0),
      clusteringCoefficient:
          _readDouble(json, 'clusteringCoefficient', 0.0),
      graphDiameter: _readInt(json, 'graphDiameter', 0),
      avgDegree: _readDouble(json, 'avgDegree', 0.0),
      distinctLineages: _readInt(json, 'distinctLineages', 1),
      languageDistribution: dist,
      maxBetweennessNode: json['maxBetweennessNode'] as String?,
      rootNode: json['rootNode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'memberCount': memberCount,
        'generationDepth': generationDepth,
        'edgeCount': edgeCount,
        'clusteringCoefficient': clusteringCoefficient,
        'graphDiameter': graphDiameter,
        'avgDegree': avgDegree,
        'distinctLineages': distinctLineages,
        'languageDistribution': languageDistribution,
        'maxBetweennessNode': maxBetweennessNode,
        'rootNode': rootNode,
      };
}

/// Archetype classification attached to a family's AURA.
class AuraArchetype {
  const AuraArchetype({
    required this.key,
    required this.confidence,
  });

  final ArchetypeType key;
  final double confidence; // 0.0–1.0

  factory AuraArchetype.fromJson(Map<String, dynamic> json) {
    return AuraArchetype(
      key: ArchetypeType.fromString(json['key'] as String?),
      confidence: _readDouble(json, 'confidence', 0.5),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key.wireKey,
        'confidence': confidence,
      };
}

/// Full AURA payload returned by `GET /aura/:familyId`.
class AuraModel {
  const AuraModel({
    required this.familyId,
    required this.symbol,
    required this.archetype,
    required this.metrics,
    required this.computedAt,
    required this.updatedAt,
  });

  final String familyId;
  final AuraSymbolParameters symbol;
  final AuraArchetype archetype;
  final AuraMetrics metrics;
  final DateTime computedAt;
  final DateTime updatedAt;

  factory AuraModel.fromJson(Map<String, dynamic> json) {
    return AuraModel(
      familyId: (json['familyId'] as String?) ?? '',
      symbol: AuraSymbolParameters.fromJson(
        (json['symbol'] as Map<String, dynamic>?) ?? const {},
      ),
      archetype: AuraArchetype.fromJson(
        (json['archetype'] as Map<String, dynamic>?) ?? const {},
      ),
      metrics: AuraMetrics.fromJson(
        (json['metrics'] as Map<String, dynamic>?) ?? const {},
      ),
      computedAt: _readDate(json['computedAt']) ?? DateTime.now(),
      updatedAt: _readDate(json['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'familyId': familyId,
        'symbol': symbol.toJson(),
        'archetype': archetype.toJson(),
        'metrics': metrics.toJson(),
        'computedAt': computedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Encode the whole model as a JSON string for storage in the Drift
  /// cache table (`CachedAura.data` text column).
  String encode() => jsonEncode(toJson());

  static AuraModel decode(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('CachedAura.data is not a JSON object');
    }
    return AuraModel.fromJson(decoded);
  }
}

/// One member's role glyph within the family AURA. Mirrors the rows
/// returned by `GET /aura/:familyId/roles`.
class RoleGlyph {
  const RoleGlyph({
    required this.memberId,
    required this.roleKey,
    required this.glyphShape,
    required this.glyphColorHex,
    required this.generationIndex,
    required this.betweennessScore,
    required this.degreeCount,
  });

  final String memberId;

  /// One of: root | anchor | bridge | weaver | leaf | twin_node
  final String roleKey;

  /// Visual hint from the backend (e.g. `deep_anchor`, `bridge_cross`).
  final String glyphShape;
  final String glyphColorHex; // #RRGGBB
  final int generationIndex;
  final double betweennessScore;
  final int degreeCount;

  factory RoleGlyph.fromJson(Map<String, dynamic> json) {
    return RoleGlyph(
      memberId: (json['memberId'] as String?) ?? '',
      roleKey: (json['roleKey'] as String?) ?? 'leaf',
      glyphShape: (json['glyphShape'] as String?) ?? 'petal',
      glyphColorHex: (json['glyphColorHex'] as String?) ?? '#C8853A',
      generationIndex: _readInt(json, 'generationIndex', 0),
      betweennessScore:
          _readDouble(json, 'betweennessScore', 0.0),
      degreeCount: _readInt(json, 'degreeCount', 0),
    );
  }

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'roleKey': roleKey,
        'glyphShape': glyphShape,
        'glyphColorHex': glyphColorHex,
        'generationIndex': generationIndex,
        'betweennessScore': betweennessScore,
        'degreeCount': degreeCount,
      };
}

/// One historical snapshot from `GET /aura/:familyId/history`.
class AuraHistorySnapshot {
  const AuraHistorySnapshot({
    required this.id,
    required this.memberCount,
    required this.generationDepth,
    required this.archetypeKey,
    required this.ringCount,
    required this.spokeCount,
    required this.innerPatternType,
    required this.primaryColorHex,
    required this.secondaryColorHex,
    required this.accentColorHex,
    required this.archetypeChanged,
    required this.previousArchetype,
    required this.capturedAt,
    required this.triggerMemberId,
    required this.triggerEventType,
  });

  final String id;
  final int memberCount;
  final int generationDepth;
  final ArchetypeType archetypeKey;
  final int ringCount;
  final int spokeCount;
  final AuraInnerPattern innerPatternType;
  final String primaryColorHex;
  final String secondaryColorHex;
  final String accentColorHex;
  final bool archetypeChanged;
  final String? previousArchetype;
  final DateTime capturedAt;
  final String? triggerMemberId;
  final String triggerEventType;

  factory AuraHistorySnapshot.fromJson(Map<String, dynamic> json) {
    return AuraHistorySnapshot(
      id: (json['id'] as String?) ?? '',
      memberCount: _readInt(json, 'memberCount', 0),
      generationDepth: _readInt(json, 'generationDepth', 1),
      archetypeKey: ArchetypeType.fromString(
          json['archetypeKey'] as String?),
      ringCount: _readInt(json, 'ringCount', 2),
      spokeCount: _readInt(json, 'spokeCount', 4),
      innerPatternType: AuraInnerPattern.fromString(
          json['innerPatternType'] as String?),
      primaryColorHex:
          (json['primaryColorHex'] as String?) ?? '#C8853A',
      secondaryColorHex:
          (json['secondaryColorHex'] as String?) ?? '#6B3FA0',
      accentColorHex:
          (json['accentColorHex'] as String?) ?? '#2D8A4E',
      archetypeChanged: (json['archetypeChanged'] as bool?) ?? false,
      previousArchetype: json['previousArchetype'] as String?,
      capturedAt: _readDate(json['capturedAt']) ?? DateTime.now(),
      triggerMemberId: json['triggerMemberId'] as String?,
      triggerEventType:
          (json['triggerEventType'] as String?) ?? 'member_added',
    );
  }
}

// ─── helpers ───────────────────────────────────────────────────────────

int _readInt(Map<String, dynamic> json, String key, int fallback) {
  final v = json[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _readDouble(
    Map<String, dynamic> json, String key, double fallback) {
  final v = json[key];
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

DateTime? _readDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
