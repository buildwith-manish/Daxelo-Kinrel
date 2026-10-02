// test/features/prediction_battle_v1/pb_v1_coin_models_test.dart
//
// Unit tests for the coin economy models. Verifies fromJson/toJson
// round-trips preserve all fields, including:
//   - balance + lifetimeEarned parsing (camelCase + snake_case)
//   - history entry with metadata (round_id, question_id, etc.)
//   - negative amounts (spends — not yet used by the prediction
//     module but allowed by the schema)
//   - reasonLabel mapping (human-readable label per reason)
//   - isCredit + roundId getters

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/prediction_battle_v1/pb_v1_coin_models.dart';

void main() {
  group('PBv1CoinBalance', () {
    test('fromJson accepts camelCase keys', () {
      final b = PBv1CoinBalance.fromJson({
        'balance': 42,
        'lifetimeEarned': 100,
        'updatedAt': '2026-09-23T16:00:00.000Z',
      });
      expect(b.balance, 42);
      expect(b.lifetimeEarned, 100);
      expect(b.updatedAt, isNotNull);
    });

    test('fromJson accepts snake_case keys (from the RPC)', () {
      final b = PBv1CoinBalance.fromJson({
        'balance': 7,
        'lifetime_earned': 50,
        'updated_at': '2026-09-23T16:00:00.000Z',
      });
      expect(b.balance, 7);
      expect(b.lifetimeEarned, 50);
    });

    test('fromJson defaults to zeros when fields missing', () {
      final b = PBv1CoinBalance.fromJson({});
      expect(b.balance, 0);
      expect(b.lifetimeEarned, 0);
      expect(b.updatedAt, isNull);
    });

    test('empty constant equals a zero-balance streak', () {
      expect(PBv1CoinBalance.empty.balance, 0);
      expect(PBv1CoinBalance.empty.lifetimeEarned, 0);
    });

    test('toJson round-trips through fromJson', () {
      final original = PBv1CoinBalance(
        balance: 42,
        lifetimeEarned: 100,
        updatedAt: DateTime.utc(2026, 9, 23, 16, 0),
      );
      final back = PBv1CoinBalance.fromJson(original.toJson());
      expect(back.balance, 42);
      expect(back.lifetimeEarned, 100);
      expect(back.updatedAt?.toUtc(), original.updatedAt!.toUtc());
    });
  });

  group('PBv1CoinHistoryEntry', () {
    test('fromJson parses all fields correctly', () {
      final e = PBv1CoinHistoryEntry.fromJson({
        'id': 'ledger-1',
        'amount': 10,
        'reason': 'prediction_winner',
        'metadata': {
          'round_id': 'round-abc',
          'question_id': 'pq-001',
          'guess_value': 42,
          'correct_answer': 42,
          'distance': 0,
        },
        'createdAt': '2026-09-23T15:30:00.000Z',
      });
      expect(e.id, 'ledger-1');
      expect(e.amount, 10);
      expect(e.reason, 'prediction_winner');
      expect(e.metadata['round_id'], 'round-abc');
      expect(e.metadata['question_id'], 'pq-001');
      expect(e.createdAt, DateTime.utc(2026, 9, 23, 15, 30));
    });

    test('fromJson accepts snake_case createdAt', () {
      final e = PBv1CoinHistoryEntry.fromJson({
        'id': 'l-2',
        'amount': -5,
        'reason': 'spend',
        'metadata': <String, dynamic>{},
        'created_at': '2026-09-23T15:30:00.000Z',
      });
      expect(e.amount, -5);
      expect(e.createdAt, DateTime.utc(2026, 9, 23, 15, 30));
    });

    test('fromJson handles missing metadata as empty map', () {
      final e = PBv1CoinHistoryEntry.fromJson({
        'id': 'l-3',
        'amount': 2,
        'reason': 'prediction_close_guess',
      });
      expect(e.metadata, isEmpty);
    });

    test('isCredit returns true for positive amounts', () {
      final e = PBv1CoinHistoryEntry(
        id: 'l-4',
        amount: 10,
        reason: 'prediction_winner',
        metadata: const {},
        createdAt: DateTime.utc(2026, 9, 23),
      );
      expect(e.isCredit, isTrue);
    });

    test('isCredit returns false for negative amounts (spends)', () {
      final e = PBv1CoinHistoryEntry(
        id: 'l-5',
        amount: -5,
        reason: 'spend',
        metadata: const {},
        createdAt: DateTime.utc(2026, 9, 23),
      );
      expect(e.isCredit, isFalse);
    });

    test('roundId returns the metadata round_id when present', () {
      final e = PBv1CoinHistoryEntry(
        id: 'l-6',
        amount: 10,
        reason: 'prediction_winner',
        metadata: const {'round_id': 'round-xyz'},
        createdAt: DateTime.utc(2026, 9, 23),
      );
      expect(e.roundId, 'round-xyz');
    });

    test('roundId returns null when metadata has no round_id', () {
      final e = PBv1CoinHistoryEntry(
        id: 'l-7',
        amount: 5,
        reason: 'daily_login_bonus',
        metadata: const {},
        createdAt: DateTime.utc(2026, 9, 23),
      );
      expect(e.roundId, isNull);
    });

    test('reasonLabel returns human-readable labels for known reasons', () {
      final cases = {
        'prediction_winner': 'Prediction winner',
        'prediction_streak_bonus': 'Streak bonus',
        'prediction_close_guess': 'Close guess',
        'prediction_participation': 'Participation',
      };
      for (final entry in cases.entries) {
        final e = PBv1CoinHistoryEntry(
          id: 'l-x',
          amount: 1,
          reason: entry.key,
          metadata: const {},
          createdAt: DateTime.utc(2026, 9, 23),
        );
        expect(e.reasonLabel, entry.value, reason: 'reason: ${entry.key}');
      }
    });

    test('reasonLabel returns the raw reason for unknown reasons', () {
      final e = PBv1CoinHistoryEntry(
        id: 'l-y',
        amount: 5,
        reason: 'daily_login_bonus',
        metadata: const {},
        createdAt: DateTime.utc(2026, 9, 23),
      );
      expect(e.reasonLabel, 'daily_login_bonus');
    });

    test('toJson round-trips through fromJson', () {
      final original = PBv1CoinHistoryEntry(
        id: 'l-z',
        amount: 10,
        reason: 'prediction_winner',
        metadata: const {'round_id': 'r-1', 'question_id': 'pq-001'},
        createdAt: DateTime.utc(2026, 9, 23, 15, 30),
      );
      final back = PBv1CoinHistoryEntry.fromJson(original.toJson());
      expect(back.id, 'l-z');
      expect(back.amount, 10);
      expect(back.reason, 'prediction_winner');
      expect(back.metadata['round_id'], 'r-1');
      expect(back.metadata['question_id'], 'pq-001');
      expect(back.createdAt.toUtc(), original.createdAt.toUtc());
    });
  });

  group('PBv1CoinHistory', () {
    test('parses full RPC response shape', () {
      final json = {
        'ok': true,
        'balance': {
          'balance': 42,
          'lifetimeEarned': 100,
          'updatedAt': '2026-09-23T16:00:00.000Z',
        },
        'rows': [
          {
            'id': 'l-1',
            'amount': 10,
            'reason': 'prediction_winner',
            'metadata': {'round_id': 'r-1'},
            'createdAt': '2026-09-23T15:30:00.000Z',
          },
          {
            'id': 'l-2',
            'amount': 5,
            'reason': 'prediction_streak_bonus',
            'metadata': {'round_id': 'r-1', 'streak': 3},
            'createdAt': '2026-09-23T15:30:00.000Z',
          },
          {
            'id': 'l-3',
            'amount': 2,
            'reason': 'prediction_close_guess',
            'metadata': {'round_id': 'r-2'},
            'createdAt': '2026-09-22T15:30:00.000Z',
          },
        ],
        'cachedAt': '2026-09-23T16:00:00.000Z',
      };
      final h = PBv1CoinHistory.fromJson(json);
      expect(h.balance.balance, 42);
      expect(h.balance.lifetimeEarned, 100);
      expect(h.rows.length, 3);
      expect(h.rows[0].amount, 10);
      expect(h.rows[0].reason, 'prediction_winner');
      expect(h.rows[1].amount, 5);
      expect(h.rows[1].reason, 'prediction_streak_bonus');
      expect(h.rows[2].amount, 2);
    });

    test('handles empty rows array', () {
      final json = {
        'ok': true,
        'balance': {'balance': 0, 'lifetimeEarned': 0},
        'rows': <Map<String, dynamic>>[],
        'cachedAt': '',
      };
      final h = PBv1CoinHistory.fromJson(json);
      expect(h.rows, isEmpty);
      expect(h.balance.balance, 0);
    });

    test('handles missing balance field (defaults to empty)', () {
      final json = {
        'ok': true,
        'rows': <Map<String, dynamic>>[],
        'cachedAt': '',
      };
      final h = PBv1CoinHistory.fromJson(json);
      expect(h.balance.balance, 0);
      expect(h.balance.lifetimeEarned, 0);
    });

    test('survives toJson → fromJson round-trip', () {
      final original = PBv1CoinHistory(
        balance: const PBv1CoinBalance(balance: 42, lifetimeEarned: 100),
        rows: [
          PBv1CoinHistoryEntry(
            id: 'l-1',
            amount: 10,
            reason: 'prediction_winner',
            metadata: const {'round_id': 'r-1'},
            createdAt: DateTime.utc(2026, 9, 23, 15, 30),
          ),
        ],
        cachedAt: '2026-09-23T16:00:00.000Z',
      );
      final back = PBv1CoinHistory.fromJson(original.toJson());
      expect(back.balance.balance, 42);
      expect(back.balance.lifetimeEarned, 100);
      expect(back.rows.length, 1);
      expect(back.rows[0].id, 'l-1');
      expect(back.rows[0].amount, 10);
      expect(back.cachedAt, '2026-09-23T16:00:00.000Z');
    });
  });
}
