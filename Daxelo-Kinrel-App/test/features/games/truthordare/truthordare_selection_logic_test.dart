// test/features/games/truthordare/truthordare_selection_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/truthordare/truthordare_selection_logic.dart';
import 'dart:math' as math;

void main() {
  group('selectPlayer — spinner never selected', () {
    test('never returns the spinner ID', () {
      final players = [
        ('userId': 'p1', 'timesSelected': 0),
        ('userId': 'p2', 'timesSelected': 0),
        ('userId': 'p3', 'timesSelected': 0),
        ('userId': 'p4', 'timesSelected': 0),
      ].map((m) => (userId: m['userId'] as String, timesSelected: m['timesSelected'] as int)).toList();

      // Run 100 times, never select spinner
      final rng = math.Random(42);
      for (int i = 0; i < 100; i++) {
        final selected = selectPlayer(players: players, spinnerId: 'p1', random: rng);
        expect(selected, isNot('p1'), reason: 'Spinner should never be selected');
        expect(selected, isNotNull);
      }
    });

    test('returns null if only one player (the spinner)', () {
      final result = selectPlayer(players: [(userId: 'p1', timesSelected: 0)], spinnerId: 'p1');
      expect(result, isNull);
    });
  });

  group('selectPlayer — anti-repeat weighting', () {
    test('player with more selections is picked less often', () {
      final players = [
        (userId: 'p1', timesSelected: 10), // selected many times
        (userId: 'p2', timesSelected: 0),  // never selected
        (userId: 'p3', timesSelected: 0),
        (userId: 'p4', timesSelected: 0),
      ];

      final rng = math.Random(42);
      int p1Count = 0, p2Count = 0;
      for (int i = 0; i < 1000; i++) {
        final selected = selectPlayer(players: players, spinnerId: 'p4', random: rng); // p4 is spinner
        if (selected == 'p1') p1Count++;
        if (selected == 'p2') p2Count++;
      }
      // p2 (0 selections) should be picked significantly more than p1 (10 selections)
      expect(p2Count > p1Count, true, reason: 'Player with fewer selections should be picked more often');
    });
  });

  group('selectPrompt — only approved prompts served', () {
    test('returns a prompt from the provided list', () {
      final promptIds = ['prompt1', 'prompt2', 'prompt3'];
      final rng = math.Random(42);
      final result = selectPrompt(promptIds: promptIds, usedPromptIds: {}, random: rng);
      expect(promptIds.contains(result), true);
    });

    test('avoids used prompts when available', () {
      final promptIds = ['p1', 'p2', 'p3'];
      final used = {'p1', 'p2'};
      final rng = math.Random(42);
      // Run multiple times — should only return p3 (the only unused)
      for (int i = 0; i < 20; i++) {
        final result = selectPrompt(promptIds: promptIds, usedPromptIds: used, random: rng);
        expect(result, 'p3', reason: 'Should only return unused prompt');
      }
    });

    test('resets pool when all prompts used', () {
      final promptIds = ['p1', 'p2'];
      final used = {'p1', 'p2'}; // all used
      final rng = math.Random(42);
      final result = selectPrompt(promptIds: promptIds, usedPromptIds: used, random: rng);
      expect(promptIds.contains(result), true, reason: 'Should return any prompt when pool exhausted');
    });

    test('returns null for empty prompt list', () {
      final result = selectPrompt(promptIds: [], usedPromptIds: {});
      expect(result, isNull);
    });
  });

  group('flagPrompt — profanity filter', () {
    test('flags prompt with bad word', () {
      expect(flagPrompt('What the fuck is this'), true);
      expect(flagPrompt('You are a shit person'), true);
    });

    test('does not flag clean prompt', () {
      expect(flagPrompt('What is your favorite color?'), false);
      expect(flagPrompt('Sing a song for the group'), false);
    });

    test('case-insensitive', () {
      expect(flagPrompt('WHAT THE FUCK'), true);
      expect(flagPrompt('Shit'), true);
    });
  });
}
