// lib/features/gaming_ecosystem/data/game_registry.dart
//
// The single source of truth for the 14 multiplayer games (+ Ghost Painter).
// Replaces the 15 hard-coded _GameCatalogCards in the old Games hub with a
// typed registry that powers:
//   • the redesigned Games hub grid (categorised, progressive disclosure)
//   • per-game leaderboards
//   • smart match suggestion deep links
//   • match history icons
//
// Design principles applied (per the Family Gaming Ecosystem brief):
//   • Hick's Law — games are grouped into 4 scannable categories instead of
//     one flat 15-item list, reducing choice overload.
//   • Fitts's Law — every Play target is a large, thumb-friendly card body
//     (not a small button).
//   • Progressive disclosure — categories collapse by default to "Featured
//     + Quick Play"; "Explore all" reveals the rest.

/// A game in the Kinrel Family Games catalog.
class GameCatalogEntry {
  const GameCatalogEntry({
    required this.gameId,
    required this.name,
    required this.description,
    required this.gameTable,
    required this.route,
    required this.accent,
    required this.playersLabel,
    required this.category,
    this.sizeEstimate = '~1 MB',
    this.sortOrder = 100,
  });

  /// Slug used by GameAssetManager / GameIcon (`assets/icons/games/<id>.png`).
  final String gameId;

  /// Display name.
  final String name;

  /// One-line description (short, warm, family-first tone).
  final String description;

  /// Supabase table name (used for per-game leaderboards).
  final String gameTable;

  /// Lobby route pattern; {familyId} is substituted at navigation time.
  final String route;

  /// Accent color for cards / borders / icon chips.
  final int accent;

  /// Human player-count hint, e.g. "2–4 players".
  final String playersLabel;

  /// Category for the hub grouping.
  final GameCategory category;

  final String sizeEstimate;
  final int sortOrder;
}

enum GameCategory {
  quickDuels('Quick Duels', '⚡', 'Perfect for a 5-minute break'),
  partyNight('Party Night', '🎉', 'Laugh-out-loud group games'),
  boardClassics('Board Classics', '♟️', 'Timeless favourites, reimagined'),
  indianClassics('Indian Classics', '🇮🇳', 'Games your family grew up with');

  const GameCategory(this.label, this.emoji, this.tagline);
  final String label;
  final String emoji;
  final String tagline;
}

/// All 15 games — ordered as they should appear in the hub.
const kGameCatalog = <GameCatalogEntry>[
  // ── Quick Duels (1v1, fastest to start) ────────────────────────────────
  GameCatalogEntry(
    gameId: 'tictactoe',
    name: 'Tic-Tac-Toe',
    description: 'Classic 3×3 — best of N rounds!',
    gameTable: 'tictactoe_games',
    route: '/family/{familyId}/tictactoe/lobby',
    accent: 0xFF8B5CF6,
    playersLabel: '2 players',
    category: GameCategory.quickDuels,
    sortOrder: 10,
  ),
  GameCatalogEntry(
    gameId: 'chess',
    name: 'Chess',
    description: 'Challenge a family member — checkmate to win!',
    gameTable: 'chess_games',
    route: '/family/{familyId}/chess/lobby',
    accent: 0xFF64748B,
    playersLabel: '2 players',
    category: GameCategory.quickDuels,
    sortOrder: 20,
  ),
  GameCatalogEntry(
    gameId: 'checkers',
    name: 'Checkers',
    description: 'Mandatory captures + kings — pure strategy',
    gameTable: 'checkers_games',
    route: '/family/{familyId}/checkers/lobby',
    accent: 0xFF6366F1,
    playersLabel: '2 players',
    category: GameCategory.quickDuels,
    sortOrder: 30,
  ),
  GameCatalogEntry(
    gameId: 'carrom',
    name: 'Carrom',
    description: 'Flick the striker — pot your coins first!',
    gameTable: 'carrom_games',
    route: '/family/{familyId}/carrom/lobby',
    accent: 0xFFF59E0B,
    playersLabel: '2–4 players',
    category: GameCategory.quickDuels,
    sortOrder: 40,
  ),
  GameCatalogEntry(
    gameId: 'connect4',
    name: 'Connect 4',
    description: 'Drop discs, connect four, win the column!',
    gameTable: 'connect4_games',
    route: '/family/{familyId}/connect4/lobby',
    accent: 0xFF0EA5E9,
    playersLabel: '2 players',
    category: GameCategory.quickDuels,
    sortOrder: 50,
  ),

  // ── Party Night (big groups, laughter) ─────────────────────────────────
  GameCatalogEntry(
    gameId: 'truthordare',
    name: 'Truth or Dare',
    description: 'Spin the bottle — family-submitted prompts!',
    gameTable: 'truthordare_games',
    route: '/family/{familyId}/truthordare/lobby',
    accent: 0xFFEF4444,
    playersLabel: '2–20 players',
    category: GameCategory.partyNight,
    sortOrder: 10,
  ),
  GameCatalogEntry(
    gameId: 'twotruths',
    name: 'Two Truths and a Lie',
    description: 'Fool your family — 2 truths, 1 lie!',
    gameTable: 'twotruths_games',
    route: '/family/{familyId}/twotruths/lobby',
    accent: 0xFFD946EF,
    playersLabel: '2–20 players',
    category: GameCategory.partyNight,
    sortOrder: 20,
  ),
  GameCatalogEntry(
    gameId: 'chitmatch',
    name: 'TripleMatch',
    description: 'Pass chits, collect 3-of-a-kind — 4-12 players!',
    gameTable: 'chitmatch_games',
    route: '/family/{familyId}/chitmatch/lobby',
    accent: 0xFFEC4899,
    playersLabel: '4–12 players',
    category: GameCategory.partyNight,
    sortOrder: 30,
  ),
  GameCatalogEntry(
    gameId: 'freeze-dash',
    name: 'Freeze & Dash',
    description: 'Race to the finish — freeze when Caller calls RED!',
    gameTable: 'redlight_rounds',
    route: '/family/{familyId}/freeze-dash/lobby',
    accent: 0xFF10B981,
    playersLabel: '2–20 players',
    category: GameCategory.partyNight,
    sizeEstimate: '~3 MB',
    sortOrder: 40,
  ),
  GameCatalogEntry(
    gameId: 'ghost-painter',
    name: 'Ghost Painter',
    description: 'Draw a word while your family guesses in real-time',
    gameTable: 'ghost_painter_rounds',
    route: '/family/{familyId}/ghost-painter/draw',
    accent: 0xFFEC4899,
    playersLabel: '2+ players',
    category: GameCategory.partyNight,
    sortOrder: 50,
  ),
  GameCatalogEntry(
    gameId: 'tug-of-war',
    name: 'Tug of War',
    description: 'Two teams, one rope — tap PULL with all your might!',
    gameTable: 'tugofwar_games',
    route: '/family/{familyId}/tug-of-war/lobby',
    accent: 0xFFE8612A,
    playersLabel: '2–20 players',
    category: GameCategory.partyNight,
    sortOrder: 60,
  ),
  GameCatalogEntry(
    gameId: 'memory-match',
    name: 'Memory Match',
    description: 'Flip, remember, match — sharpest memory wins!',
    gameTable: 'memorymatch_games',
    route: '/family/{familyId}/memory-match/lobby',
    accent: 0xFFA855F7,
    playersLabel: '2–4 players',
    category: GameCategory.partyNight,
    sortOrder: 70,
  ),
  GameCatalogEntry(
    gameId: 'impostor',
    name: 'Who\'s the Impostor?',
    description: 'Social deduction — blend in or get caught!',
    gameTable: 'impostor_games',
    route: '/family/{familyId}/impostor/lobby',
    accent: 0xFF8B5CF6,
    playersLabel: '3–10 players',
    category: GameCategory.partyNight,
    sortOrder: 80,
  ),

  // ── Board Classics ─────────────────────────────────────────────────────
  GameCatalogEntry(
    gameId: 'ludo',
    name: 'Ludo',
    description: 'Roll, race, and capture — the classic board race',
    gameTable: 'ludo_games',
    route: '/family/{familyId}/ludo/lobby',
    accent: 0xFFE11D48,
    playersLabel: '2–4 players',
    category: GameCategory.boardClassics,
    sortOrder: 10,
  ),
  GameCatalogEntry(
    gameId: 'bingo',
    name: 'Bingo',
    description: 'Mark your 5×5 card — first line wins!',
    gameTable: 'bingo_games',
    route: '/family/{familyId}/bingo/lobby',
    accent: 0xFF06B6D4,
    playersLabel: '2–100 players',
    category: GameCategory.boardClassics,
    sortOrder: 20,
  ),
  GameCatalogEntry(
    gameId: 'dotsboxes',
    name: 'Dots and Boxes',
    description: 'Draw lines, capture boxes — most boxes wins!',
    gameTable: 'dotsboxes_games',
    route: '/family/{familyId}/dotsboxes/lobby',
    accent: 0xFF06B6D4,
    playersLabel: '2–4 players',
    category: GameCategory.boardClassics,
    sortOrder: 30,
  ),

  // ── Indian Classics ────────────────────────────────────────────────────
  GameCatalogEntry(
    gameId: 'antakshari',
    name: 'Antakshari',
    description: 'Sing the letter chain — with challenge mechanic',
    gameTable: 'antakshari_games',
    route: '/family/{familyId}/antakshari/lobby',
    accent: 0xFF8B5CF6,
    playersLabel: '2–50 players',
    category: GameCategory.indianClassics,
    sortOrder: 10,
  ),
  GameCatalogEntry(
    gameId: 'nameplace',
    name: 'Name, Place, Animal, Thing',
    description: 'Pick a letter, fill categories, score unique answers!',
    gameTable: 'nameplace_games',
    route: '/family/{familyId}/nameplace/lobby',
    accent: 0xFF10B981,
    playersLabel: '2–20 players',
    category: GameCategory.indianClassics,
    sortOrder: 20,
  ),
  GameCatalogEntry(
    gameId: 'sos',
    name: 'SOS',
    description: 'Complete S-O-S sequences — solo or team mode',
    gameTable: 'sos_games',
    route: '/family/{familyId}/sos/lobby',
    accent: 0xFFF59E0B,
    playersLabel: '2–4 players',
    category: GameCategory.indianClassics,
    sortOrder: 30,
  ),
  GameCatalogEntry(
    gameId: 'ashta-chamma',
    name: 'Ashta Chamma',
    description: 'Traditional Indian strategy — cowrie shells, captures, '
        'and the race home',
    gameTable: 'ashta_chamma_games',
    route: '/family/{familyId}/ashta-chamma/lobby',
    accent: 0xFFE11D48,
    playersLabel: '2–4 players',
    category: GameCategory.indianClassics,
    sortOrder: 40,
  ),
  GameCatalogEntry(
    gameId: 'color-trap',
    name: 'Color Trap',
    description: 'Last player standing — move to the safe color or fall!',
    gameTable: 'color_trap_games',
    route: '/family/{familyId}/color-trap/lobby',
    accent: 0xFFF59E0B,
    playersLabel: '2–8 players',
    category: GameCategory.partyNight,
    sortOrder: 90,
  ),
  GameCatalogEntry(
    gameId: 'freeze-auction',
    name: 'Freeze Auction',
    description: 'Bid on mystery crates — rewards or traps await!',
    gameTable: 'freeze_auction_games',
    route: '/family/{familyId}/freeze-auction/lobby',
    accent: 0xFFF59E0B,
    playersLabel: '2–8 players',
    category: GameCategory.partyNight,
    sortOrder: 100,
  ),
  GameCatalogEntry(
    gameId: 'flick-arena',
    name: 'Flick Arena',
    description: 'Flick discs into the goal — physics strategy',
    gameTable: 'flick_arena_games',
    route: '/family/{familyId}/flick-arena/lobby',
    accent: 0xFF22D3EE,
    playersLabel: '2–4 players',
    category: GameCategory.quickDuels,
    sortOrder: 60,
  ),
  GameCatalogEntry(
    gameId: 'secret-heist',
    name: 'Secret Heist',
    description: 'Bluff, steal, outsmart — hidden-role heist',
    gameTable: 'secret_heist_games',
    route: '/family/{familyId}/secret-heist/lobby',
    accent: 0xFF10B981,
    playersLabel: '3–8 players',
    category: GameCategory.partyNight,
    sortOrder: 110,
  ),
  GameCatalogEntry(
    gameId: 'mind-match',
    name: 'Mind Match',
    description: 'Think like everyone else — match answers, earn points',
    gameTable: 'mind_match_games',
    route: '/family/{familyId}/mind-match/lobby',
    accent: 0xFFF472B6,
    playersLabel: '2–8 players',
    category: GameCategory.partyNight,
    sortOrder: 120,
  ),
  GameCatalogEntry(
    gameId: 'code-clues',
    name: 'Code Clues',
    description: 'Codenames-style word association — teams + spymasters',
    gameTable: 'code_clues_games',
    route: '/family/{familyId}/code-clues/lobby',
    accent: 0xFFF59E0B,
    playersLabel: '4–8 players',
    category: GameCategory.partyNight,
    sortOrder: 130,
  ),
  GameCatalogEntry(
    gameId: 'night-falls',
    name: 'Night Falls',
    description: 'Classic Werewolf — werewolves, seer, doctor, hunter',
    gameTable: 'night_falls_games',
    route: '/family/{familyId}/night-falls/lobby',
    accent: 0xFF6366F1,
    playersLabel: '5–12 players',
    category: GameCategory.partyNight,
    sortOrder: 140,
  ),
  GameCatalogEntry(
    gameId: 'sketch-telephone',
    name: 'Sketch Telephone',
    description: 'Draw, describe, draw again — hilarious chain game',
    gameTable: 'sketch_telephone_games',
    route: '/family/{familyId}/sketch-telephone/lobby',
    accent: 0xFFEC4899,
    playersLabel: '4–8 players',
    category: GameCategory.partyNight,
    sortOrder: 150,
  ),
  GameCatalogEntry(
    gameId: 'word-forge',
    name: 'Word Forge',
    description: 'Fake definitions for obscure words — fool your family',
    gameTable: 'word_forge_games',
    route: '/family/{familyId}/word-forge/lobby',
    accent: 0xFF8B5CF6,
    playersLabel: '3–8 players',
    category: GameCategory.partyNight,
    sortOrder: 160,
  ),
  GameCatalogEntry(
    gameId: 'stickman-heist',
    name: 'Stickman Heist',
    description: 'Treasure hunt shooter — steal, chase, escape',
    gameTable: 'stickman_heist_games',
    route: '/family/{familyId}/stickman-heist/lobby',
    accent: 0xFFEF4444,
    playersLabel: '2–8 players',
    category: GameCategory.quickDuels,
    sortOrder: 70,
  ),
  GameCatalogEntry(
    gameId: 'crystal-bridge',
    name: 'Crystal Bridge',
    description: 'Survival · Risk vs Reward — cross the bridge, one crystal saves you',
    gameTable: 'crystal_bridge_games',
    route: '/family/{familyId}/crystal-bridge/lobby',
    accent: 0xFF06B6D4,
    playersLabel: '2–8 players',
    category: GameCategory.partyNight,
    sortOrder: 75,
  ),
];

/// All catalog entries sorted for hub display (featured first).
List<GameCatalogEntry> gamesByCategory(GameCategory category) =>
    kGameCatalog
        .where((g) => g.category == category)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

/// Finds a catalog entry by its Supabase table name.
GameCatalogEntry? gameByTable(String? gameTable) {
  if (gameTable == null) return null;
  for (final g in kGameCatalog) {
    if (g.gameTable == gameTable) return g;
  }
  return null;
}

/// Finds a catalog entry by its hub slug (gameId).
GameCatalogEntry? gameById(String? gameId) {
  if (gameId == null) return null;
  for (final g in kGameCatalog) {
    if (g.gameId == gameId) return g;
  }
  return null;
}

/// Resolves the lobby route for a game + family.
String gameRoute(GameCatalogEntry game, String familyId) =>
    game.route.replaceFirst('{familyId}', familyId);
