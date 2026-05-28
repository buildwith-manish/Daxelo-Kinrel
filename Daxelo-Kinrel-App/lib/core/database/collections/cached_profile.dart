import 'package:isar/isar.dart';

part 'cached_profile.g.dart';

/// Isar collection for caching user profile data locally.
/// Mirrors the ProfileModel from profile_provider.dart.
@Collection()
class CachedProfile {
  Id isarId = Isar.autoIncrement;

  /// User ID (unique business key — one profile per user)
  @Index(unique: true, replace: true)
  late String id;

  late String email;
  String? name;
  String? phone;
  String? avatarUrl;
  String? bio;

  /// Stored as ISO8601 string
  String? dateOfBirth;
  String? gender;
  String? username;

  late String preferredLanguage;
  late String profileVisibility;
  late String invitePermission;
  late bool twoFactorEnabled;
  late String authProvider;

  /// Stored as ISO8601 string
  late String createdAt;
  late String updatedAt;

  /// When this cache entry was last updated from the server
  late String cachedAt;

  /// Convert to JSON matching the domain ProfileModel
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'bio': bio,
        'dateOfBirth': dateOfBirth,
        'gender': gender,
        'username': username,
        'preferredLanguage': preferredLanguage,
        'profileVisibility': profileVisibility,
        'invitePermission': invitePermission,
        'twoFactorEnabled': twoFactorEnabled,
        'authProvider': authProvider,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Create from the domain ProfileModel's JSON representation
  static CachedProfile fromJson(Map<String, dynamic> json) {
    return CachedProfile()
      ..id = json['id'] as String? ?? ''
      ..email = json['email'] as String? ?? ''
      ..name = json['name'] as String?
      ..phone = json['phone'] as String?
      ..avatarUrl = json['avatarUrl'] as String?
      ..bio = json['bio'] as String?
      ..dateOfBirth = json['dateOfBirth']?.toString()
      ..gender = json['gender'] as String?
      ..username = json['username'] as String?
      ..preferredLanguage = json['preferredLanguage'] as String? ?? 'en'
      ..profileVisibility = json['profileVisibility'] as String? ?? 'public'
      ..invitePermission = json['invitePermission'] as String? ?? 'anyone'
      ..twoFactorEnabled = json['twoFactorEnabled'] as bool? ?? false
      ..authProvider = json['authProvider'] as String? ?? 'email'
      ..createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString()).toIso8601String()
          : DateTime.now().toIso8601String()
      ..updatedAt = json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'].toString()).toIso8601String()
          : DateTime.now().toIso8601String()
      ..cachedAt = DateTime.now().toIso8601String();
  }
}
