// lib/features/games/shared/models/game_invite_status.dart
//
// Per-member invite status tracking for game room invites.
//
// When a host sends a real-time invite (via SocketService.sendGameInvite),
// we record the recipient's userId as 'pending'. When the recipient taps
// Accept or Decline in the GameInviteListener dialog, the server relays
// a 'game:invite:accepted' or 'game:invite:declined' event back to us;
// we update the status here. After 5 minutes with no response, the status
// automatically flips to 'expired' (client-side timer — no backend change).
//
// The host sees these statuses as small badges in the invite sheet and
// in the lobby's Pending Invites section.

import 'package:flutter/foundation.dart';

/// Per-recipient invite status.
enum InviteMemberStatus {
  /// Invite sent, no response yet.
  pending,

  /// Recipient tapped Accept in their dialog.
  accepted,

  /// Recipient tapped Decline in their dialog.
  declined,

  /// 5 minutes elapsed with no response.
  expired,
}

extension InviteMemberStatusX on InviteMemberStatus {
  String get label {
    switch (this) {
      case InviteMemberStatus.pending:
        return 'Pending';
      case InviteMemberStatus.accepted:
        return 'Accepted';
      case InviteMemberStatus.declined:
        return 'Declined';
      case InviteMemberStatus.expired:
        return 'Expired';
    }
  }
}

/// One record per invited member, keyed by userId in [GameInviteState.invites].
@immutable
class InviteRecord {
  const InviteRecord({
    required this.userId,
    required this.name,
    required this.status,
    required this.sentAt,
    this.username,
    this.avatarUrl,
    this.photoThumb,
    this.respondedAt,
  });

  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? photoThumb;
  final InviteMemberStatus status;

  /// When the invite was sent (client clock).
  final DateTime sentAt;

  /// When the recipient responded (Accept or Decline). Null while pending.
  final DateTime? respondedAt;

  InviteRecord copyWith({
    InviteMemberStatus? status,
    DateTime? respondedAt,
  }) {
    return InviteRecord(
      userId: userId,
      name: name,
      username: username,
      avatarUrl: avatarUrl,
      photoThumb: photoThumb,
      status: status ?? this.status,
      sentAt: sentAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  factory InviteRecord.fromJson(Map<String, dynamic> json) {
    return InviteRecord(
      userId: (json['userId'] ?? '') as String,
      name: (json['name'] ?? 'Family member') as String,
      username: json['username'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      photoThumb: json['photoThumb'] as String?,
      status: InviteMemberStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String? ?? 'pending'),
        orElse: () => InviteMemberStatus.pending,
      ),
      sentAt: json['sentAt'] is String
          ? (DateTime.tryParse(json['sentAt'] as String) ?? DateTime.now())
          : (json['sentAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(json['sentAt'] as int)
              : DateTime.now()),
      respondedAt: json['respondedAt'] is String
          ? DateTime.tryParse(json['respondedAt'] as String)
          : (json['respondedAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(json['respondedAt'] as int)
              : null),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (photoThumb != null) 'photoThumb': photoThumb,
        'status': status.name,
        'sentAt': sentAt.toUtc().toIso8601String(),
        if (respondedAt != null)
          'respondedAt': respondedAt!.toUtc().toIso8601String(),
      };
}

/// State for [GameInviteStatusNotifier]. All invites for ONE game room,
/// keyed by recipient userId so accept/decline events can update in O(1).
@immutable
class GameInviteState {
  const GameInviteState({this.invites = const {}});

  final Map<String, InviteRecord> invites;

  bool get isEmpty => invites.isEmpty;
  int get length => invites.length;

  InviteRecord? operator [](String userId) => invites[userId];

  int countByStatus(InviteMemberStatus s) =>
      invites.values.where((r) => r.status == s).length;

  GameInviteState copyWith({Map<String, InviteRecord>? invites}) {
    return GameInviteState(invites: invites ?? this.invites);
  }
}
