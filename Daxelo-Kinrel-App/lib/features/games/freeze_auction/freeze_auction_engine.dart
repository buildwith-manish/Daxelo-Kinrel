// lib/features/games/freeze_auction/freeze_auction_engine.dart
//
// Freeze Auction — pure Dart game engine.
//
// Social strategy game: players bid coins on mystery crates each round.
// Highest bid wins the crate, which is revealed to contain a reward or
// penalty. Mix of bluffing, risk-taking, and resource management.
// 2–8 players, 5/10/15 rounds. Last player with most coins wins.

import 'dart:math';

const int kFreezeAuctionMinPlayers = 2;
const int kFreezeAuctionMaxPlayers = 8;

enum AuctionItemRarity { common, rare, epic, legendary, trap }

extension AuctionItemRarityX on AuctionItemRarity {
  String get wire => name;
  static AuctionItemRarity fromString(String? s) {
    return AuctionItemRarity.values.firstWhere((v) => v.wire == s, orElse: () => AuctionItemRarity.common);
  }
  String get label => name[0].toUpperCase() + name.substring(1);
  int get argb => switch (this) {
    AuctionItemRarity.common => 0xFF94A3B8,
    AuctionItemRarity.rare => 0xFF3B82F6,
    AuctionItemRarity.epic => 0xFF8B5CF6,
    AuctionItemRarity.legendary => 0xFFF59E0B,
    AuctionItemRarity.trap => 0xFFEF4444,
  };
}

enum AuctionItemEffect {
  addCoins,        // +N coins
  doubleCoins,     // double current coins
  tripleCoins,     // triple current coins
  stealCoins,      // steal N from random player
  shield,          // ignore next trap
  multiplier,      // next reward x2
  freeze,          // target player can't bid > 25 next round
  nothing,         // empty crate
  loseCoins,       // -N coins
  bankruptcy,      // lose all coins
  jackpot,         // +100 coins
}

extension AuctionItemEffectX on AuctionItemEffect {
  String get wire => name;
  static AuctionItemEffect fromString(String? s) {
    return AuctionItemEffect.values.firstWhere((v) => v.wire == s, orElse: () => AuctionItemEffect.nothing);
  }
}

class AuctionItem {
  const AuctionItem({
    required this.id,
    required this.name,
    required this.rarity,
    required this.effect,
    this.value = 0,
    this.description = '',
  });
  final String id;
  final String name;
  final AuctionItemRarity rarity;
  final AuctionItemEffect effect;
  final int value;
  final String description;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'rarity': rarity.wire, 'effect': effect.wire, 'value': value, 'desc': description};
  factory AuctionItem.fromJson(Map<String, dynamic> json) => AuctionItem(
    id: (json['id'] ?? '') as String, name: (json['name'] ?? '') as String,
    rarity: AuctionItemRarityX.fromString(json['rarity'] as String?),
    effect: AuctionItemEffectX.fromString(json['effect'] as String?),
    value: (json['value'] as num?)?.toInt() ?? 0,
    description: (json['desc'] ?? '') as String,
  );

  /// The item pool — all possible crate contents.
  static const List<AuctionItem> normalPool = [
    AuctionItem(id: 'i-add10', name: 'Small Stash', rarity: AuctionItemRarity.common, effect: AuctionItemEffect.addCoins, value: 10, description: '+10 coins'),
    AuctionItem(id: 'i-add20', name: 'Coin Pouch', rarity: AuctionItemRarity.common, effect: AuctionItemEffect.addCoins, value: 20, description: '+20 coins'),
    AuctionItem(id: 'i-add30', name: 'Treasure Chest', rarity: AuctionItemRarity.common, effect: AuctionItemEffect.addCoins, value: 30, description: '+30 coins'),
    AuctionItem(id: 'i-add50', name: 'Gold Bar', rarity: AuctionItemRarity.rare, effect: AuctionItemEffect.addCoins, value: 50, description: '+50 coins'),
    AuctionItem(id: 'i-add75', name: 'Diamond', rarity: AuctionItemRarity.rare, effect: AuctionItemEffect.addCoins, value: 75, description: '+75 coins'),
    AuctionItem(id: 'i-double', name: 'Coin Multiplier', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.doubleCoins, description: 'Double your coins'),
    AuctionItem(id: 'i-steal25', name: 'Thief Gloves', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.stealCoins, value: 25, description: 'Steal 25 from a random player'),
    AuctionItem(id: 'i-shield', name: 'Shield', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.shield, description: 'Ignore next trap'),
    AuctionItem(id: 'i-mult', name: 'Lucky Charm', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.multiplier, description: 'Next reward x2'),
    AuctionItem(id: 'i-nothing', name: 'Empty Crate', rarity: AuctionItemRarity.common, effect: AuctionItemEffect.nothing, description: 'Nothing inside'),
    AuctionItem(id: 'i-lose25', name: 'Trap Hole', rarity: AuctionItemRarity.trap, effect: AuctionItemEffect.loseCoins, value: 25, description: '-25 coins'),
    AuctionItem(id: 'i-lose50', name: 'Curse', rarity: AuctionItemRarity.trap, effect: AuctionItemEffect.loseCoins, value: 50, description: '-50 coins'),
    AuctionItem(id: 'i-bankrupt', name: 'Bankruptcy', rarity: AuctionItemRarity.trap, effect: AuctionItemEffect.bankruptcy, description: 'Lose all coins'),
  ];

  static const List<AuctionItem> chaosPool = [
    AuctionItem(id: 'i-add10', name: 'Small Stash', rarity: AuctionItemRarity.common, effect: AuctionItemEffect.addCoins, value: 10, description: '+10 coins'),
    AuctionItem(id: 'i-add50', name: 'Gold Bar', rarity: AuctionItemRarity.rare, effect: AuctionItemEffect.addCoins, value: 50, description: '+50 coins'),
    AuctionItem(id: 'i-double', name: 'Coin Multiplier', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.doubleCoins, description: 'Double your coins'),
    AuctionItem(id: 'i-steal25', name: 'Thief Gloves', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.stealCoins, value: 25, description: 'Steal 25 from a random player'),
    AuctionItem(id: 'i-freeze', name: 'Freeze', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.freeze, description: 'Target player can\'t bid > 25 next round'),
    AuctionItem(id: 'i-nothing', name: 'Empty Crate', rarity: AuctionItemRarity.common, effect: AuctionItemEffect.nothing, description: 'Nothing inside'),
    AuctionItem(id: 'i-lose50', name: 'Curse', rarity: AuctionItemRarity.trap, effect: AuctionItemEffect.loseCoins, value: 50, description: '-50 coins'),
    AuctionItem(id: 'i-bankrupt', name: 'Bankruptcy', rarity: AuctionItemRarity.trap, effect: AuctionItemEffect.bankruptcy, description: 'Lose all coins'),
  ];

  static const List<AuctionItem> legendaryPool = [
    AuctionItem(id: 'i-add50', name: 'Gold Bar', rarity: AuctionItemRarity.rare, effect: AuctionItemEffect.addCoins, value: 50, description: '+50 coins'),
    AuctionItem(id: 'i-add75', name: 'Diamond', rarity: AuctionItemRarity.rare, effect: AuctionItemEffect.addCoins, value: 75, description: '+75 coins'),
    AuctionItem(id: 'i-double', name: 'Coin Multiplier', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.doubleCoins, description: 'Double your coins'),
    AuctionItem(id: 'i-triple', name: 'Triple Threat', rarity: AuctionItemRarity.legendary, effect: AuctionItemEffect.tripleCoins, description: 'Triple your coins'),
    AuctionItem(id: 'i-jackpot', name: 'JACKPOT', rarity: AuctionItemRarity.legendary, effect: AuctionItemEffect.jackpot, value: 100, description: '+100 coins!'),
    AuctionItem(id: 'i-shield', name: 'Shield', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.shield, description: 'Ignore next trap'),
    AuctionItem(id: 'i-mult', name: 'Lucky Charm', rarity: AuctionItemRarity.epic, effect: AuctionItemEffect.multiplier, description: 'Next reward x2'),
  ];

  static List<AuctionItem> poolFor(String poolId) {
    switch (poolId) {
      case 'chaos': return chaosPool;
      case 'legendary': return legendaryPool;
      default: return normalPool;
    }
  }
}

class AuctionBid {
  const AuctionBid({required this.playerIndex, required this.amount, required this.submittedAt});
  final int playerIndex;
  final int amount;
  final DateTime submittedAt;

  Map<String, dynamic> toJson() => {'p': playerIndex, 'amt': amount, 'ts': submittedAt.toIso8601String()};
  factory AuctionBid.fromJson(Map<String, dynamic> json) => AuctionBid(
    playerIndex: (json['p'] as num?)?.toInt() ?? 0,
    amount: (json['amt'] as num?)?.toInt() ?? 0,
    submittedAt: DateTime.tryParse(json['ts'] ?? '') ?? DateTime.now(),
  );
}

class AuctionPlayer {
  AuctionPlayer({required this.playerIndex, required this.userId, required this.userName, this.coins = 100, this.isAlive = true, this.hasShield = false, this.hasMultiplier = false, this.isFrozen = false});
  final int playerIndex;
  final String userId;
  final String userName;
  int coins;
  bool isAlive;
  bool hasShield;
  bool hasMultiplier;
  bool isFrozen;

  Map<String, dynamic> toJson() => {'idx': playerIndex, 'userId': userId, 'name': userName, 'coins': coins, 'alive': isAlive, 'shield': hasShield, 'mult': hasMultiplier, 'frozen': isFrozen};
  factory AuctionPlayer.fromJson(Map<String, dynamic> json) => AuctionPlayer(
    playerIndex: (json['idx'] as num?)?.toInt() ?? 0,
    userId: (json['userId'] ?? '') as String,
    userName: (json['name'] ?? 'Player') as String,
    coins: (json['coins'] as num?)?.toInt() ?? 100,
    isAlive: (json['alive'] as bool?) ?? true,
    hasShield: (json['shield'] as bool?) ?? false,
    hasMultiplier: (json['mult'] as bool?) ?? false,
    isFrozen: (json['frozen'] as bool?) ?? false,
  );
  AuctionPlayer copy() => AuctionPlayer(playerIndex: playerIndex, userId: userId, userName: userName, coins: coins, isAlive: isAlive, hasShield: hasShield, hasMultiplier: hasMultiplier, isFrozen: isFrozen);
}

enum AuctionPhase { bidding, revealing, roundResult, finished }

extension AuctionPhaseX on AuctionPhase {
  String get wire => name;
  static AuctionPhase fromString(String? s) => AuctionPhase.values.firstWhere((v) => v.wire == s, orElse: () => AuctionPhase.bidding);
}

class AuctionRound {
  AuctionRound({required this.roundNumber, required this.item, required this.isFinalRound});
  final int roundNumber;
  AuctionItem item;
  final bool isFinalRound;
  AuctionPhase phase = AuctionPhase.bidding;
  List<AuctionBid> bids = [];
  int? winnerPlayerIndex;
  int winningBid = 0;
  String? effectDescription;

  Map<String, dynamic> toJson() => {'round': roundNumber, 'item': item.toJson(), 'final': isFinalRound, 'phase': phase.wire, 'bids': bids.map((b) => b.toJson()).toList(), 'winner': winnerPlayerIndex ?? -1, 'winBid': winningBid, 'effect': effectDescription};
  factory AuctionRound.fromJson(Map<String, dynamic> json) {
    final round = AuctionRound(
      roundNumber: (json['round'] as num?)?.toInt() ?? 1,
      item: AuctionItem.fromJson(Map<String, dynamic>.from(json['item'] as Map? ?? {})),
      isFinalRound: (json['final'] as bool?) ?? false,
    );
    round.phase = AuctionPhaseX.fromString(json['phase'] as String?);
    final rawBids = json['bids'];
    if (rawBids is List) round.bids = rawBids.whereType<Map>().map((e) => AuctionBid.fromJson(Map<String, dynamic>.from(e))).toList();
    round.winnerPlayerIndex = (json['winner'] as num?)?.toInt();
    if (round.winnerPlayerIndex == -1) round.winnerPlayerIndex = null;
    round.winningBid = (json['winBid'] as num?)?.toInt() ?? 0;
    round.effectDescription = json['effect'] as String?;
    return round;
  }
  AuctionRound copy() {
    final r = AuctionRound(roundNumber: roundNumber, item: item, isFinalRound: isFinalRound);
    r.phase = phase;
    r.bids = List<AuctionBid>.from(bids);
    r.winnerPlayerIndex = winnerPlayerIndex;
    r.winningBid = winningBid;
    r.effectDescription = effectDescription;
    return r;
  }
}

class FreezeAuctionState {
  FreezeAuctionState({required this.playerCount, required this.totalRounds, required this.startingCoins, required this.itemPoolId, required this.currentRoundNumber, required this.rounds, required this.players, required this.status, this.winnerPlayerIndex = -1});
  int playerCount;
  int totalRounds;
  int startingCoins;
  String itemPoolId;
  int currentRoundNumber;
  List<AuctionRound> rounds;
  List<AuctionPlayer> players;
  String status;
  int winnerPlayerIndex;

  AuctionRound? get currentRound => rounds.isNotEmpty && currentRoundNumber <= rounds.length ? rounds[currentRoundNumber - 1] : null;
  bool get isFinished => status == 'completed';

  Map<String, dynamic> toJson() => {'playerCount': playerCount, 'totalRounds': totalRounds, 'startingCoins': startingCoins, 'itemPoolId': itemPoolId, 'currentRound': currentRoundNumber, 'rounds': rounds.map((r) => r.toJson()).toList(), 'players': players.map((p) => p.toJson()).toList(), 'status': status, 'winner': winnerPlayerIndex};
  factory FreezeAuctionState.fromJson(Map<String, dynamic> json) {
    final roundsList = <AuctionRound>[];
    final rawRounds = json['rounds'];
    if (rawRounds is List) for (final r in rawRounds) { if (r is Map) roundsList.add(AuctionRound.fromJson(Map<String, dynamic>.from(r))); }
    final playersList = <AuctionPlayer>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) for (final p in rawPlayers) { if (p is Map) playersList.add(AuctionPlayer.fromJson(Map<String, dynamic>.from(p))); }
    return FreezeAuctionState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 2,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 5,
      startingCoins: (json['startingCoins'] as num?)?.toInt() ?? 100,
      itemPoolId: (json['itemPoolId'] as String?) ?? 'normal',
      currentRoundNumber: (json['currentRound'] as num?)?.toInt() ?? 1,
      rounds: roundsList, players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerPlayerIndex: (json['winner'] as num?)?.toInt() ?? -1,
    );
  }
  FreezeAuctionState copy() => FreezeAuctionState(
    playerCount: playerCount, totalRounds: totalRounds, startingCoins: startingCoins, itemPoolId: itemPoolId,
    currentRoundNumber: currentRoundNumber, rounds: rounds.map((r) => r.copy()).toList(),
    players: players.map((p) => p.copy()).toList(), status: status, winnerPlayerIndex: winnerPlayerIndex,
  );
}

class FreezeAuctionEngine {
  FreezeAuctionEngine._();

  static FreezeAuctionState createMatch({required int playerCount, required int totalRounds, required int startingCoins, required String itemPoolId, required List<(String userId, String userName)> playerInfo, Random? rng}) {
    assert(playerCount >= kFreezeAuctionMinPlayers && playerCount <= kFreezeAuctionMaxPlayers);
    final r = rng ?? Random();
    final players = <AuctionPlayer>[];
    for (var i = 0; i < playerCount; i++) {
      players.add(AuctionPlayer(playerIndex: i, userId: playerInfo[i].$1, userName: playerInfo[i].$2, coins: startingCoins));
    }
    final state = FreezeAuctionState(playerCount: playerCount, totalRounds: totalRounds, startingCoins: startingCoins, itemPoolId: itemPoolId, currentRoundNumber: 1, rounds: [], players: players, status: 'in_progress');
    _startRound(state, r);
    return state;
  }

  static void _startRound(FreezeAuctionState state, Random rng) {
    final isFinal = state.currentRoundNumber >= state.totalRounds;
    final pool = AuctionItem.poolFor(isFinal ? 'legendary' : state.itemPoolId);
    final item = pool[rng.nextInt(pool.length)];
    state.rounds.add(AuctionRound(roundNumber: state.currentRoundNumber, item: item, isFinalRound: isFinal));
  }

  static AuctionItem generateAuctionItem(String itemPoolId, {bool isFinalRound = false, Random? rng}) {
    final r = rng ?? Random();
    final pool = AuctionItem.poolFor(isFinalRound ? 'legendary' : itemPoolId);
    return pool[r.nextInt(pool.length)];
  }

  static String? submitBid(FreezeAuctionState state, int playerIndex, int amount) {
    final round = state.currentRound;
    if (round == null || round.phase != AuctionPhase.bidding) return 'Not in bidding phase';
    final player = state.players.where((p) => p.playerIndex == playerIndex).firstOrNull;
    if (player == null || !player.isAlive) return 'Player not found or eliminated';
    if (round.bids.any((b) => b.playerIndex == playerIndex)) return 'Already bid this round';
    if (amount < 0) return 'Bid must be >= 0';
    if (amount > player.coins) return 'Not enough coins';
    if (player.isFrozen && amount > 25) return 'Frozen — max bid is 25';
    round.bids.add(AuctionBid(playerIndex: playerIndex, amount: amount, submittedAt: DateTime.now()));
    return null;
  }

  static FreezeAuctionState lockBids(FreezeAuctionState state) {
    final round = state.currentRound;
    if (round == null || round.phase != AuctionPhase.bidding) return state;
    final next = state.copy();
    next.currentRound!.phase = AuctionPhase.revealing;
    return _determineWinner(next);
  }

  static FreezeAuctionState _determineWinner(FreezeAuctionState state) {
    final round = state.currentRound;
    if (round == null || round.bids.isEmpty) return state;
    // Highest bid wins. Ties broken by earliest submission.
    final sorted = List<AuctionBid>.from(round.bids)..sort((a, b) {
      final cmp = b.amount.compareTo(a.amount);
      if (cmp != 0) return cmp;
      return a.submittedAt.compareTo(b.submittedAt);
    });
    final winner = sorted.first;
    round.winnerPlayerIndex = winner.playerIndex;
    round.winningBid = winner.amount;
    // Deduct bid from winner
    state.players[winner.playerIndex].coins -= winner.amount;
    return _revealItem(state);
  }

  static FreezeAuctionState _revealItem(FreezeAuctionState state) {
    final round = state.currentRound;
    if (round == null) return state;
    final item = round.item;
    final winnerIdx = round.winnerPlayerIndex;
    if (winnerIdx == null) return state;
    final winner = state.players[winnerIdx];
    var desc = '';

    switch (item.effect) {
      case AuctionItemEffect.addCoins:
        var val = item.value;
        if (winner.hasMultiplier) { val *= 2; winner.hasMultiplier = false; }
        winner.coins += val;
        desc = '+$val coins';
      case AuctionItemEffect.jackpot:
        var val = item.value;
        if (winner.hasMultiplier) { val *= 2; winner.hasMultiplier = false; }
        winner.coins += val;
        desc = 'JACKPOT! +$val coins';
      case AuctionItemEffect.doubleCoins:
        winner.coins *= 2;
        desc = 'Coins doubled!';
      case AuctionItemEffect.tripleCoins:
        winner.coins *= 3;
        desc = 'Coins tripled!';
      case AuctionItemEffect.stealCoins:
        final targets = state.players.where((p) => p.playerIndex != winnerIdx && p.isAlive && p.coins > 0).toList();
        if (targets.isNotEmpty) {
          final target = targets[Random().nextInt(targets.length)];
          final stolen = target.coins < item.value ? target.coins : item.value;
          target.coins -= stolen;
          winner.coins += stolen;
          desc = 'Stole $stolen from ${target.userName}';
        } else { desc = 'No one to steal from'; }
      case AuctionItemEffect.shield:
        winner.hasShield = true;
        desc = 'Shield activated!';
      case AuctionItemEffect.multiplier:
        winner.hasMultiplier = true;
        desc = 'Next reward x2!';
      case AuctionItemEffect.freeze:
        final targets = state.players.where((p) => p.playerIndex != winnerIdx && p.isAlive).toList();
        if (targets.isNotEmpty) {
          final target = targets[Random().nextInt(targets.length)];
          target.isFrozen = true;
          desc = 'Froze ${target.userName} (max 25 next round)';
        } else { desc = 'No one to freeze'; }
      case AuctionItemEffect.nothing:
        desc = 'Empty crate — nothing inside';
      case AuctionItemEffect.loseCoins:
        if (winner.hasShield) { winner.hasShield = false; desc = 'Shield blocked the trap!'; }
        else { winner.coins = (winner.coins - item.value).clamp(0, 999999); desc = '-${item.value} coins'; }
      case AuctionItemEffect.bankruptcy:
        if (winner.hasShield) { winner.hasShield = false; desc = 'Shield blocked bankruptcy!'; }
        else { winner.coins = 0; desc = 'BANKRUPTCY! Lost all coins'; }
    }
    // Check for elimination (0 coins = eliminated)
    if (winner.coins <= 0) { winner.isAlive = false; }
    // Clear freeze for all players at end of round
    for (final p in state.players) { p.isFrozen = false; }
    round.effectDescription = desc;
    round.phase = AuctionPhase.roundResult;
    return state;
  }

  static FreezeAuctionState advanceRound(FreezeAuctionState state, [Random? rng]) {
    final round = state.currentRound;
    if (round == null || round.phase != AuctionPhase.roundResult) return state;
    if (state.currentRoundNumber >= state.totalRounds || state.players.where((p) => p.isAlive).length <= 1) {
      return finishMatch(state);
    }
    final next = state.copy();
    next.currentRoundNumber++;
    _startRound(next, rng ?? Random());
    return next;
  }

  static FreezeAuctionState finishMatch(FreezeAuctionState state) {
    final next = state.copy();
    next.status = 'completed';
    // Winner = highest coins
    final sorted = next.players.toList()..sort((a, b) => b.coins.compareTo(a.coins));
    next.winnerPlayerIndex = sorted.isNotEmpty ? sorted.first.playerIndex : -1;
    if (next.currentRound != null) next.currentRound!.phase = AuctionPhase.finished;
    return next;
  }

  static int getWinner(FreezeAuctionState state) => state.winnerPlayerIndex;
}
