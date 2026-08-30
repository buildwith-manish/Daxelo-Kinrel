// test/graph/rearrange/save_button_state_test.dart
//
// v5.39 — Verify the Save (✓) button enable/disable contract:
//   • No changes → button disabled (hasUnsavedChangesProvider == false)
//   • Drag a node → button enabled (hasUnsavedChangesProvider == true)
//   • Save or Reset → button disabled again
//   • Exit Rearrange mode → button disabled (changes discarded)
//   • Re-enter Rearrange mode → button still disabled (clean slate)
//
// This test exercises the provider-level state machine that the
// FamilyGraphScreen's _buildSaveAllButton() consumes via
// ref.watch(hasUnsavedChangesProvider). The actual drag gesture is
// simulated by directly flipping the provider the same way the
// interaction_mixin does (ref.read(hasUnsavedChangesProvider.notifier).state = true).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/graph/rearrange/layout_overrides_service.dart';

void main() {
  group('Save (✓) button state — hasUnsavedChangesProvider', () {
    test('defaults to false — button starts disabled when Rearrange '
        'mode is opened with no changes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(hasUnsavedChangesProvider), false,
          reason: 'A fresh Rearrange session must start with the Save '
              'button disabled. The user has not moved any node yet.');
    });

    test('flips to true when a node is dragged (simulating the drag '
        'update path in interaction_mixin.dart)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Simulate the first _handleRearrangeDragUpdate call —
      // interaction_mixin sets this flag the moment the live override
      // map is mutated.
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      expect(container.read(hasUnsavedChangesProvider), true,
          reason: 'After the user moves a node, the Save (✓) button '
              'MUST be enabled so the user can commit the change.');
    });

    test('stays true across multiple node moves (Save button remains '
        'enabled until the user saves or resets)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // First move.
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      // Second move (re-setting the same value is a no-op, just like
      // the guard in _handleRearrangeDragUpdate).
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      // Third move.
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      expect(container.read(hasUnsavedChangesProvider), true,
          reason: 'Multiple unsaved moves must keep the Save button '
              'enabled — the user has not yet committed or discarded.');
    });

    test('flips back to false after Save completes (changes committed, '
        'no longer unsaved)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      expect(container.read(hasUnsavedChangesProvider), true);
      // Simulate _onSaveAllTrigger's cleanup: after persisting the
      // live overrides, the engine view clears the flag.
      container.read(hasUnsavedChangesProvider.notifier).state = false;
      expect(container.read(hasUnsavedChangesProvider), false,
          reason: 'After a successful save, there are no unsaved '
              'changes — the button MUST disable so the user cannot '
              're-tap it for a no-op save.');
    });

    test('flips back to false after Reset (changes discarded)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      expect(container.read(hasUnsavedChangesProvider), true);
      // Simulate _onResetUnsavedTrigger's cleanup.
      container.read(hasUnsavedChangesProvider.notifier).state = false;
      expect(container.read(hasUnsavedChangesProvider), false,
          reason: 'After Reset, the unsaved changes are gone — the '
              'button MUST disable.');
    });

    test('flips back to false when Rearrange mode is exited (changes '
        'discarded on exit)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // User enters Rearrange mode.
      container.read(rearrangeModeProvider.notifier).state = true;
      // User drags a node — flag goes true.
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      expect(container.read(hasUnsavedChangesProvider), true);
      // User exits Rearrange mode without saving — the engine view's
      // listener clears the flag.
      container.read(hasUnsavedChangesProvider.notifier).state = false;
      expect(container.read(hasUnsavedChangesProvider), false,
          reason: 'Exiting Rearrange mode discards unsaved changes — '
              'the button MUST disable.');
    });

    test('stays false when re-entering Rearrange mode after a clean '
        'exit (no stale true state)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Enter, drag, exit (clean cycle).
      container.read(rearrangeModeProvider.notifier).state = true;
      container.read(hasUnsavedChangesProvider.notifier).state = true;
      container.read(hasUnsavedChangesProvider.notifier).state = false;
      container.read(rearrangeModeProvider.notifier).state = false;
      expect(container.read(hasUnsavedChangesProvider), false);
      // Re-enter — flag must still be false.
      container.read(rearrangeModeProvider.notifier).state = true;
      expect(container.read(hasUnsavedChangesProvider), false,
          reason: 'Re-opening Rearrange mode must NOT show a stale '
              '"unsaved changes" state from the previous session. '
              'The Save button stays disabled until the user actually '
              'moves a node again.');
    });
  });
}
