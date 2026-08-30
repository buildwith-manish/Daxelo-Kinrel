// lib/graph/interaction/haptic_language.dart
//
// DAXELO KINREL — Graph Haptic Language (P3.2)
//
// Single source of truth for haptic patterns used across the graph.
// Per Vision §6 #2 (WOW 6) — restrained, consistent, accessible.
//
// Vocabulary:
//   nodeTap         selectionClick   — soft tick on node tap
//   nodeSelect      lightImpact      — slightly stronger on selection
//   edgeTap         selectionClick   — soft tick on edge tap
//   longPress       mediumImpact     — clear "menu opening" feel
//   focusEnter      heavyImpact      — clear "moment" feel on focus
//   focusExit       lightImpact      — gentle release on focus exit
//   branchExpand    mediumImpact     — branch opening (chip TAP)
//   branchMenuOpen  selectionClick + — branch ACTION SHEET (chip
//                   mediumImpact       LONG-PRESS): distinct double-
//                                      pulse so users feel the richer
//                                      interaction was triggered
//   pathTraceStep   selectionClick   — rhythmic footsteps along path
//   compareComplete heavyImpact      — clear "answer" feel on compare
//
// Reduced motion: ALL haptics disabled. The user feels nothing —
// consistent with "reduced motion = reduced stimulation." Per spec
// P3.2 accessibility considerations.
//
// Web: HapticFeedback is a no-op on web (no haptic hardware). No
// special handling needed.
//
// Background: haptics do not fire when the app is backgrounded. Per
// spec P3.2 edge cases.

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Single source of truth for graph haptic patterns.
///
/// All graph code MUST go through [GraphHaptics] — no direct
/// `HapticFeedback.*` calls (per P3.2 acceptance criterion).
///
/// The class exposes two flavors of each haptic:
///   * `xxx(context)` — checks `MediaQuery.disableAnimationsOf` and
///     the app lifecycle, then fires. Use this from widget code that
///     has a [BuildContext].
///   * `xxxNoContext({required bool reducedMotion})` — same checks
///     but accepts the reduced-motion flag as a parameter. Use this
///     from non-widget code (e.g. [GraphPathTraceController]) that
///     cannot reach a [BuildContext] but receives the flag from its
///     consumer.
class GraphHaptics {
  GraphHaptics._();

  // ── Public vocabulary (BuildContext flavor) ──────────────────────

  /// Soft tick on node tap.
  static Future<void> nodeTap(BuildContext context) =>
      _maybe(context, HapticFeedback.selectionClick);

  /// Slightly stronger haptic on node selection.
  static Future<void> nodeSelect(BuildContext context) =>
      _maybe(context, HapticFeedback.lightImpact);

  /// Soft tick on edge tap.
  static Future<void> edgeTap(BuildContext context) =>
      _maybe(context, HapticFeedback.selectionClick);

  /// Clear "menu opening" haptic on long-press.
  static Future<void> longPress(BuildContext context) =>
      _maybe(context, HapticFeedback.mediumImpact);

  /// Clear "moment" haptic on focus enter.
  static Future<void> focusEnter(BuildContext context) =>
      _maybe(context, HapticFeedback.heavyImpact);

  /// Gentle release haptic on focus exit.
  static Future<void> focusExit(BuildContext context) =>
      _maybe(context, HapticFeedback.lightImpact);

  /// "Branch opening" haptic on branch expand.
  static Future<void> branchExpand(BuildContext context) =>
      _maybe(context, HapticFeedback.mediumImpact);

  /// v5.132: "Branch action sheet opening" haptic on LONG-PRESS of a
  /// collapsed-branch chip.
  ///
  /// Distinct from [branchExpand] (a single medium impact, fired on
  /// chip TAP): this fires a double pulse — a soft selection tick,
  /// then the medium "menu opening" impact ~60 ms later — so users
  /// can FEEL that the long-press triggered the richer interaction
  /// (branch details + full-names preview) rather than the plain
  /// instant expand.
  ///
  /// The reduced-motion flag is read from [context] ONCE,
  /// synchronously, BEFORE the delay — the context is never used
  /// across an async gap.
  static Future<void> branchMenuOpen(BuildContext context) async {
    final reduced = MediaQuery.disableAnimationsOf(context);
    await _maybeNoContext(reduced, HapticFeedback.selectionClick);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _maybeNoContext(reduced, HapticFeedback.mediumImpact);
  }

  /// Clear "answer" haptic when the compare sheet opens.
  static Future<void> compareComplete(BuildContext context) =>
      _maybe(context, HapticFeedback.heavyImpact);

  // ── Public vocabulary (no-context flavor) ────────────────────────
  //
  // Used by non-widget code (e.g. GraphPathTraceController) that
  // receives the reduced-motion flag from its consumer.

  /// Rhythmic footsteps haptic on each path-trace step completion.
  ///
  /// [reducedMotion] — when true, no haptic fires.
  static Future<void> pathTraceStep({required bool reducedMotion}) =>
      _maybeNoContext(reducedMotion, HapticFeedback.selectionClick);

  /// No-context variant of [nodeTap].
  static Future<void> nodeTapNoContext({required bool reducedMotion}) =>
      _maybeNoContext(reducedMotion, HapticFeedback.selectionClick);

  /// No-context variant of [longPress].
  static Future<void> longPressNoContext({required bool reducedMotion}) =>
      _maybeNoContext(reducedMotion, HapticFeedback.mediumImpact);

  /// No-context variant of [focusEnter].
  static Future<void> focusEnterNoContext({required bool reducedMotion}) =>
      _maybeNoContext(reducedMotion, HapticFeedback.heavyImpact);

  // ── Internal helpers ────────────────────────────────────────────

  /// Gate for widget-context haptics. Checks:
  ///   1. Reduced motion is NOT active (MediaQuery).
  ///   2. App lifecycle is `resumed` (not backgrounded).
  /// Then fires [haptic].
  static Future<void> _maybe(
    BuildContext context,
    Future<void> Function() haptic,
  ) {
    // Reduced motion → skip entirely. Per spec P3.2 accessibility.
    if (MediaQuery.disableAnimationsOf(context)) return Future.value();
    // Background → skip. Per spec P3.2 edge cases.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return Future.value();
    }
    return haptic();
  }

  /// Gate for non-widget haptics. Same rules as [_maybe] but the
  /// reduced-motion flag is passed by the caller (who read it from
  /// a BuildContext before invoking the controller).
  static Future<void> _maybeNoContext(
    bool reducedMotion,
    Future<void> Function() haptic,
  ) {
    if (reducedMotion) return Future.value();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return Future.value();
    }
    return haptic();
  }
}
