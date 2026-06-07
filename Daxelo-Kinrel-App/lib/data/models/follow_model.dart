// lib/data/models/follow_model.dart
//
// DAXELO KINREL — Follow Model
//
// Represents a follow relationship between users.
// Status flow: PENDING → ACCEPTED | REJECTED

import '../../features/profile/data/profile_provider.dart';

/// Represents a follow relationship between two users.
class FollowModel {
  const FollowModel({
    required this.id,
    required this.followerId,
    required this.followingId,
    this.status = 'PENDING',
    required this.createdAt,
    this.follower,
    this.following,
  });

  factory FollowModel.fromJson(Map<String, dynamic> json) {
    return FollowModel(
      id: _parseString(json['id']),
      followerId: _parseString(json['followerId']),
      followingId: _parseString(json['followingId']),
      status: _parseString(json['status'], fallback: 'PENDING').toUpperCase(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      follower: json['follower'] != null
          ? ProfileModel.fromJson(
              _extractMap(json['follower']),
            )
          : null,
      following: json['following'] != null
          ? ProfileModel.fromJson(
              _extractMap(json['following']),
            )
          : null,
    );
  }

  final String id;
  final String followerId;
  final String followingId;

  /// PENDING | ACCEPTED | REJECTED
  final String status;
  final DateTime createdAt;

  /// The user who initiated the follow.
  final ProfileModel? follower;

  /// The user being followed.
  final ProfileModel? following;

  bool get isPending => status == 'PENDING';
  bool get isAccepted => status == 'ACCEPTED';
  bool get isRejected => status == 'REJECTED';

  Map<String, dynamic> toJson() => {
        'id': id,
        'followerId': followerId,
        'followingId': followingId,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        if (follower != null) 'follower': follower!.toJson(),
        if (following != null) 'following': following!.toJson(),
      };
}

// ── Safe Parsing Helpers ─────────────────────────────────────────

String _parseString(dynamic value, {String fallback = ''}) {
  if (value is String) return value;
  if (value is int || value is num) return value.toString();
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
