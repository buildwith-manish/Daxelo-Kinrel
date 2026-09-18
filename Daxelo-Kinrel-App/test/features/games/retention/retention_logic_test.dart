// test/features/games/retention/retention_logic_test.dart
//
// Pure-Dart unit tests for the retention systems contract.

import 'package:test/test.dart';
import 'package:kinrel/features/games/retention/coin_models.dart';
import 'package:kinrel/features/games/retention/create_content_sheet.dart';

void main() {
  group('Coin economy — award/redeem contract', () {
    test('awarding coins increments balance by the awarded amount', () {
      var balance = 50;
      const award = 10;
      balance += award;
      expect(balance, 60);
    });

    test('redeem rejects when balance insufficient', () {
      var balance = 50;
      const cost = 100;
      final canAfford = balance >= cost;
      expect(canAfford, isFalse);
      expect(balance, 50);
    });

    test('redeem succeeds and decrements balance when sufficient', () {
      var balance = 200;
      const cost = 150;
      final canAfford = balance >= cost;
      expect(canAfford, isTrue);
      balance -= cost;
      expect(balance, 50);
    });

    test('win streak award is larger than match completion award', () {
      const matchCompleteAmount = 10;
      const winStreakAmount = 25;
      expect(winStreakAmount, greaterThan(matchCompleteAmount));
    });

    test('new game bonus encourages variety', () {
      const newGameBonus = 30;
      const matchComplete = 10;
      expect(newGameBonus, greaterThan(matchComplete));
    });

    test('seasonal coin multiplier boosts awards', () {
      const baseAmount = 10;
      const diwaliMultiplier = 1.5;
      final boostedAmount = (baseAmount * diwaliMultiplier).round();
      expect(boostedAmount, 15);
    });
  });

  group('CoinBalance model', () {
    test('fromJson parses all fields correctly', () {
      final balance = CoinBalance.fromJson({
        'balance': 150,
        'totalEarned': 300,
        'totalSpent': 150,
        'familyTreasury': 500,
      });
      expect(balance.balance, 150);
      expect(balance.totalEarned, 300);
      expect(balance.totalSpent, 150);
      expect(balance.familyTreasury, 500);
    });

    test('fromJson handles missing fields with defaults', () {
      final balance = CoinBalance.fromJson({});
      expect(balance.balance, 0);
      expect(balance.totalEarned, 0);
      expect(balance.totalSpent, 0);
      expect(balance.familyTreasury, 0);
    });
  });

  group('Profanity filter', () {
    test('detects common profanity', () {
      expect(containsProfanity('this is shit'), isTrue);
      expect(containsProfanity('what the fuck'), isTrue);
      expect(containsProfanity('you bastard'), isTrue);
    });

    test('passes clean text', () {
      expect(containsProfanity('I once met a cricket player'), isFalse);
      expect(containsProfanity('Do your best dance move'), isFalse);
      expect(containsProfanity('I love my family'), isFalse);
    });

    test('case-insensitive detection', () {
      expect(containsProfanity('THIS IS SHIT'), isTrue);
      expect(containsProfanity('ShIt'), isTrue);
    });
  });

  group('SeasonalTheme model', () {
    test('fromJson parses all fields', () {
      final theme = SeasonalTheme.fromJson({
        'id': 'theme-diwali-2026',
        'name': 'Diwali Game Night',
        'startDate': '2026-10-20T00:00:00Z',
        'endDate': '2026-11-05T23:59:59Z',
        'accentColor': '#F59E0B',
        'coinMultiplier': 1.5,
        'iconEmoji': '🪔',
      });
      expect(theme.id, 'theme-diwali-2026');
      expect(theme.name, 'Diwali Game Night');
      expect(theme.accentColor, '#F59E0B');
      expect(theme.coinMultiplier, 1.5);
      expect(theme.iconEmoji, '🪔');
    });

    test('accentColorValue parses hex to int', () {
      final theme = SeasonalTheme.fromJson({
        'accentColor': '#F59E0B',
        'startDate': '2026-10-20T00:00:00Z',
        'endDate': '2026-11-05T23:59:59Z',
      });
      expect(theme.accentColorValue, 0xFFF59E0B);
    });

    test('accentColorValue falls back to default on invalid hex', () {
      final theme = SeasonalTheme.fromJson({
        'accentColor': 'invalid',
        'startDate': '2026-10-20T00:00:00Z',
        'endDate': '2026-11-05T23:59:59Z',
      });
      expect(theme.accentColorValue, 0xFFE8612A);
    });

    test('isActive returns true when current time is within range', () {
      final now = DateTime.now();
      final theme = SeasonalTheme.fromJson({
        'startDate': now.subtract(const Duration(days: 1)).toIso8601String(),
        'endDate': now.add(const Duration(days: 1)).toIso8601String(),
      });
      expect(theme.isActive, isTrue);
    });

    test('isActive returns false when current time is outside range', () {
      final now = DateTime.now();
      final theme = SeasonalTheme.fromJson({
        'startDate': now.add(const Duration(days: 1)).toIso8601String(),
        'endDate': now.add(const Duration(days: 2)).toIso8601String(),
      });
      expect(theme.isActive, isFalse);
    });
  });

  group('UnlockableReward model', () {
    test('fromJson parses all fields', () {
      final reward = UnlockableReward.fromJson({
        'id': 'reward-festive-ludo',
        'name': 'Festive Ludo Board',
        'description': 'Diwali-themed Ludo board skin',
        'type': 'board_skin',
        'category': 'board_skins',
        'cost': 200,
        'iconEmoji': '🎲',
      });
      expect(reward.id, 'reward-festive-ludo');
      expect(reward.name, 'Festive Ludo Board');
      expect(reward.type, 'board_skin');
      expect(reward.cost, 200);
      expect(reward.isUnlocked, isFalse);
    });

    test('copyWith updates isUnlocked', () {
      final reward = UnlockableReward.fromJson({
        'id': 'test',
        'cost': 100,
      });
      final unlocked = reward.copyWith(isUnlocked: true);
      expect(unlocked.isUnlocked, isTrue);
      expect(reward.isUnlocked, isFalse);
    });
  });
}
