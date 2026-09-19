// lib/features/games/shared/multiplayer/room_config.dart
//
// Per-game configuration for the shared multiplayer room framework.
// Every multiplayer game (SOS, Bingo, Ludo, Chess, etc.) provides a
// RoomConfig to the [RoomController] so it knows which table to read/
// write, what the min/max players are, and what the lobby status names
// are for that game (each game uses slightly different status strings).
//
// This is the SINGLE point of game-specific knowledge the framework
// needs — everything else is generic. Adding a new multiplayer game
// is a 3-line change: define a RoomConfig, hand it to a RoomController,
// render LobbyView.

/// The list of game tables supported by the framework.
/// Mirrors the SQL migration's table list.
enum GameTableKind {
  bingoGames,        // bingo_games
  ludoGames,         // ludo_games
  checkersGames,     // checkers_games
  carromGames,       // carrom_games
  chessGames,        // chess_games
  sosGames,          // sos_games
  antakshariGames,   // antakshari_games
  tictactoeGames,    // tictactoe_games
  truthordareGames,  // truthordare_games
  twotruthsGames,    // twotruths_games
  dotsboxesGames,    // dotsboxes_games
  nameplaceGames,    // nameplace_games
  chitmatchGames,    // chitmatch_games
  redlightRounds,    // redlight_rounds
  tugofwarGames,     // tugofwar_games
  memoryMatchGames,  // memorymatch_games
  flickArenaGames,   // flick_arena_games
  secretHeistGames,  // secret_heist_games
  mindMatchGames,    // mind_match_games
  codeCluesGames,    // code_clues_games
  nightFallsGames,   // night_falls_games
  sketchTelephoneGames, // sketch_telephone_games
  wordForgeGames,    // word_forge_games
}

extension GameTableKindX on GameTableKind {
  /// The actual Postgres table name (e.g. 'sos_games').
  String get tableName {
    switch (this) {
      case GameTableKind.bingoGames:        return 'bingo_games';
      case GameTableKind.ludoGames:         return 'ludo_games';
      case GameTableKind.checkersGames:     return 'checkers_games';
      case GameTableKind.carromGames:       return 'carrom_games';
      case GameTableKind.chessGames:        return 'chess_games';
      case GameTableKind.sosGames:          return 'sos_games';
      case GameTableKind.antakshariGames:   return 'antakshari_games';
      case GameTableKind.tictactoeGames:    return 'tictactoe_games';
      case GameTableKind.truthordareGames:  return 'truthordare_games';
      case GameTableKind.twotruthsGames:    return 'twotruths_games';
      case GameTableKind.dotsboxesGames:    return 'dotsboxes_games';
      case GameTableKind.nameplaceGames:    return 'nameplace_games';
      case GameTableKind.chitmatchGames:    return 'chitmatch_games';
      case GameTableKind.redlightRounds:    return 'redlight_rounds';
      case GameTableKind.tugofwarGames:     return 'tugofwar_games';
      case GameTableKind.memoryMatchGames:  return 'memorymatch_games';
      case GameTableKind.flickArenaGames:   return 'flick_arena_games';
      case GameTableKind.secretHeistGames:  return 'secret_heist_games';
      case GameTableKind.mindMatchGames:    return 'mind_match_games';
      case GameTableKind.codeCluesGames:    return 'code_clues_games';
      case GameTableKind.nightFallsGames:   return 'night_falls_games';
      case GameTableKind.sketchTelephoneGames: return 'sketch_telephone_games';
      case GameTableKind.wordForgeGames:    return 'word_forge_games';
    }
  }

  /// The players-table name (e.g. 'sos_players'). For inline-player
  /// games (chess, checkers, carrom, tictactoe), this returns null and
  /// the framework falls back to UPDATEs on the game row's playerXId /
  /// playerOneId columns.
  String? get playersTableName {
    switch (this) {
      case GameTableKind.chessGames:
      case GameTableKind.checkersGames:
      case GameTableKind.carromGames:
      case GameTableKind.tictactoeGames:
        return null;
      case GameTableKind.bingoGames:        return 'bingo_cards';
      case GameTableKind.ludoGames:         return 'ludo_players';
      case GameTableKind.sosGames:          return 'sos_players';
      case GameTableKind.antakshariGames:   return 'antakshari_players';
      case GameTableKind.truthordareGames:  return 'truthordare_players';
      case GameTableKind.twotruthsGames:    return 'twotruths_players';
      case GameTableKind.dotsboxesGames:    return 'dotsboxes_players';
      case GameTableKind.nameplaceGames:    return 'nameplace_players';
      case GameTableKind.chitmatchGames:    return 'chitmatch_players';
      case GameTableKind.redlightRounds:    return 'redlight_players';
      case GameTableKind.tugofwarGames:     return 'tugofwar_players';
      case GameTableKind.memoryMatchGames:  return 'memorymatch_players';
      case GameTableKind.flickArenaGames:   return null; // inline player slots
      case GameTableKind.secretHeistGames:  return 'secret_heist_players';
      case GameTableKind.mindMatchGames:    return 'mind_match_players';
      case GameTableKind.codeCluesGames:    return 'code_clues_players';
      case GameTableKind.nightFallsGames:   return 'night_falls_players';
      case GameTableKind.sketchTelephoneGames: return 'sketch_telephone_players';
      case GameTableKind.wordForgeGames:    return 'word_forge_players';
    }
  }
}

/// Per-game configuration. Passed to [RoomController] at construction.
class RoomConfig {
  const RoomConfig({
    required this.gameTable,
    required this.minPlayers,
    required this.maxPlayers,
    required this.lobbyStatusValue,
    required this.activeStatusValue,
    required this.finishedStatusValue,
    this.cancelledStatusValue,
    this.defaultAutoCloseMinutes = 5,
  });

  /// The game's primary table (e.g. GameTableKind.sosGames).
  final GameTableKind gameTable;

  /// Minimum players required to start the game.
  final int minPlayers;

  /// Maximum players allowed in the room.
  final int maxPlayers;

  /// The status string the game uses for the "lobby" / "waiting" state.
  /// Each game uses its own convention ('lobby' for SOS, 'waiting' for Ludo,
  /// 'waiting' for Bingo). The framework needs to know which value to write
  /// when creating a room, and which value to look for when checking "is the
  /// room still in lobby?".
  final String lobbyStatusValue;

  /// The status string for an active (started) game.
  final String activeStatusValue;

  /// The status string for a finished game.
  final String finishedStatusValue;

  /// The status string for a cancelled game (used by Cancel Room).
  /// If null, the framework writes 'cancelled' into the status column.
  /// Most games use their lobbyStatusValue as the cancelled indicator
  /// + set cancelledAt; we keep this configurable for games that have
  /// a distinct 'cancelled' / 'abandoned' status enum.
  final String? cancelledStatusValue;

  /// Default auto-close duration (in minutes) if the host doesn't pick one.
  /// 5 minutes is a sensible default — short enough that abandoned rooms
  /// don't linger, long enough that invites have time to be accepted.
  final int defaultAutoCloseMinutes;

  /// Static presets for each supported game. Use these instead of
  /// constructing a RoomConfig manually — they encode the per-game
  /// status string conventions that match the existing migrations.
  static const sos = RoomConfig(
    gameTable: GameTableKind.sosGames,
    minPlayers: 2,
    maxPlayers: 4,
    lobbyStatusValue: 'lobby',
    activeStatusValue: 'active',
    finishedStatusValue: 'finished',
    cancelledStatusValue: 'cancelled',
  );

  static const bingo = RoomConfig(
    gameTable: GameTableKind.bingoGames,
    minPlayers: 2,
    maxPlayers: 100, // Bingo supports large rooms
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
    defaultAutoCloseMinutes: 10,
  );

  static const ludo = RoomConfig(
    gameTable: GameTableKind.ludoGames,
    minPlayers: 2,
    maxPlayers: 4,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const chess = RoomConfig(
    gameTable: GameTableKind.chessGames,
    minPlayers: 2,
    maxPlayers: 2,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const checkers = RoomConfig(
    gameTable: GameTableKind.checkersGames,
    minPlayers: 2,
    maxPlayers: 2,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const carrom = RoomConfig(
    gameTable: GameTableKind.carromGames,
    minPlayers: 2,
    maxPlayers: 4,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const tictactoe = RoomConfig(
    gameTable: GameTableKind.tictactoeGames,
    minPlayers: 2,
    maxPlayers: 2,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const truthordare = RoomConfig(
    gameTable: GameTableKind.truthordareGames,
    minPlayers: 2,
    maxPlayers: 20,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const twotruths = RoomConfig(
    gameTable: GameTableKind.twotruthsGames,
    minPlayers: 2,
    maxPlayers: 20,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const dotsboxes = RoomConfig(
    gameTable: GameTableKind.dotsboxesGames,
    minPlayers: 2,
    maxPlayers: 4,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const nameplace = RoomConfig(
    gameTable: GameTableKind.nameplaceGames,
    minPlayers: 2,
    maxPlayers: 20,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const chitmatch = RoomConfig(
    gameTable: GameTableKind.chitmatchGames,
    minPlayers: 2,
    maxPlayers: 20,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const antakshari = RoomConfig(
    gameTable: GameTableKind.antakshariGames,
    minPlayers: 2,
    maxPlayers: 50,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const redlight = RoomConfig(
    gameTable: GameTableKind.redlightRounds,
    minPlayers: 2,
    maxPlayers: 20,
    lobbyStatusValue: 'lobby',
    activeStatusValue: 'active',
    finishedStatusValue: 'finished',
    cancelledStatusValue: 'cancelled',
  );

  static const tugofwar = RoomConfig(
    gameTable: GameTableKind.tugofwarGames,
    minPlayers: 2,
    maxPlayers: 20, // 1v1 up to 10v10
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const memoryMatch = RoomConfig(
    gameTable: GameTableKind.memoryMatchGames,
    minPlayers: 2,
    maxPlayers: 4, // individual competition — 2, 3 or 4 players
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const flickArena = RoomConfig(
    gameTable: GameTableKind.flickArenaGames,
    minPlayers: 2,
    maxPlayers: 4, // 1v1 (Solo Duel) or 2v2 (Team Battle)
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const secretHeist = RoomConfig(
    gameTable: GameTableKind.secretHeistGames,
    minPlayers: 3,
    maxPlayers: 8,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const mindMatch = RoomConfig(
    gameTable: GameTableKind.mindMatchGames,
    minPlayers: 2,
    maxPlayers: 8,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const codeClues = RoomConfig(
    gameTable: GameTableKind.codeCluesGames,
    minPlayers: 4,
    maxPlayers: 8,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const nightFalls = RoomConfig(
    gameTable: GameTableKind.nightFallsGames,
    minPlayers: 5,
    maxPlayers: 12,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const sketchTelephone = RoomConfig(
    gameTable: GameTableKind.sketchTelephoneGames,
    minPlayers: 4,
    maxPlayers: 8,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );

  static const wordForge = RoomConfig(
    gameTable: GameTableKind.wordForgeGames,
    minPlayers: 3,
    maxPlayers: 8,
    lobbyStatusValue: 'waiting',
    activeStatusValue: 'in_progress',
    finishedStatusValue: 'completed',
    cancelledStatusValue: 'cancelled',
  );
}
