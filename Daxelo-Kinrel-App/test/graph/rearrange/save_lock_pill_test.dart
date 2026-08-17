// test/graph/rearrange/save_lock_pill_test.dart
//
// v5.22 PART 3 — Shared Save/Lock inline confirmation pill tests.
//
// Verifies the shared pill widget used by both PART 1 (node drag) and
// PART 2 (edge midpoint bow) provides Save / Cancel buttons that
// invoke the right callbacks, AND that the auto-dismiss timeout
// defaults to Cancel/revert (so unconfirmed changes never silently
// persist).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rearrange/save_lock_pill.dart';

void main() {
  group('SaveLockPill', () {
    testWidgets('renders Save and Cancel buttons with the given message',
        (tester) async {
      bool? saved;
      bool? cancelled;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Stack(
              children: [
                SaveLockPill(
                  message: 'Save this position?',
                  onSave: () => saved = true,
                  onCancel: () => cancelled = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Save this position?'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(saved, isNull);
      expect(cancelled, isNull);
    });

    testWidgets('Save button invokes onSave and closes the pill',
        (tester) async {
      int saves = 0;
      int cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SaveLockPill(
              message: 'Save this curve?',
              onSave: () => saves++,
              onCancel: () => cancels++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saves, 1);
      expect(cancels, 0);
    });

    testWidgets('Cancel button invokes onCancel', (tester) async {
      int saves = 0;
      int cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SaveLockPill(
              message: 'Save this position?',
              onSave: () => saves++,
              onCancel: () => cancels++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(saves, 0);
      expect(cancels, 1);
    });

    testWidgets('auto-dismiss defaults to Cancel (revert) so unconfirmed '
        'changes never silently persist', (tester) async {
      int saves = 0;
      int cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SaveLockPill(
              message: 'Save this position?',
              onSave: () => saves++,
              onCancel: () => cancels++,
              // Use a short timeout to keep the test fast.
              autoDismissSeconds: 1,
            ),
          ),
        ),
      );

      // Wait for the auto-dismiss timer to fire (1 second + pump buffer).
      await tester.pump(const Duration(seconds: 1, milliseconds: 50));
      expect(saves, 0,
          reason: 'auto-dismiss must NOT default to Save');
      expect(cancels, 1,
          reason: 'auto-dismiss must default to Cancel (revert)');
    });
  });
}
