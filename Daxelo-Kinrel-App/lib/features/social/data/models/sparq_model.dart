// SparqModel — ephemeral 24-hour content (IMAGE, VIDEO, TEXT, VOICE)
class SparqModel {
  final String id;
  final String userId;
  final String type; // IMAGE, VIDEO, TEXT, VOICE
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? text;
  final String? backgroundColor;
  final int? duration; // seconds, for VIDEO and VOICE
  final String audience; // PUBLIC, FAMILY_ONLY
  final DateTime expiresAt;
  final DateTime createdAt;
  final int viewCount;

  const SparqModel({
    required this.id,
    required this.userId,
    required this.type,
    this.mediaUrl,
    this.thumbnailUrl,
    this.text,
    this.backgroundColor,
    this.duration,
    this.audience = 'PUBLIC',
    required this.expiresAt,
    required this.createdAt,
    this.viewCount = 0,
  });

  factory SparqModel.fromJson(Map<String, dynamic> json) {
    return SparqModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      type: json['type'] as String? ?? 'TEXT',
      mediaUrl: json['mediaUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      text: json['text'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      duration: json['duration'] as int?,
      audience: json['audience'] as String? ?? 'PUBLIC',
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : DateTime.now().add(const Duration(hours: 24)),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      viewCount: json['viewCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'type': type,
    'mediaUrl': mediaUrl,
    'thumbnailUrl': thumbnailUrl,
    'text': text,
    'backgroundColor': backgroundColor,
    'duration': duration,
    'audience': audience,
    'expiresAt': expiresAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'viewCount': viewCount,
  };

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Duration in seconds for auto-advance: 5s for IMAGE/TEXT, full duration for VIDEO/VOICE
  int get autoAdvanceDuration {
    switch (type) {
      case 'IMAGE':
      case 'TEXT':
        return 5;
      case 'VIDEO':
      case 'VOICE':
        return duration ?? 60;
      default:
        return 5;
    }
  }
}

/// Groups Sparqs by user for the feed display
class UserSparqGroup {
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final List<SparqModel> sparqs;
  final bool allSeen; // true = grey ring, false = orange ring

  const UserSparqGroup({
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.sparqs,
    this.allSeen = false,
  });

  factory UserSparqGroup.fromJson(Map<String, dynamic> json) {
    return UserSparqGroup(
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      userAvatarUrl: json['userAvatarUrl'] as String?,
      sparqs: (json['sparqs'] as List?)
              ?.map((s) => SparqModel.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      allSeen: json['allSeen'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'userName': userName,
    'userAvatarUrl': userAvatarUrl,
    'sparqs': sparqs.map((s) => s.toJson()).toList(),
    'allSeen': allSeen,
  };

  /// Whether this group has any active (non-expired) sparqs
  bool get hasActiveSparqs => sparqs.isNotEmpty;
}
