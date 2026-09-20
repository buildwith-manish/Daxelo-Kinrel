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
  tugOfWar, // Tug of War
  memoryMatch, // Memory Match
  ashtaChamma, // Ashta Chamma (Chowka Bhara)
  connect4, // Connect 4
  impostor, // Who's the Impostor?
  colorTrap, // Color Trap
  freezeAuction, // Freeze Auction
  flickArena, // Flick Arena
  secretHeist, // Secret Heist
  mindMatch, // Mind Match
  wordForge, // Word Forge (Balderdash-style fake definitions)
  codeClues, // Code Clues (Codenames-style word association)
  nightFalls, // Night Falls (Werewolf)
  sketchTelephone, // Sketch Telephone (Gartic Phone-style drawing chain)
  stickmanHeist, // Stickman Heist (real-time top-down treasure-hunt shooter)
  crystalBridge, // Crystal Bridge (turn-based bridge-crossing survival)
  ghostPainter, // Ghost Painter (real-time family draw-and-guess)
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
      case GameType.tugOfWar:
        return 'tug-of-war';
      case GameType.memoryMatch:
        return 'memory-match';
      case GameType.ashtaChamma:
        return 'ashta-chamma';
      case GameType.connect4:
        return 'connect4';
      case GameType.impostor:
        return 'impostor';
      case GameType.colorTrap:
        return 'color-trap';
      case GameType.freezeAuction:
        return 'freeze-auction';
      case GameType.flickArena:
        return 'flick-arena';
      case GameType.secretHeist:
        return 'secret-heist';
      case GameType.mindMatch:
        return 'mind-match';
      case GameType.wordForge:
        return 'word-forge';
      case GameType.codeClues:
        return 'code-clues';
      case GameType.nightFalls:
        return 'night-falls';
      case GameType.sketchTelephone:
        return 'sketch-telephone';
      case GameType.stickmanHeist:
        return 'stickman-heist';
      case GameType.crystalBridge:
        return 'crystal-bridge';
      case GameType.ghostPainter:
        return 'ghost-painter';
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
      case GameType.tugOfWar:
        return 'Tug of War';
      case GameType.memoryMatch:
        return 'Memory Match';
      case GameType.ashtaChamma:
        return 'Ashta Chamma';
      case GameType.connect4:
        return 'Connect 4';
      case GameType.impostor:
        return 'Who\'s the Impostor?';
      case GameType.colorTrap:
        return 'Color Trap';
      case GameType.freezeAuction:
        return 'Freeze Auction';
      case GameType.flickArena:
        return 'Flick Arena';
      case GameType.secretHeist:
        return 'Secret Heist';
      case GameType.mindMatch:
        return 'Mind Match';
      case GameType.wordForge:
        return 'Word Forge';
      case GameType.codeClues:
        return 'Code Clues';
      case GameType.nightFalls:
        return 'Night Falls';
      case GameType.sketchTelephone:
        return 'Sketch Telephone';
      case GameType.stickmanHeist:
        return 'Stickman Heist';
      case GameType.crystalBridge:
        return 'Crystal Bridge';
      case GameType.ghostPainter:
        return 'Ghost Painter';
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

/// The canonical forward map: [GameType] → Postgres table name, used
/// wherever a game_invites row is inserted (the invite sheet, the shared
/// RematchButton, …).
///
/// MUST stay in lockstep with the reverse map `gameTypeForTable` in
/// family_invite_card.dart — the game-registration contract test
/// (test/features/games/game_registration_contract_test.dart) fails the
/// build if a GameType is added without its table (or vice versa). This
/// used to be TWO hand-copied private switches (invite sheet + rematch
/// button) alongside the reverse map; Ghost Painter shipped unwired
/// precisely because a copy missed a game.
String gameTableForType(GameType t) {
  switch (t) {
    case GameType.bingo: return 'bingo_games';
    case GameType.ludo: return 'ludo_games';
    case GameType.checkers: return 'checkers_games';
    case GameType.carrom: return 'carrom_games';
    case GameType.chess: return 'chess_games';
    case GameType.chitmatch: return 'chitmatch_games';
    case GameType.nameplace: return 'nameplace_games';
    case GameType.tictactoe: return 'tictactoe_games';
    case GameType.truthordare: return 'truthordare_games';
    case GameType.twotruths: return 'twotruths_games';
    case GameType.dotsboxes: return 'dotsboxes_games';
    case GameType.sos: return 'sos_games';
    case GameType.antakshari: return 'antakshari_games';
    case GameType.redlight: return 'redlight_rounds';
    case GameType.tugOfWar: return 'tugofwar_games';
    case GameType.memoryMatch: return 'memorymatch_games';
    case GameType.ashtaChamma: return 'ashta_chamma_games';
    case GameType.connect4: return 'connect4_games';
    case GameType.impostor: return 'impostor_games';
    case GameType.colorTrap: return 'color_trap_games';
    case GameType.freezeAuction: return 'freeze_auction_games';
    case GameType.flickArena: return 'flick_arena_games';
    case GameType.secretHeist: return 'secret_heist_games';
    case GameType.mindMatch: return 'mind_match_games';
    case GameType.wordForge: return 'word_forge_games';
    case GameType.codeClues: return 'code_clues_games';
    case GameType.nightFalls: return 'night_falls_games';
    case GameType.sketchTelephone: return 'sketch_telephone_games';
    case GameType.stickmanHeist: return 'stickman_heist_games';
    case GameType.crystalBridge: return 'crystal_bridge_games';
    // ── QA fix 2026-09-20: registered together with the GameType.ghostPainter
    // enum member and the reverse case in gameTypeForTable — the contract
    // test keeps all three in lockstep.
    case GameType.ghostPainter: return 'ghost_painter_rounds';
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

  /// Deep-link path that navigates the recipient into the host's game:
  /// EVERY game (including the board games — chess, checkers, carrom,
  /// tictactoe) joins via the lobby's `?join=<gameId>` flow. The lobby
  /// takes the joiner straight into the shared waiting room, where
  /// they take the free opponent slot automatically; if the match is
  /// already running they land there as a spectator.
  String get joinRoute =>
      '/family/$familyId/${gameType.routeSegment}/lobby?join=$gameId';
}

/// Server-relayed event: recipient tapped "Accept" on their invite dialog.
///
/// The server emits this back to the original sender via
/// `game:invite:accepted`. The sender's [GameInviteStatusNotifier] uses
/// this to flip the recipient's status from 'pending' to 'accepted'.
class GameInviteAcceptedEvent {
  const GameInviteAcceptedEvent({
    required this.inviteId,
    required this.gameId,
    required this.gameType,
    required this.familyId,
    required this.acceptedByUserId,
  });

  final String inviteId;
  final String gameId;
  final String gameType;
  final String familyId;
  final String acceptedByUserId;
}

/// Server-relayed event: recipient tapped "Decline" on their invite dialog.
class GameInviteDeclinedEvent {
  const GameInviteDeclinedEvent({
    required this.inviteId,
    required this.gameId,
    required this.declinedByUserId,
  });

  final String inviteId;
  final String gameId;
  final String declinedByUserId;
}
