/// Data class for caching FamilyRelationship data locally.
/// Mirrors the FamilyRelationship model from family_provider.dart.
class CachedRelationship {
  CachedRelationship({
    required this.id,
    required this.familyId,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.direction = 'from',
    this.isActive = true,
    this.label,
    this.createdAt,
    required this.cachedAt,
  });

  /// Supabase document ID (unique business key)
  late String id;

  /// Family ID for querying relationships by family
  late String familyId;

  late String fromPersonId;
  late String toPersonId;
  late String relationshipKey;

  late String direction;
  late bool isActive;
  String? label;
  String? createdAt;

  /// When this cache entry was last updated from the server
  late String cachedAt;

  /// Convert to JSON matching the domain FamilyRelationship model
  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'fromPersonId': fromPersonId,
        'toPersonId': toPersonId,
        'relationshipKey': relationshipKey,
        'direction': direction,
        'isActive': isActive,
        'label': label,
        'createdAt': createdAt,
      };

  /// Create from the domain FamilyRelationship model's JSON representation
  static CachedRelationship fromJson(Map<String, dynamic> json) {
    return CachedRelationship(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId']?.toString() ?? '',
      fromPersonId: json['fromPersonId']?.toString() ?? '',
      toPersonId: json['toPersonId']?.toString() ?? '',
      relationshipKey: json['relationshipKey'] as String? ?? '',
      direction: json['direction'] as String? ?? 'from',
      isActive: json['isActive'] as bool? ?? true,
      label: json['label'] as String?,
      createdAt: json['createdAt']?.toString(),
      cachedAt: DateTime.now().toIso8601String(),
    );
  }
}
