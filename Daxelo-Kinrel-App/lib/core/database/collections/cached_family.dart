/// Data class for caching Family data locally.
/// Mirrors the Family model from family_provider.dart.
class CachedFamily {
  CachedFamily({
    required this.id,
    required this.name,
    this.description,
    this.primaryLanguage,
    this.gotra,
    this.originVillage,
    this.createdBy,
    this.createdAt,
    this.familyCode,
    this.avatarUrl,
    this.region,
    this.privacyMode,
    this.isOnboarded = false,
    this.anchorPersonId,
    this.memberCount = 0,
    this.generationCount = 1,
    this.lastActivityAt,
    this.username,
    required this.cachedAt,
  });

  /// Supabase document ID (unique business key)
  late String id;

  late String name;

  String? description;
  String? primaryLanguage;
  String? gotra;
  String? originVillage;
  String? createdBy;

  /// Stored as ISO8601 string
  String? createdAt;

  String? familyCode;
  String? avatarUrl;
  String? region;
  String? privacyMode;

  late bool isOnboarded;
  String? anchorPersonId;

  late int memberCount;
  late int generationCount;

  String? lastActivityAt;
  String? username;

  /// When this cache entry was last updated from the server
  late String cachedAt;

  /// Convert from CachedFamily to the domain Family model's JSON representation
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'primaryLanguage': primaryLanguage,
        'gotra': gotra,
        'originVillage': originVillage,
        'createdBy': createdBy,
        'createdAt': createdAt,
        'familyCode': familyCode,
        'avatarUrl': avatarUrl,
        'region': region,
        'privacyMode': privacyMode,
        'isOnboarded': isOnboarded,
        'anchorPersonId': anchorPersonId,
        'memberCount': memberCount,
        'generationCount': generationCount,
        'lastActivityAt': lastActivityAt,
        'username': username,
      };

  /// Create from the domain Family model's JSON representation
  static CachedFamily fromJson(Map<String, dynamic> json) {
    return CachedFamily(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unnamed Family',
      description: json['description'] as String?,
      primaryLanguage: json['primaryLanguage'] as String?,
      gotra: json['gotra'] as String?,
      originVillage: json['originVillage'] as String?,
      createdBy: json['createdBy'] as String?,
      createdAt: json['createdAt']?.toString(),
      familyCode: json['familyCode'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      region: json['region'] as String?,
      privacyMode: json['privacyMode'] as String?,
      isOnboarded: json['isOnboarded'] as bool? ?? false,
      anchorPersonId: json['anchorPersonId'] as String?,
      memberCount: json['memberCount'] as int? ?? 0,
      generationCount: json['generationCount'] as int? ?? 1,
      lastActivityAt: json['lastActivityAt']?.toString(),
      username: json['username'] as String?,
      cachedAt: DateTime.now().toIso8601String(),
    );
  }
}
