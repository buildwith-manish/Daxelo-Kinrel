// lib/features/prediction_battle_v1/pb_v1_coin_models.dart
//
// Data models for the coin economy Flutter UI. Maps the JSON shape
// returned by the `fn_get_coin_balance` and `fn_get_coin_history`
// Supabase RPCs.
//
// The coin economy has two RPCs the Flutter client cares about:
//   - fn_get_coin_balance → returns { ok, balance, lifetimeEarned,
//     updatedAt }
//   - fn_get_coin_history → returns { ok, rows: [...] } where each
//     row is a CoinHistoryEntry (amount, reason, metadata,
//     createdAt).
//
// All models support toJson/fromJson so the coin provider can cache
// the response via LocalCacheService (mirroring the cache-first
// pattern used by pb_v1_provider and pb_v1_history_provider).

/// The user's coin balance for a family. Returned by
/// `fn_get_coin_balance`. The `lifetimeEarned` field is the sum of
/// all positive amounts ever credited (spends don't reduce it) —
/// useful as a "you've earned X total" stat on the history screen.
class PBv1CoinBalance {
  const PBv1CoinBalance({
    required this.balance,
    required this.lifetimeEarned,
    this.updatedAt,
  });

  final int balance;
  final int lifetimeEarned;
  final DateTime? updatedAt;

  factory PBv1CoinBalance.fromJson(Map<String, dynamic> json) => PBv1CoinBalance(
    balance: (json['balance'] ?? 0) as int,
    lifetimeEarned: (json['lifetimeEarned'] ?? json['lifetime_earned'] ?? 0) as int,
    updatedAt: DateTime.tryParse((json['updatedAt'] ?? json['updated_at'] ?? '').toString()),
  );

  Map<String, dynamic> toJson() => {
    'balance': balance,
    'lifetime_earned': lifetimeEarned,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  static const empty = PBv1CoinBalance(balance: 0, lifetimeEarned: 0);
}

/// A single entry in the coin ledger (one credit or one spend).
/// Returned by `fn_get_coin_history` as part of the `rows` array.
class PBv1CoinHistoryEntry {
  const PBv1CoinHistoryEntry({
    required this.id,
    required this.amount,
    required this.reason,
    required this.metadata,
    required this.createdAt,
  });

  final String id;
  final int amount;             // can be negative for spends
  final String reason;          // 'prediction_winner' | 'prediction_streak_bonus' | 'prediction_close_guess' | 'prediction_participation' | future
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  factory PBv1CoinHistoryEntry.fromJson(Map<String, dynamic> json) => PBv1CoinHistoryEntry(
    id: (json['id'] ?? '') as String,
    amount: (json['amount'] ?? 0) as int,
    reason: (json['reason'] ?? '') as String,
    metadata: json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : <String, dynamic>{},
    createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at'] ?? '').toString()) ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'reason': reason,
    'metadata': metadata,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  /// True iff this is a credit (positive amount). Spends (amount < 0)
  /// are not currently awarded by the prediction module but are
  /// allowed by the schema for future "spend coins on X" features.
  bool get isCredit => amount > 0;

  /// Returns the round_id from metadata, or null if the award wasn't
  /// tied to a specific round (e.g., a future "daily login bonus"
  /// wouldn't have one).
  String? get roundId => metadata['round_id'] is String ? metadata['round_id'] as String : null;

  /// Returns a human-readable label for the reason. Mirrors the labels
  /// used by the coin history screen's per-entry icon + copy.
  String get reasonLabel {
    switch (reason) {
      case 'prediction_winner':
        return 'Prediction winner';
      case 'prediction_streak_bonus':
        return 'Streak bonus';
      case 'prediction_close_guess':
        return 'Close guess';
      case 'prediction_participation':
        return 'Participation';
      default:
        return reason;
    }
  }
}

/// The full state returned by the coin history RPC. Wraps the
/// paginated rows array with the balance (so the screen can render
/// the balance header + history list in one pass).
class PBv1CoinHistory {
  const PBv1CoinHistory({
    required this.balance,
    required this.rows,
    required this.cachedAt,
  });

  final PBv1CoinBalance balance;
  final List<PBv1CoinHistoryEntry> rows;
  final String cachedAt;

  factory PBv1CoinHistory.fromJson(Map<String, dynamic> json) => PBv1CoinHistory(
    balance: json['balance'] is Map
        ? PBv1CoinBalance.fromJson(Map<String, dynamic>.from(json['balance'] as Map))
        : PBv1CoinBalance.empty,
    rows: (json['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => PBv1CoinHistoryEntry.fromJson(Map<String, dynamic>.from(r)))
        .toList(),
    cachedAt: (json['cachedAt'] ?? '') as String,
  );

  Map<String, dynamic> toJson() => {
    'balance': balance.toJson(),
    'rows': rows.map((r) => r.toJson()).toList(),
    'cachedAt': cachedAt,
  };
}
