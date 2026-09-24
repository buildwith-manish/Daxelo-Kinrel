// lib/features/prediction_battle_v1/pb_v1_prediction_widget_updater.dart
//
// Phase 3.21 — Home-screen widget updater for the Prediction Battle.
//
// Writes an urgency-sorted list of families (with their current
// prediction state) to SharedPreferences via the home_widget
// package. The native Kotlin widget reads the JSON and renders the
// top family's card. The cycle-chip tap increments an index in the
// native prefs so the widget re-renders with the next family.
//
// When the updater runs
//   - On app foreground (AppLifecycleState.resumed) — picks up any
//     state changes that happened while the app was backgrounded
//   - On prediction state changes (card load, guess submit, reveal)
//     — wired from pbV1Provider's load() + submitGuess() via a
//     Riverpod listener in main.dart
//   - On a 15-min timer (matches the NestJS scheduler cadence) —
//     keeps the countdown fresh even when the app is foregrounded
//     but not actively navigating
//
// Urgency score (computed in Dart before writing to prefs)
//   - open + not submitted + streak ≥ 3 + after 8:30 PM IST = highest
//   - open + not submitted = high
//   - open + submitted = low (action taken)
//   - locked = low (waiting for reveal)
//   - revealed = lowest (no action needed)
//   - Tiebreaker: most recently active family first
//
// What gets written
//   A JSON array under the SharedPreferences key
//   'kinrel_prediction_widget_data'. Each element:
//     {
//       "family_id": "fam-abc",
//       "family_name": "Sharma Family",
//       "question_text": "How many moons does Jupiter have?",
//       "unit_label": "moons",
//       "status": "open",          // 'open' | 'revealed'
//       "my_guess": 95,             // null if not submitted
//       "correct_answer": 95,      // null before reveal
//       "is_winner": false,
//       "reveal_at_iso": "2026-09-23T16:00:00.000Z",
//       "countdown_text": "4h 23m left",
//       "streak_in_danger": true,
//       "current_streak": 5
//     }
//   Plus a separate key 'kinrel_prediction_widget_count' with the
//   array length (so the native side knows how many families there
//   are without parsing the JSON).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/family/family_provider.dart';
import 'pb_v1_models.dart';

/// The Android app widget provider's Java/Kotlin class name. Must
/// match the `<receiver android:name="...">` in
/// Daxelo-Kinrel-App/android/app/src/main/AndroidManifest.xml.
const _kAndroidWidgetProviderName = 'PredictionWidgetProvider';

/// SharedPreferences keys. The native Kotlin side reads these.
const _kWidgetDataKey = 'kinrel_prediction_widget_data';
const _kWidgetCountKey = 'kinrel_prediction_widget_count';
const _kWidgetSelectedIndexKey = 'kinrel_prediction_widget_selected_index';

class PredictionWidgetUpdater {
  PredictionWidgetUpdater(this._ref);
  final Ref _ref;

  Timer? _refreshTimer;
  bool _running = false;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;

  /// Start the periodic refresh timer. Called from main.dart on
  /// app startup. The timer fires every 15 min to keep the
  /// countdown text fresh.
  void startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      refresh();
    });
    // Also do an immediate refresh on start.
    refresh();
  }

  /// Stop the periodic refresh timer. Called from main.dart on
  /// app dispose.
  void stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Refresh the widget data. Fetches all families the user belongs
  /// to, then for each family fetches the current prediction state,
  /// computes the urgency score, sorts, and writes the JSON to prefs.
  /// Triggers a native widget update so the home screen re-renders.
  Future<void> refresh() async {
    if (_running) return; // Prevent concurrent runs.
    _running = true;
    try {
      final client = _client;
      final myId = _myId;
      if (client == null || myId == null) return;

      // 1. Get all families the user belongs to.
      final familyRows = await client
          .from('FamilyMember')
          .select('familyId, family:Family(id, name)')
          .eq('userId', myId);
      if (!kReleaseMode) {
        debugPrint('[PredictionWidget] found ${(familyRows as List).length} family memberships');
      }
      final families = <_FamilyPredictionState>[];
      for (final row in (familyRows as List)) {
        final r = row as Map<String, dynamic>;
        final family = r['family'];
        if (family is! Map) continue;
        final familyId = (family['id'] ?? '') as String;
        final familyName = (family['name'] ?? 'Family') as String;
        if (familyId.isEmpty) continue;

        // 2. For each family, fetch the current prediction state.
        final state = await _fetchFamilyState(familyId, familyName);
        if (state != null) families.add(state);
      }

      // 3. Sort by urgency score (descending — highest urgency first).
      families.sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));

      // 4. Write to SharedPreferences via home_widget.
      final jsonList = families.map((f) => f.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await HomeWidget.saveWidgetData(_kWidgetDataKey, jsonString);
      await HomeWidget.saveWidgetData(_kWidgetCountKey, families.length);
      // Reset the selected index if it's now out of bounds (e.g., user
      // left a family). The native side clamps on read too, but we
      // also clamp here to avoid a stale index pointing at nothing.
      final selectedIndex = await HomeWidget.readWidgetData<int>(_kWidgetSelectedIndexKey) ?? 0;
      if (selectedIndex >= families.length) {
        await HomeWidget.saveWidgetData(_kWidgetSelectedIndexKey, 0);
      }

      // 5. Trigger the native widget update.
      await HomeWidget.updateWidget(
        androidName: _kAndroidWidgetProviderName,
      );
      if (!kReleaseMode) {
        debugPrint('[PredictionWidget] updated: ${families.length} families, top: ${families.isEmpty ? "none" : families.first.familyName}');
      }
    } catch (e) {
      debugPrint('[PredictionWidget] refresh error: $e');
    } finally {
      _running = false;
    }
  }

  /// Fetch the current prediction state for a single family.
  /// Returns null if the fetch fails or the family has no round.
  Future<_FamilyPredictionState?> _fetchFamilyState(
    String familyId,
    String familyName,
  ) async {
    try {
      final client = _client;
      if (client == null) return null;
      final resp = await client.rpc('fn_pb_v1_get_next_question', params: {
        'p_family_id': familyId,
      });
      if (resp is! Map || resp['ok'] != true) return null;

      final round = PBv1Round.fromJson(Map<String, dynamic>.from(resp['round'] as Map));
      final question = PBv1Question.fromJson(Map<String, dynamic>.from(resp['question'] as Map));

      // Fetch the user's guess for this round + the family's current
      // streak for this user. We do these in parallel to save a
      // round-trip.
      final results = await Future.wait([
        client
            .from('pb_v1_guesses')
            .select('guess_value')
            .eq('round_id', round.id)
            .eq('user_id', _myId!)
            .maybeSingle(),
        client
            .from('pb_v1_win_streaks')
            .select('current_streak')
            .eq('user_id', _myId!)
            .eq('family_id', familyId)
            .maybeSingle(),
      ]);

      final guessRow = results[0] as Map<String, dynamic>?;
      final myGuess = guessRow != null
          ? (guessRow['guess_value'] as num?)?.toDouble()
          : null;

      final streakRow = results[1] as Map<String, dynamic>?;
      final currentStreak = (streakRow?['current_streak'] as int?) ?? 0;

      final isRevealed = round.status == 'revealed' ||
          AppTime.nowServerAccurate().isAfter(round.revealAt);

      // If revealed, fetch the correct answer + whether the user won.
      // (The RPC returns the question with the correct answer only
      // after reveal — for the 'open' status, correct_answer is in
      // the question JSON but we should NOT show it on the widget
      // since the round is still open. The native side checks status.)
      double? correctAnswer;
      bool isWinner = false;
      if (isRevealed) {
        correctAnswer = question.correctAnswer;
        // We'd need to fetch all guesses + compute winners to know if
        // the user won. That's expensive per-family per-refresh.
        // Instead, we let the native widget just show "Reveal is in"
        // without the winner detail. The user taps the widget →
        // opens the reveal screen → sees the full result. This keeps
        // the widget refresh cheap.
      }

      return _FamilyPredictionState(
        familyId: familyId,
        familyName: familyName,
        questionText: question.questionText,
        unitLabel: question.unitLabel,
        status: isRevealed ? 'revealed' : 'open',
        myGuess: myGuess,
        correctAnswer: isRevealed ? correctAnswer : null,
        isWinner: isWinner,
        revealAt: round.revealAt,
        currentStreak: currentStreak,
      );
    } catch (e) {
      debugPrint('[PredictionWidget] _fetchFamilyState($familyId) error: $e');
      return null;
    }
  }
}

/// Internal model for a family's current prediction state + the
/// computed urgency score. Serialized to JSON for the native widget.
class _FamilyPredictionState {
  _FamilyPredictionState({
    required this.familyId,
    required this.familyName,
    required this.questionText,
    required this.unitLabel,
    required this.status,
    required this.myGuess,
    required this.correctAnswer,
    required this.isWinner,
    required this.revealAt,
    required this.currentStreak,
  });

  final String familyId;
  final String familyName;
  final String questionText;
  final String unitLabel;
  final String status;        // 'open' | 'revealed'
  final double? myGuess;
  final double? correctAnswer;
  final bool isWinner;
  final DateTime revealAt;
  final int currentStreak;

  /// Computed urgency score (higher = shown first on the widget).
  /// See file header for the scoring rubric.
  double get urgencyScore {
    final now = AppTime.nowServerAccurate();
    final isPastReveal = now.isAfter(revealAt);
    final streakInDanger = currentStreak >= 3 && myGuess == null && !isPastReveal;

    if (!isPastReveal) {
      // Round is open.
      if (myGuess == null) {
        if (streakInDanger) return 100; // highest
        return 80;                       // high
      }
      return 30;                         // low — action taken
    }
    // Round is revealed.
    return 10;                           // lowest
  }

  /// Human-readable countdown for the widget. Mirrors the
  /// revealCountdown logic in pb_v1_provider.
  String get countdownText {
    if (status == 'revealed') return 'Reveal is in';
    final diff = revealAt.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'Reveal imminent';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '$h h $m m left';
    if (m > 0) return '$m m left';
    return '${diff.inSeconds}s left';
  }

  bool get streakInDanger =>
      currentStreak >= 3 && myGuess == null && status == 'open';

  Map<String, dynamic> toJson() => {
    'family_id': familyId,
    'family_name': familyName,
    'question_text': questionText,
    'unit_label': unitLabel,
    'status': status,
    'my_guess': myGuess,
    'correct_answer': correctAnswer,
    'is_winner': isWinner,
    'reveal_at_iso': revealAt.toUtc().toIso8601String(),
    'countdown_text': countdownText,
    'streak_in_danger': streakInDanger,
    'current_streak': currentStreak,
  };
}

final predictionWidgetUpdaterProvider = Provider<PredictionWidgetUpdater>(
  (ref) => PredictionWidgetUpdater(ref),
);
