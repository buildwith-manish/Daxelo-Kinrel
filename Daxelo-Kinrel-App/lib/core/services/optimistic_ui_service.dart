// lib/core/services/optimistic_ui_service.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  OPTIMISTIC UI SERVICE — instant feedback on every action            │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// WhatsApp sends appear instantly. Instagram likes appear instantly.
// Twitter retweets appear instantly. NONE of these wait for the server
// to confirm before updating the UI. This pattern is called "optimistic
// UI" and it's the single biggest perceived-speed win in mobile apps.
//
// The pattern:
//   1. User taps an action (send, like, add, delete).
//   2. The UI updates IMMEDIATELY to show the result (message appears,
//      heart fills, item added).
//   3. The server call fires in the background.
//   4. If the server succeeds: nothing changes (UI was already right).
//   5. If the server fails: ROLLBACK the UI to its previous state +
//      show an error + fire an error haptic.
//
// This makes every action feel instant (<16ms, one frame) regardless
// of network speed. The Doherty Threshold (<400ms feels instant) is
// satisfied trivially because the UI doesn't wait for the network at all.
//
// PSYCHOLOGICAL PRINCIPLE: DOHERTY THRESHOLD + LOSS AVERSION
// ─────────────────────────────────────────────────────────────────────
//   • Doherty: <400ms = user feels in control. Optimistic UI = <16ms.
//   • Loss Aversion: if the action fails and we roll back, the user
//     feels the LOSS of the optimistic state more strongly than if
//     they'd never seen it. This is why we pair rollback with a clear
//     error message + haptic — the user understands what happened,
//     not just that "it didn't work".
//
// USAGE
// ─────
//   final result = await OptimisticUIService.instance.execute(
//     optimisticAction: () {
//       // Update local state / provider IMMEDIATELY
//       ref.read(chatProvider.notifier).addMessage(message);
//     },
//     rollbackAction: () {
//       // Undo the optimistic update if the server fails
//       ref.read(chatProvider.notifier).removeMessage(message.id);
//     },
//     serverCall: () => api.sendMessage(message),
//     successHaptic: true,
//   );
//
// The [execute] method returns an [OptimisticResult] you can inspect.

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'haptic_service.dart';

/// The outcome of an optimistic action.
enum OptimisticResult {
  /// The server call succeeded. The optimistic UI was correct.
  success,
  /// The server call failed. The rollback was applied.
  rolledBack,
}

/// Executes optimistic UI actions: applies the optimistic state,
/// fires the server call, and rolls back on failure.
///
/// This is a stateless service — all state lives in the caller's
/// providers/controllers. The service just orchestrates the
/// apply → call → rollback sequence with proper haptics.
class OptimisticUIService {
  OptimisticUIService._();
  static final OptimisticUIService instance = OptimisticUIService._();

  /// Executes an optimistic action.
  ///
  /// Sequence:
  ///   1. [optimisticAction] — update the UI immediately.
  ///   2. [serverCall] — fire the network request.
  ///   3. On success: optionally fire [successHaptic]. Done.
  ///   4. On failure: [rollbackAction] — undo the UI. Fire error haptic.
  ///
  /// Returns [OptimisticResult.success] if the server call succeeded,
  /// [OptimisticResult.rolledBack] if it failed and was rolled back.
  ///
  /// NEVER throws — failures are caught and handled via rollback.
  /// The caller doesn't need a try/catch.
  Future<OptimisticResult> execute({
    required Future<void> Function() serverCall,
    required VoidCallback optimisticAction,
    required VoidCallback rollbackAction,
    bool successHaptic = true,
    bool errorHaptic = true,
  }) async {
    // 1. Apply the optimistic update IMMEDIATELY.
    try {
      optimisticAction();
    } catch (e) {
      // If even the optimistic action fails, abort — don't fire the
      // server call because the UI isn't in the expected state.
      if (errorHaptic) unawaited(HapticService.error());
      return OptimisticResult.rolledBack;
    }

    // 2. Fire the server call.
    try {
      await serverCall();
      // 3. Success — UI was already right. Optional success haptic.
      if (successHaptic) unawaited(HapticService.success());
      return OptimisticResult.success;
    } catch (e) {
      // 4. Failure — roll back the UI.
      try {
        rollbackAction();
      } catch (_) {
        // If rollback fails, the UI is in an inconsistent state.
        // This is a critical error but we still don't throw —
        // the user will see the inconsistency and can refresh.
        debugPrint('⚠️ OptimisticUI rollback failed: UI inconsistent');
      }
      if (errorHaptic) unawaited(HapticService.error());
      return OptimisticResult.rolledBack;
    }
  }
}
