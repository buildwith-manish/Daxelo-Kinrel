// lib/features/games/shared/models/game_invite.dart
//
// Model for a "Family Space" game invite delivered in real-time via
// the NestJS KinrelGateway socket.
//
// These invites are sent from a game lobby when the host taps "Invite"
// next to a linked family member. The recipient sees an in-app dialog
// with Accept / Decline actions; Accepting navigates them into the
// sender's game lobby with the correct room code pre-applied.

/// The 14 game types that support Family-Space invites.
///
/// The string value matches the URL path segment used in app_router.dart,
/// e.g. `GameType.bingo.routeSegment` -> 'bingo' -> '/family/:id/bingo/lobby'.
enum GameType {
  bingo,
  ludo,
  checkers,
  carrom,
  chess,
  chitmatch,
  nameplace,
  tictactoe,
  truthordare,
  twotruths,
  dotsboxes,
  sos,
  antakshari,
  redlight, // Freeze & Dash
}

extension GameTypeX on GameType {
  /// URL path segment used between `/family/:id/` and `/lobby`.
  String get routeSegment {
    switch (this) {
      case GameType.bingo:
        return 'bingo';
      case GameType.ludo:
        return 'ludo';
      case GameType.checkers:
        return 'checkers';
      case GameType.carrom:
        return 'carrom';
      case GameType.chess:
        return 'chess';
      case GameType.chitmatch:
        return 'chitmatch';
      case GameType.nameplace:
        return 'nameplace';
      case GameType.tictactoe:
        return 'tictactoe';
      case GameType.truthordare:
        return 'truthordare';
      case GameType.twotruths:
        return 'twotruths';
      case GameType.dotsboxes:
        return 'dotsboxes';
      case GameType.sos:
        return 'sos';
      case GameType.antakshari:
        return 'antakshari';
      case GameType.redlight:
        return 'freeze-dash';
    }
  }

  /// Human-friendly display name shown in invite dialogs.
  String get displayName {
    switch (this) {
      case GameType.bingo:
        return 'Bingo';
      case GameType.ludo:
        return 'Ludo';
      case GameType.checkers:
        return 'Checkers';
      case GameType.carrom:
        return 'Carrom';
      case GameType.chess:
        return 'Chess';
      case GameType.chitmatch:
        return 'TripleMatch';
      case GameType.nameplace:
        return 'Name, Place, Animal, Thing';
      case GameType.tictactoe:
        return 'Tic-Tac-Toe';
      case GameType.truthordare:
        return 'Truth or Dare';
      case GameType.twotruths:
        return 'Two Truths and a Lie';
      case GameType.dotsboxes:
        return 'Dots and Boxes';
      case GameType.sos:
        return 'SOS';
      case GameType.antakshari:
        return 'Antakshari';
      case GameType.redlight:
        return 'Freeze & Dash';
    }
  }

  /// Parses a [routeSegment] back into a [GameType].
  /// Returns null if the segment is unknown.
  static GameType? fromRouteSegment(String segment) {
    for (final t in GameType.values) {
      if (t.routeSegment == segment) return t;
    }
    return null;
  }

  /// Parses a [displayName] back into a [GameType].
  static GameType? fromDisplayName(String name) {
    for (final t in GameType.values) {
      if (t.displayName.toLowerCase() == name.toLowerCase()) return t;
    }
    return null;
  }
}

/// A real-time game invite, sent from a host to a linked family member.
///
/// Wire format (JSON) — matches what the NestJS KinrelGateway emits on the
/// `game:invite:received` event:
/// ```json
/// {
///   "inviteId": "inv_xxx",
///   "gameType": "bingo",
///   "gameId":   "uuid-of-bingo_games-row",
///   "roomCode": "AB12CD",
///   "familyId": "uuid-of-family",
///   "fromUserId": "uuid",
///   "fromName": "Aunt Rita",
///   "maxPlayers": 30,
///   "currentPlayers": 1,
///   "message": "Join my Bingo room!",
///   "timestamp": "2026-07-05T16:00:00.000Z"
/// }
/// ```
class GameInvite {
  const GameInvite({
    required this.inviteId,
    required this.gameType,
    required this.gameId,
    required this.roomCode,
    required this.familyId,
    required this.fromUserId,
    required this.fromName,
    required this.maxPlayers,
    required this.currentPlayers,
    this.message,
    this.timestamp,
  });

  final String inviteId;
  final GameType gameType;
  final String gameId;
  final String roomCode;
  final String familyId;
  final String fromUserId;
  final String fromName;
  final int maxPlayers;
  final int currentPlayers;
  final String? message;
  final DateTime? timestamp;

  factory GameInvite.fromJson(Map<String, dynamic> json) {
    final rawGameType = json['gameType'] as String?;
    final gameType = GameTypeX.fromRouteSegment(rawGameType ?? '') ??
        GameTypeX.fromDisplayName(rawGameType ?? '') ??
        GameType.bingo;

    final rawTs = json['timestamp'];
    DateTime? ts;
    if (rawTs is String) {
      ts = DateTime.tryParse(rawTs);
    } else if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is num) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs.toInt());
    }

    return GameInvite(
      inviteId: (json['inviteId'] ?? json['invite_id'] ?? '') as String,
      gameType: gameType,
      gameId: (json['gameId'] ?? json['game_id'] ?? '') as String,
      roomCode: (json['roomCode'] ?? json['room_code'] ?? '') as String,
      familyId: (json['familyId'] ?? json['family_id'] ?? '') as String,
      fromUserId: (json['fromUserId'] ?? json['from_user_id'] ?? '') as String,
      fromName: (json['fromName'] ?? json['from_name'] ?? 'Family member') as String,
      maxPlayers: (json['maxPlayers'] ?? json['max_players'] ?? 2) as int,
      currentPlayers: (json['currentPlayers'] ?? json['current_players'] ?? 1) as int,
      message: json['message'] as String?,
      timestamp: ts,
    );
  }

  Map<String, dynamic> toJson() => {
        'inviteId': inviteId,
        'gameType': gameType.routeSegment,
        'gameId': gameId,
        'roomCode': roomCode,
        'familyId': familyId,
        'fromUserId': fromUserId,
        'fromName': fromName,
        'maxPlayers': maxPlayers,
        'currentPlayers': currentPlayers,
        if (message != null) 'message': message,
      };

  /// Deep-link path that navigates the recipient into the host's lobby
  /// with the room code pre-applied via the `?join=<gameId>` query param.
  String get joinRoute =>
      '/family/$familyId/${gameType.routeSegment}/lobby?join=$gameId';
}
