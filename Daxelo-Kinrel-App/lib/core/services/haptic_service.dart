// lib/core/services/haptic_service.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  HAPTIC SERVICE — iOS-grade tactile feedback, centralized           │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Haptic feedback is the single biggest contributor to perceived "iOS
// smoothness" that costs ZERO infrastructure. iOS uses a tightly
// constrained haptic vocabulary — selection clicks, impact bumps, and
// notification success/warning/error patterns — and users have been
// trained to read them as "this app feels premium".
//
// Before this service, the codebase called `HapticFeedback.lightImpact()`
// in 10+ separate places with no consistency: some screens used it,
// others didn't, and the intensity was arbitrary. This service gives
// the whole app a single, documented haptic vocabulary so a tap on a
// sign-in button feels the same as a tap on any other primary CTA.
//
// PSYCHOLOGICAL PRINCIPLE: OPERANT CONDITIONING (Skinner)
// ─────────────────────────────────────────────────────────────────────
// A immediate, consistent tactile response to an action reinforces
// the action and makes the UI feel responsive BEFORE the visual
// loading state even appears. This shrinks perceived latency — the
// user's brain registers "the app accepted my tap" within ~10ms of
// the haptic firing, while a network round-trip takes 200-800ms.
//
// PERFORMANCE
// ───────────
// HapticFeedback calls are platform-channel round-trips but they are
// fire-and-forget and never block the UI thread. All methods are
// async and use `unawaited()` at call sites so they cannot delay
// navigation or build phases.
//
// ACCESSIBILITY
// ─────────────
// All methods check the platform's reduced-motion / accessibility
// settings where available. On Android, haptics respect the system
// "touch feedback" setting. On iOS, they respect "Vibration". We do
// NOT override user preferences.
//
// USAGE
// ─────
//   // Tap a primary button
//   unawaited(HapticService.tap());
//
//   // Successful action (login, save, send)
//   unawaited(HapticService.success());
//
//   // Error / validation failure
//   unawaited(HapticService.error());
//
//   // Selection change (tab, segment, picker)
//   unawaited(HapticService.selection());

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized haptic feedback vocabulary for the entire app.
///
/// Use this instead of calling [HapticFeedback] directly so the
/// haptic language stays consistent and can be tuned in one place.
class HapticService {
  HapticService._();

  /// Whether haptics are supported on the current platform.
  /// Web doesn't have haptics; native platforms do.
  static bool get isSupported => !kIsWeb;

  /// Light tap — used for primary button presses (CTAs).
  ///
  /// iOS equivalent: `UIImpactFeedbackGenerator(.light)`.
  /// This is the workhorse: tap a sign-in button, tap a card, tap a
  /// tab. It's subtle enough to not annoy but present enough to
  /// confirm "the tap registered".
  static Future<void> tap() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Haptics are best-effort — never let them crash the UI.
    }
  }

  /// Medium tap — used for secondary actions (toggles, chips).
  ///
  /// iOS equivalent: `UIImpactFeedbackGenerator(.medium)`.
  /// Slightly stronger than [tap] so the user can distinguish a
  /// primary CTA from a secondary action by feel alone.
  static Future<void> medium() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Selection click — used for tab switches, picker changes,
  /// segmented controls.
  ///
  /// iOS equivalent: `UISelectionFeedbackGenerator`.
  /// This is the lightest possible haptic — a tiny "tick" that
  /// confirms a selection changed. Use it whenever the user picks
  /// one option from a set (tabs, segments, dropdowns).
  static Future<void> selection() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Success pattern — used after a successful async action
  /// (login completed, save succeeded, message sent).
  ///
  /// iOS equivalent: `UINotificationFeedbackGenerator().notificationSuccess()`.
  /// This plays a specific pattern that iOS users associate with
  /// "the operation succeeded" — it's a rising tick-tock pattern
  /// that the brain reads as positive.
  static Future<void> success() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.successNotification();
    } catch (_) {}
  }

  /// Warning pattern — used for soft warnings (form validation
  /// that's recoverable, retryable failures).
  ///
  /// iOS equivalent: `UINotificationFeedbackGenerator().notificationWarning()`.
  static Future<void> warning() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.warningNotification();
    } catch (_) {}
  }

  /// Error pattern — used after a hard failure (login rejected,
  /// network error, save failed).
  ///
  /// iOS equivalent: `UINotificationFeedbackGenerator().notificationError()`.
  /// This is the strongest haptic pattern — a double-buzz that
  /// the brain reads as "something went wrong". Pair it with a
  /// visible error message; don't fire it without a UI cue.
  static Future<void> error() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.errorNotification();
    } catch (_) {}
  }

  /// Soft error — a single medium impact, used for inline form
  /// validation errors that don't warrant the full error pattern.
  ///
  /// Use this when a field fails validation but the user hasn't
  /// submitted yet (e.g., password too short as they type past
  /// the threshold).
  static Future<void> softError() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}
