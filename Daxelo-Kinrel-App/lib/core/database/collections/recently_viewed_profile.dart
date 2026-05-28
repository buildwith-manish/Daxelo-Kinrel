import 'package:isar/isar.dart';

part 'recently_viewed_profile.g.dart';

/// Isar collection for recently viewed person profiles.
/// Enables quick access to recently viewed family members.
@Collection()
class RecentlyViewedProfile {
  Id isarId = Isar.autoIncrement;

  /// Person ID
  @Index()
  late String personId;

  /// Family ID the person belongs to
  @Index()
  late String familyId;

  /// Person name (for display without loading full data)
  late String personName;

  /// Person photo URL (nullable)
  String? photoUrl;

  /// When this profile was last viewed
  @Index()
  late String viewedAt;

  /// Create a new recently viewed entry
  static RecentlyViewedProfile create({
    required String personId,
    required String familyId,
    required String personName,
    String? photoUrl,
  }) {
    return RecentlyViewedProfile()
      ..personId = personId
      ..familyId = familyId
      ..personName = personName
      ..photoUrl = photoUrl
      ..viewedAt = DateTime.now().toIso8601String();
  }
}
