// lib/features/games/retention/coin_models.dart
//
// Models for the shared Family Coins economy.

class CoinBalance {
  const CoinBalance({
    this.balance = 0,
    this.totalEarned = 0,
    this.totalSpent = 0,
    this.familyTreasury = 0,
  });

  final int balance;
  final int totalEarned;
  final int totalSpent;
  final int familyTreasury;

  factory CoinBalance.fromJson(Map<String, dynamic> json) {
    return CoinBalance(
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      totalEarned: (json['totalEarned'] as num?)?.toInt() ?? 0,
      totalSpent: (json['totalSpent'] as num?)?.toInt() ?? 0,
      familyTreasury: (json['familyTreasury'] as num?)?.toInt() ?? 0,
    );
  }
}

class UnlockableReward {
  const UnlockableReward({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.category,
    required this.cost,
    required this.iconEmoji,
    this.isUnlocked = false,
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final String category;
  final int cost;
  final String iconEmoji;
  final bool isUnlocked;

  factory UnlockableReward.fromJson(Map<String, dynamic> json) {
    return UnlockableReward(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      type: (json['type'] ?? '') as String,
      category: (json['category'] ?? 'general') as String,
      cost: (json['cost'] as num?)?.toInt() ?? 100,
      iconEmoji: (json['iconEmoji'] ?? '🎁') as String,
    );
  }

  UnlockableReward copyWith({bool? isUnlocked}) => UnlockableReward(
        id: id,
        name: name,
        description: description,
        type: type,
        category: category,
        cost: cost,
        iconEmoji: iconEmoji,
        isUnlocked: isUnlocked ?? this.isUnlocked,
      );
}

class CoinLedgerEntry {
  const CoinLedgerEntry({
    required this.id,
    required this.amount,
    required this.reason,
    this.referenceId,
    required this.createdAt,
  });

  final String id;
  final int amount;
  final String reason;
  final String? referenceId;
  final DateTime createdAt;

  factory CoinLedgerEntry.fromJson(Map<String, dynamic> json) {
    return CoinLedgerEntry(
      id: (json['id'] ?? '') as String,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      reason: (json['reason'] ?? '') as String,
      referenceId: json['referenceId'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String get reasonLabel {
    switch (reason) {
      case 'match_complete':
        return 'Match completed';
      case 'win_streak':
        return 'Win streak milestone';
      case 'challenge_complete':
        return 'Challenge completed';
      case 'cup_placement':
        return 'Family Cup placement';
      case 'new_game_bonus':
        return 'New game bonus';
      case 'reward_redeem':
        return 'Reward redeemed';
      default:
        return reason;
    }
  }

  bool get isEarn => amount > 0;
}

class CustomContent {
  const CustomContent({
    required this.contentJson,
    required this.isCustom,
    required this.contentId,
  });

  final Map<String, dynamic> contentJson;
  final bool isCustom;
  final String contentId;

  factory CustomContent.fromJson(Map<String, dynamic> json) {
    return CustomContent(
      contentJson: json['contentJson'] is Map
          ? Map<String, dynamic>.from(json['contentJson'] as Map)
          : const {},
      isCustom: (json['isCustom'] as bool?) ?? false,
      contentId: (json['contentId'] ?? '') as String,
    );
  }
}

class SeasonalTheme {
  const SeasonalTheme({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.accentColor,
    required this.coinMultiplier,
    required this.iconEmoji,
    this.bannerAssetUrl,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String accentColor;
  final String? bannerAssetUrl;
  final double coinMultiplier;
  final String iconEmoji;

  bool get isActive =>
      DateTime.now().isAfter(startDate) && DateTime.now().isBefore(endDate);

  factory SeasonalTheme.fromJson(Map<String, dynamic> json) {
    return SeasonalTheme(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      startDate: DateTime.tryParse(json['startDate'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['endDate'] ?? '') ?? DateTime.now(),
      accentColor: (json['accentColor'] ?? '#E8612A') as String,
      bannerAssetUrl: json['bannerAssetUrl'] as String?,
      coinMultiplier: (json['coinMultiplier'] as num?)?.toDouble() ?? 1.0,
      iconEmoji: (json['iconEmoji'] ?? '🎉') as String,
    );
  }

  /// Parse the hex accent color string (#F59E0B) into a Flutter Color.
  /// Returns null if the string is invalid.
  int get accentColorValue {
    final hex = accentColor.replaceFirst('#', '');
    if (hex.length == 6) {
      return int.parse('FF$hex', radix: 16);
    }
    return 0xFFE8612A; // default Kinrel orange
  }
}
