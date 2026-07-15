// lib/features/family_map/data/place_models.dart
//
// P10.1 — Family Place data models.
//
// A FamilyPlace is a meaningful location tied to a family's story:
// homes, birthplaces, wedding venues, memorials, family businesses,
// schools, and other important places. Unlike a Person's lat/lng
// (which is "where someone lives now"), a Place is a fixed landmark
// with a semantic type and optional time-window for timeline filtering.
//
// Constitution test (Rule 5):
//   (a) Understand — places let you see where your family lived.
//   (d) Preserve  — places anchor family history across generations.

import 'package:flutter/foundation.dart';

/// Semantic type of a family place. Drives the building's emotional
/// lighting in P10.2.
///
/// Order matters for the [values] list — DO NOT reorder. New types
/// must be appended at the end so existing serialized data stays
/// forward-compatible (P10.9 persistence and the Supabase `placeType`
/// text column rely on the enum name, not the index).
enum PlaceType {
  /// Where the person currently lives. Warm orange + glow halo.
  currentHome,

  /// Where they grew up. Soft amber.
  childhoodHome,

  /// Multi-generational family seat. Gold heritage lighting.
  ancestralHome,

  /// Where someone was born. Gentle highlight.
  birthplace,

  /// Wedding venue. Warm celebration glow (pulse-animated).
  wedding,

  /// Memorial / cemetery / place of remembrance. Soft candle light.
  memorial,

  /// Family-owned shop, farm, or business. Neutral warm.
  familyBusiness,

  /// School / college / university. Cool neutral.
  school,

  /// Vacation / retreat home. Cool serenity glow (per master prompt).
  vacationHome,

  /// Family temple / place of worship. Sacred warm glow (per master prompt).
  familyTemple,

  /// Grandparents' home. Amber warmth, gentle pulse (per master prompt).
  grandparentsHome,

  /// Any other place of family significance. Default warm.
  importantPlace;

  /// Human-readable label for screen readers and UI.
  ///
  /// These strings are also used as the source for .arb localizations
  /// (per P6.4 infrastructure). When adding a new type, also add the
  /// matching `placeType.*` key to `app_en.arb`.
  String get semanticLabel {
    switch (this) {
      case PlaceType.currentHome:
        return 'Current Home';
      case PlaceType.childhoodHome:
        return 'Childhood Home';
      case PlaceType.ancestralHome:
        return 'Ancestral Home';
      case PlaceType.birthplace:
        return 'Birthplace';
      case PlaceType.wedding:
        return 'Wedding Location';
      case PlaceType.memorial:
        return 'Memorial Location';
      case PlaceType.familyBusiness:
        return 'Family Business';
      case PlaceType.school:
        return 'School';
      case PlaceType.vacationHome:
        return 'Vacation Home';
      case PlaceType.familyTemple:
        return 'Family Temple';
      case PlaceType.grandparentsHome:
        return 'Grandparents\' Home';
      case PlaceType.importantPlace:
        return 'Important Family Place';
    }
  }

  /// Storage string used by Supabase `Place.placeType` text column.
  /// Persisted in snake_case to match the existing schema conventions.
  String get wireName {
    switch (this) {
      case PlaceType.currentHome:
        return 'current_home';
      case PlaceType.childhoodHome:
        return 'childhood_home';
      case PlaceType.ancestralHome:
        return 'ancestral_home';
      case PlaceType.birthplace:
        return 'birthplace';
      case PlaceType.wedding:
        return 'wedding';
      case PlaceType.memorial:
        return 'memorial';
      case PlaceType.familyBusiness:
        return 'family_business';
      case PlaceType.school:
        return 'school';
      case PlaceType.vacationHome:
        return 'vacation_home';
      case PlaceType.familyTemple:
        return 'family_temple';
      case PlaceType.grandparentsHome:
        return 'grandparents_home';
      case PlaceType.importantPlace:
        return 'important_place';
    }
  }

  /// Parse from the wire format. Returns [importantPlace] as a safe
  /// fallback for unknown strings (forward-compatibility).
  static PlaceType fromWireName(String? wire) {
    if (wire == null) return PlaceType.importantPlace;
    for (final v in PlaceType.values) {
      if (v.wireName == wire) return v;
    }
    return PlaceType.importantPlace;
  }
}

/// A single family place row, mirroring the Supabase `Place` table
/// (migration `20260715_create_place_table.sql`).
///
/// Instances are immutable. The map screen reads these to render family
/// buildings (P10.2) and to filter by year on the timeline (P10.7).
@immutable
class FamilyPlace {
  const FamilyPlace({
    required this.id,
    required this.familyId,
    required this.name,
    required this.placeType,
    required this.lat,
    required this.lng,
    this.address,
    this.personId,
    this.description,
    this.validFrom,
    this.validTo,
    this.memoryCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// Cuid from the database.
  final String id;

  /// Family this place belongs to (RLS-scoped).
  final String familyId;

  /// Display name (e.g. "Grandma's House in Pune").
  final String name;

  /// Semantic type — drives building lighting in P10.2.
  final PlaceType placeType;

  /// Latitude. Required — places without coordinates are rejected
  /// at insert per the P10.1 edge-case rules.
  final double lat;

  /// Longitude.
  final double lng;

  /// Optional human-readable address. Family-private — never shown on
  /// the public map, only in the bottom sheet (P10.2).
  final String? address;

  /// Optional link to a Person. Null = standalone place (e.g. a wedding
  /// venue that doesn't belong to one person).
  final String? personId;

  /// Optional long-form description.
  final String? description;

  /// When this place became relevant to the family. Used by P10.7
  /// timeline filtering. Null = always valid.
  final DateTime? validFrom;

  /// When this place stopped being relevant (e.g. moved out). Used by
  /// P10.7 timeline filtering. Null = still valid.
  final DateTime? validTo;

  /// Number of memories associated with this place (denormalized count).
  final int memoryCount;

  /// Row creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// True if [validFrom] / [validTo] bracket [viewingDate].
  /// Null bounds mean "unbounded" on that side.
  bool isValidAt(DateTime viewingDate) {
    if (validFrom != null && viewingDate.isBefore(validFrom!)) return false;
    if (validTo != null && viewingDate.isAfter(validTo!)) return false;
    return true;
  }

  FamilyPlace copyWith({
    String? id,
    String? familyId,
    String? name,
    PlaceType? placeType,
    double? lat,
    double? lng,
    String? address,
    String? personId,
    String? description,
    DateTime? validFrom,
    DateTime? validTo,
    int? memoryCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FamilyPlace(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      name: name ?? this.name,
      placeType: placeType ?? this.placeType,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      address: address ?? this.address,
      personId: personId ?? this.personId,
      description: description ?? this.description,
      validFrom: validFrom ?? this.validFrom,
      validTo: validTo ?? this.validTo,
      memoryCount: memoryCount ?? this.memoryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory FamilyPlace.fromJson(Map<String, dynamic> json) {
    return FamilyPlace(
      id: json['id'] as String,
      familyId:
          json['familyId'] as String? ?? json['family_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      placeType: PlaceType.fromWireName(
        json['placeType'] as String? ?? json['place_type'] as String?,
      ),
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      address: json['address'] as String?,
      personId: json['personId'] as String? ?? json['person_id'] as String?,
      description: json['description'] as String?,
      validFrom: json['validFrom'] != null
          ? DateTime.tryParse(json['validFrom'].toString())
          : (json['valid_from'] != null
                ? DateTime.tryParse(json['valid_from'].toString())
                : null),
      validTo: json['validTo'] != null
          ? DateTime.tryParse(json['validTo'].toString())
          : (json['valid_to'] != null
                ? DateTime.tryParse(json['valid_to'].toString())
                : null),
      memoryCount:
          (json['memoryCount'] as num?)?.toInt() ??
          (json['memory_count'] as num?)?.toInt() ??
          0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyId': familyId,
    'name': name,
    'placeType': placeType.wireName,
    'lat': lat,
    'lng': lng,
    'address': address,
    'personId': personId,
    'description': description,
    'validFrom': validFrom?.toIso8601String(),
    'validTo': validTo?.toIso8601String(),
    'memoryCount': memoryCount,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyPlace &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'FamilyPlace(id: $id, name: "$name", type: ${placeType.wireName}, '
      'lat: $lat, lng: $lng)';
}
