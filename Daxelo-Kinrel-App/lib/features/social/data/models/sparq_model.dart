import 'package:flutter/material.dart';

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

  // ── New Sparq Enhancement Fields ──────────────────────────────────
  final String mood; // happy/hype/love/sad/celebrate/angry
  final String intensity; // calm/warm/fire
  final bool allowChain;
  final bool allowReplies;
  final bool isTimeCapsule;
  final DateTime? revealAt;
  final bool isRevealed;
  final String? parentSparqId;
  final int? chainOrder;
  final int echoCount;

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
    this.mood = 'happy',
    this.intensity = 'warm',
    this.allowChain = false,
    this.allowReplies = true,
    this.isTimeCapsule = false,
    this.revealAt,
    this.isRevealed = false,
    this.parentSparqId,
    this.chainOrder,
    this.echoCount = 0,
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
      mood: json['mood'] as String? ?? 'happy',
      intensity: json['intensity'] as String? ?? 'warm',
      allowChain: json['allowChain'] as bool? ?? false,
      allowReplies: json['allowReplies'] as bool? ?? true,
      isTimeCapsule: json['isTimeCapsule'] as bool? ?? false,
      revealAt: json['revealAt'] != null
          ? DateTime.parse(json['revealAt'] as String)
          : null,
      isRevealed: json['isRevealed'] as bool? ?? false,
      parentSparqId: json['parentSparqId'] as String?,
      chainOrder: json['chainOrder'] as int?,
      echoCount: json['echoCount'] as int? ?? 0,
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
    'mood': mood,
    'intensity': intensity,
    'allowChain': allowChain,
    'allowReplies': allowReplies,
    'isTimeCapsule': isTimeCapsule,
    'revealAt': revealAt?.toIso8601String(),
    'isRevealed': isRevealed,
    'parentSparqId': parentSparqId,
    'chainOrder': chainOrder,
    'echoCount': echoCount,
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

  // ── Mood Helper Getters ───────────────────────────────────────────

  String get moodEmoji {
    // Retained for backward compat — UI no longer uses emojis in chrome
    switch (mood) {
      case 'happy': return '😊';
      case 'hype': return '🔥';
      case 'love': return '💝';
      case 'sad': return '😢';
      case 'celebrate': return '🎉';
      case 'angry': return '😤';
      default: return '😊';
    }
  }

  Color get moodColor {
    switch (mood) {
      case 'happy': return const Color(0xFFFFB300);     // Amber
      case 'hype': return const Color(0xFFFF5722);      // Electric coral
      case 'love': return const Color(0xFFE91E63);      // Deep rose
      case 'sad': return const Color(0xFF5C7AEA);       // Muted slate-blue
      case 'celebrate': return const Color(0xFFD4AF37);  // Champagne gold
      case 'angry': return const Color(0xFFFF1744);      // Red
      default: return const Color(0xFFFFB300);
    }
  }

  Color get intensityColor {
    switch (intensity) {
      case 'calm': return const Color(0xFF5C7AEA);    // Slate-blue
      case 'warm': return const Color(0xFFFF9800);    // Amber
      case 'fire': return const Color(0xFFFF1744);    // Red
      default: return const Color(0xFFFF9800);
    }
  }

  /// Whether this Sparq is part of a chain
  bool get isChained => parentSparqId != null;

  /// Whether this Sparq is a time capsule that hasn't been revealed yet
  bool get isLockedTimeCapsule => isTimeCapsule && !isRevealed;

  /// Time remaining until reveal (for time capsules)
  Duration? get timeUntilReveal {
    if (revealAt == null) return null;
    final remaining = revealAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
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
    // Handle both flat and nested user object from backend
    // Backend returns: { user: { id, name, username, avatarUrl, photoThumb }, sparqs: [...], allSeen: bool }
    // Legacy format: { userId, userName, userAvatarUrl, sparqs: [...], allSeen: bool }
    final userObj = json['user'];

    String userId;
    String userName;
    String? userAvatarUrl;

    if (userObj is Map<String, dynamic>) {
      // Nested user object from backend
      userId = userObj['id'] as String? ?? '';
      userName = userObj['name'] as String? ?? userObj['username'] as String? ?? '';
      userAvatarUrl = userObj['avatarUrl'] as String? ?? userObj['photoThumb'] as String?;
    } else {
      // Flat format (legacy)
      userId = json['userId'] as String? ?? '';
      userName = json['userName'] as String? ?? '';
      userAvatarUrl = json['userAvatarUrl'] as String?;
    }

    return UserSparqGroup(
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
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
