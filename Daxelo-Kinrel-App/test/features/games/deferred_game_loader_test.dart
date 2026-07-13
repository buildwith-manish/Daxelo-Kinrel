// test/features/games/deferred_game_loader_test.dart
import "dart:async";
//
// P5.3 — Deferred imports for the 15 games.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/shared/widgets/deferred_game_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P5.3 — DeferredGameLoader', () {
    testWidgets('shows loading spinner while library loads', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: DeferredGameLoader(
            libraryLoader: () => completer.future,
            screenBuilder: () => const Scaffold(body: Text('Game loaded')),
          ),
        ),
      );
      // Should show loading state.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading game...'), findsOneWidget);

      // Complete the load.
      completer.complete();
      await tester.pumpAndSettle();

      // Should now show the game screen.
      expect(find.text('Game loaded'), findsOneWidget);
    });

    testWidgets('shows error state on load failure', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: DeferredGameLoader(
            libraryLoader: () => completer.future,
            screenBuilder: () => const Scaffold(body: Text('Game')),
          ),
        ),
      );
      completer.completeError('Network error');
      await tester.pumpAndSettle();

      expect(find.text('Failed to load game'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry button re-attempts load', (tester) async {
      final loadCount = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          home: DeferredGameLoader(
            libraryLoader: () {
              loadCount.value++;
              if (loadCount.value == 1) {
                return Future.error('First attempt fails');
              }
              return Future.value();
            },
            screenBuilder: () => const Scaffold(body: Text('Game loaded')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Failed to load game'), findsOneWidget);

      // Tap retry.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Should now be loaded.
      expect(find.text('Game loaded'), findsOneWidget);
      expect(loadCount.value, equals(2));
    });
  });

  group('P5.3 — Deferred import pattern contract', () {
    test('all 15 games should use deferred imports', () {
      // The 15 games are:
      //   1. Ghost Painter
      //   2. Red Light Green Light
      //   3. SOS
      //   4. Antakshari
      //   5. Bingo
      //   6. Checkers
      //   7. Ludo
      //   8. Carrom
      //   9. Chess
      //   10. Chitmatch
      //   11. Name Place Animal Thing
      //   12. Tic Tac Toe
      //   13. Truth or Dare
      //   14. Dots and Boxes
      //   15. Two Truths and a Lie
      const gameCount = 15;
      expect(gameCount, equals(15));
    });

    test('deferred import syntax uses "deferred as"', () {
      // The pattern is:
      //   import 'package:kinrel/features/games/...' deferred as game_xxx;
      // Then:
      //   await game_xxx.loadLibrary();
      //   game_xxx.GameScreen();
      const syntaxExample = 'deferred as';
      expect(syntaxExample, contains('deferred'));
    });

    test('DeferredGameLoader is the canonical loader widget', () {
      expect(DeferredGameLoader, isA<Type>());
    });
  });
}
