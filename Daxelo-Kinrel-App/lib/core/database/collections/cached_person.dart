/// Data class for caching Person data locally.
/// Mirrors the Person model from family_provider.dart.
class CachedPerson {
  CachedPerson({
    required this.id,
    required this.familyId,
    required this.name,
    this.gender,
    this.dateOfBirth,
    this.city,
    this.gotra,
    this.isDeceased = false,
    this.deletedAt,
    this.createdAt,
    this.birthYear,
    this.occupation,
    this.privacyLevel,
    this.notes,
    this.sideOfFamily,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.username,
    required this.cachedAt,
  });

  /// Supabase document ID (unique business key)
  late String id;

  /// Family ID for querying all members of a family
  late String familyId;

  late String name;

  String? gender;
  String? dateOfBirth;
  String? city;
  String? gotra;

  late bool isDeceased;
  String? deletedAt;
  String? createdAt;

  int? birthYear;
  String? occupation;
  String? privacyLevel;
  String? notes;
  String? sideOfFamily;

  late int generationIndex;
  late bool isAnchor;

  String? photoUrl;
  String? username;

  /// When this cache entry was last updated from the server
  late String cachedAt;

  /// Convert to JSON matching the domain Person model
  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'name': name,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'city': city,
        'gotra': gotra,
        'isDeceased': isDeceased,
        'deletedAt': deletedAt,
        'createdAt': createdAt,
        'birthYear': birthYear,
        'occupation': occupation,
        'privacyLevel': privacyLevel,
        'notes': notes,
        'sideOfFamily': sideOfFamily,
        'generationIndex': generationIndex,
        'isAnchor': isAnchor,
        'photoUrl': photoUrl,
        'username': username,
      };

  /// Create from the domain Person model's JSON representation
  static CachedPerson fromJson(Map<String, dynamic> json) {
    return CachedPerson(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unknown',
      gender: json['gender'] as String?,
      dateOfBirth: json['dateOfBirth']?.toString(),
      city: json['city'] as String?,
      gotra: json['gotra'] as String?,
      isDeceased: json['isDeceased'] as bool? ?? false,
      deletedAt: json['deletedAt']?.toString(),
      createdAt: json['createdAt']?.toString(),
      birthYear: json['birthYear'] as int?,
      occupation: json['occupation'] as String?,
      privacyLevel: json['privacyLevel'] as String?,
      notes: json['notes'] as String?,
      sideOfFamily: json['sideOfFamily'] as String?,
      generationIndex: json['generationIndex'] as int? ?? 0,
      isAnchor: json['isAnchor'] as bool? ?? false,
      photoUrl: json['photoUrl'] as String?,
      username: json['username'] as String?,
      cachedAt: DateTime.now().toIso8601String(),
    );
  }
}
