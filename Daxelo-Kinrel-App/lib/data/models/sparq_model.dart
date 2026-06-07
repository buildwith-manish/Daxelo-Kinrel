// lib/data/models/sparq_model.dart
//
// DAXELO KINREL — Sparq Model
//
// Ephemeral content posts (stories) with multiple media types:
// IMAGE | VIDEO | TEXT | VOICE
//
// Sparqs auto-expire and are grouped by user in the feed.

import '../../features/profile/data/profile_provider.dart';

/// A single Sparq (ephemeral story) item.
class SparqModel {
  const SparqModel({
    required this.id,
    required this.userId,
    required this.type,
    this.mediaUrl,
    this.thumbnailUrl,
    this.text,
    this.bgColor,
    this.duration,
    this.audience = 'PUBLIC',
    required this.expiresAt,
    required this.createdAt,
    this.viewCount = 0,
    this.viewed = false,
  });

  factory SparqModel.fromJson(Map<String, dynamic> json) {
    return SparqModel(
      id: _parseString(json['id']),
      userId: _parseString(json['userId']),
      type: _parseString(json['type'], fallback: 'TEXT').toUpperCase(),
      mediaUrl: json['mediaUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      text: json['text'] as String?,
      bgColor: json['bgColor'] as String?,
      duration: json['duration'] as int?,
      audience: _parseString(json['audience'], fallback: 'PUBLIC').toUpperCase(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString()) ?? DateTime.now()
          : DateTime.now().add(const Duration(hours: 24)),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      viewCount: _parseInt(json['viewCount']),
      viewed: _parseBool(json['viewed']),
    );
  }

  final String id;
  final String userId;

  /// IMAGE | VIDEO | TEXT | VOICE
  final String type;

  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? text;
  final String? bgColor;
  final int? duration; // seconds for VIDEO/VOICE

  /// PUBLIC | FAMILY_ONLY
  final String audience;

  final DateTime expiresAt;
  final DateTime createdAt;
  final int viewCount;
  final bool viewed;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isImage => type == 'IMAGE';
  bool get isVideo => type == 'VIDEO';
  bool get isText => type == 'TEXT';
  bool get isVoice => type == 'VOICE';
  bool get isPublic => audience == 'PUBLIC';

  /// Auto-advance duration in seconds.
  int get autoAdvanceSeconds {
    switch (type) {
      case 'IMAGE':
      case 'TEXT':
        return 5;
      case 'VIDEO':
      case 'VOICE':
        return duration ?? 15;
      default:
        return 5;
    }
  }

  /// Relative time since creation.
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'type': type,
        'mediaUrl': mediaUrl,
        'thumbnailUrl': thumbnailUrl,
        'text': text,
        'bgColor': bgColor,
        'duration': duration,
        'audience': audience,
        'expiresAt': expiresAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'viewCount': viewCount,
        'viewed': viewed,
      };
}

/// A group of Sparqs from the same user, displayed as a ring in the feed.
class UserSparqGroup {
  const UserSparqGroup({
    required this.userId,
    required this.user,
    required this.sparqs,
    this.hasUnseen = false,
    this.totalCount = 0,
  });

  factory UserSparqGroup.fromJson(Map<String, dynamic> json) {
    return UserSparqGroup(
      userId: _parseString(json['userId']),
      user: ProfileModel.fromJson(_extractMap(json['user'])),
      sparqs: (json['sparqs'] as List?)
              ?.map((s) => SparqModel.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      hasUnseen: _parseBool(json['hasUnseen']),
      totalCount: _parseInt(json['totalCount']),
    );
  }

  final String userId;
  final ProfileModel user;
  final List<SparqModel> sparqs;
  final bool hasUnseen;
  final int totalCount;

  /// User initials for avatar fallback.
  String get initials {
    final name = user.name ?? user.username ?? '?';
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}

// ── Safe Parsing Helpers ─────────────────────────────────────────

String _parseString(dynamic value, {String fallback = ''}) {
  if (value is String) return value;
  if (value is int || value is num) return value.toString();
  return fallback;
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is num) return value.toInt();
  return 0;
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  return fallback;
}

Map<String, dynamic> _extractMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    final converted = <String, dynamic>{};
    for (final entry in value.entries) {
      converted[entry.key.toString()] = entry.value;
    }
    return converted;
  }
  return {};
}
