// lib/features/games/ghost_painter/ghost_painter_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import 'ghost_painter_models.dart';

class GhostPainterState {
  const GhostPainterState({
    this.activeRound,
    this.strokes = const [],
    this.guesses = const [],
    this.myGuess,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });
  final GhostPainterRound? activeRound;
  final List<GhostPainterStroke> strokes;
  final List<GhostPainterGuess> guesses;
  final GhostPainterGuess? myGuess;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  bool get hasActiveRound => activeRound != null && activeRound!.isActive;
  bool get hasGuessed => myGuess != null;

  GhostPainterState copyWith({
    GhostPainterRound? activeRound,
    List<GhostPainterStroke>? strokes,
    List<GhostPainterGuess>? guesses,
    GhostPainterGuess? myGuess,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) => GhostPainterState(
    activeRound: activeRound ?? this.activeRound,
    strokes: strokes ?? this.strokes,
    guesses: guesses ?? this.guesses,
    myGuess: myGuess ?? this.myGuess,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: clearError ? null : (error ?? this.error),
  );
}

class GhostPainterNotifier extends StateNotifier<GhostPainterState> {
  GhostPainterNotifier(this._ref, this.familyId) : super(const GhostPainterState(isLoading: true));
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Member';

  RealtimeChannel? _channel;
  RealtimeChannel? _roundWatchChannel; // Watches for NEW rounds (when no active round)
  Timer? _strokeBatchTimer;
  Timer? _countdownTimer;
  final List<Map<String, dynamic>> _pendingStrokes = [];

  /// Cold-start retries: when the app is deep-linked straight onto the
  /// Ghost Painter screen, this notifier can be created BEFORE the
  /// Supabase client/session is wired into Riverpod. Without a retry
  /// the load bails once and the user is stranded on the start screen
  /// even though an active round exists.
  int _loadRetries = 0;

  Future<void> load() async {
    final client = _client;
    if (client == null) {
      if (_loadRetries < 6) {
        _loadRetries++;
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && state.activeRound == null) load();
        });
      } else {
        state = state.copyWith(isLoading: false, error: 'Not signed in');
      }
      return;
    }
    _loadRetries = 0;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Fetch active round
      final roundResp = await client
          .from('ghost_painter_rounds')
          .select()
          .eq('familyId', familyId)
          .inFilter('status', ['drawing', 'guessing'])
          .order('startedAt', ascending: false)
          .limit(1);
      if (roundResp.isEmpty) {
        state = GhostPainterState(isLoading: false);
        // Subscribe to round-watch so the card updates live when someone
        // else in the family starts a round
        _subscribeToRoundWatch();
        return;
      }
      final round = GhostPainterRound.fromJson(roundResp.first);
      // Fetch strokes
      final strokesResp = await client
          .from('ghost_painter_strokes')
          .select()
          .eq('roundId', round.id)
          .order('sequenceOrder', ascending: true);
      final strokes = strokesResp.map((s) => GhostPainterStroke.fromJson(s)).toList();
      // Fetch guesses
      final guessesResp = await client
          .from('ghost_painter_guesses')
          .select()
          .eq('roundId', round.id)
          .order('guessedAt', ascending: true);
      final guesses = guessesResp.map((g) => GhostPainterGuess.fromJson(g)).toList();
      final myId = _myId;
      // Latest guess (guesses are ordered by guessedAt ascending) — the
      // guess screen keeps the input visible until the latest guess is
      // correct, so this must not pin to the first-ever guess.
      final myGuess = guesses.where((g) => g.userId == myId).lastOrNull;
      state = GhostPainterState(activeRound: round, strokes: strokes, guesses: guesses, myGuess: myGuess, isLoading: false);
      _subscribeToRealtime(round.id);
      _startCountdownIfNeeded(round);
    } catch (e) {
      debugPrint('⚠️ GhostPainter load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  /// Subscribe to new rounds being created in this family
  /// (fires when another family member starts a round while we have none)
  void _subscribeToRoundWatch() {
    _roundWatchChannel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _roundWatchChannel = client.channel('ghost_painter_round_watch:$familyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'ghost_painter_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'familyId', value: familyId),
        callback: (payload) {
          // A new round was inserted — reload to pick it up
          debugPrint('🎲 GhostPainter: New round detected via Realtime, reloading...');
          load();
        },
      )
      .subscribe();
  }

  void _subscribeToRealtime(String roundId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _channel = client.channel('ghost_painter:$roundId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'ghost_painter_strokes',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'roundId', value: roundId),
        callback: (payload) {
          final stroke = GhostPainterStroke.fromJson(payload.newRecord);
          state = state.copyWith(strokes: [...state.strokes, stroke]);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'ghost_painter_guesses',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'roundId', value: roundId),
        callback: (payload) {
          final guess = GhostPainterGuess.fromJson(payload.newRecord);
          state = state.copyWith(guesses: [...state.guesses, guess]);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'ghost_painter_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: roundId),
        callback: (payload) {
          final round = GhostPainterRound.fromJson(payload.newRecord);
          state = state.copyWith(activeRound: round);
          // The round left the drawing phase (guessed correctly / ended /
          // someone else transitioned it) — stop the local countdown so the
          // timer can never downgrade a completed round back to 'guessing'.
          if (round.status != 'drawing') {
            _countdownTimer?.cancel();
          }
        },
      )
      .subscribe();
  }

  /// Start a new round — caller is the drawer
  Future<bool> startRound(String drawerPersonId, String drawerPersonName) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final prompt = ghostPainterPrompts[DateTime.now().millisecondsSinceEpoch % ghostPainterPrompts.length];
      final endsAt = DateTime.now().add(const Duration(seconds: 90));
      final resp = await client.from('ghost_painter_rounds').insert({
        'familyId': familyId,
        'drawerPersonId': drawerPersonId,
        'drawerPersonName': drawerPersonName,
        'promptWord': prompt,
        'status': 'drawing',
        'endsAt': endsAt.toIso8601String(),
      }).select().single();
      final round = GhostPainterRound.fromJson(resp);
      state = GhostPainterState(activeRound: round, isLoading: false);
      _subscribeToRealtime(round.id);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Batch stroke writes — called from the draw screen every ~100ms
  void queueStroke(List<OffsetPoint> points, int sequenceOrder) {
    if (points.isEmpty) return;
    // Only the round's drawer may author strokes — a guesser (or a
    // stale screen) can never write ink into someone else's round.
    final round = state.activeRound;
    final myId = _myId;
    if (round == null || myId == null || round.drawerPersonId != myId) return;
    _pendingStrokes.add({
      'roundId': state.activeRound?.id,
      // Insert as a native jsonb ARRAY — jsonEncode would store a
      // string, which the readers (and SQL) then have to unwrap.
      'strokeData': points.map((p) => p.toJson()).toList(),
      'sequenceOrder': sequenceOrder,
    });
    _strokeBatchTimer?.cancel();
    _strokeBatchTimer = Timer(const Duration(milliseconds: 100), _flushStrokes);
  }

  Future<void> _flushStrokes() async {
    final client = _client;
    if (client == null || _pendingStrokes.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_pendingStrokes);
    _pendingStrokes.clear();
    try {
      await client.from('ghost_painter_strokes').insert(batch);
    } catch (e) {
      debugPrint('⚠️ GhostPainter stroke flush error: $e');
    }
  }

  /// Submit a guess
  Future<bool> submitGuess(String text) async {
    final client = _client;
    final myId = _myId;
    final roundId = state.activeRound?.id;
    if (client == null || myId == null || roundId == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final promptWord = state.activeRound!.promptWord.trim().toLowerCase();
      final guessLower = text.trim().toLowerCase();
      // Exact match only — substring matching was exploitable (guessing
      // "e" won "elephant").
      final isCorrect = guessLower == promptWord;
      final resp = await client.from('ghost_painter_guesses').insert({
        'roundId': roundId,
        'userId': myId,
        'userName': _myName,
        'guessText': text,
        'isCorrect': isCorrect,
      }).select().single();
      final guess = GhostPainterGuess.fromJson(resp);
      state = state.copyWith(myGuess: guess, isSubmitting: false);
      if (isCorrect) {
        // Complete the round
        await client.from('ghost_painter_rounds').update({
          'status': 'completed',
          'endsAt': DateTime.now().toIso8601String(),
        }).eq('id', roundId);
      }
      return isCorrect;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Transition the round from 'drawing' to 'guessing' (drawer is done).
  /// Updates the Supabase row — other family members see this via Realtime.
  /// Guarded: never downgrades a round that already left 'drawing'
  /// (e.g. completed because someone guessed correctly).
  Future<void> transitionToGuessing() async {
    final client = _client;
    final roundId = state.activeRound?.id;
    if (client == null || roundId == null) return;
    if (state.activeRound?.status != 'drawing') return; // already guessing/completed
    _countdownTimer?.cancel();
    try {
      await client.from('ghost_painter_rounds').update({
        'status': 'guessing',
      }).eq('id', roundId).eq('status', 'drawing'); // server-side guard too
      // Update local state immediately for responsive UI
      final updatedRound = GhostPainterRound(
        id: state.activeRound!.id,
        familyId: state.activeRound!.familyId,
        drawerPersonId: state.activeRound!.drawerPersonId,
        drawerPersonName: state.activeRound!.drawerPersonName,
        promptWord: state.activeRound!.promptWord,
        status: 'guessing',
        startedAt: state.activeRound!.startedAt,
        endsAt: state.activeRound!.endsAt,
      );
      state = state.copyWith(activeRound: updatedRound);
    } catch (e) {
      debugPrint('⚠️ GhostPainter transitionToGuessing error: $e');
    }
  }

  /// Start a countdown timer that auto-transitions to guessing when time runs out
  void _startCountdownIfNeeded(GhostPainterRound round) {
    _countdownTimer?.cancel();
    if (round.status != 'drawing' || round.endsAt == null) return;
    final now = DateTime.now();
    final remaining = round.endsAt!.difference(now).inSeconds;
    if (remaining <= 0) {
      // Time already expired — transition immediately
      transitionToGuessing();
      return;
    }
    // Tick every second to update the countdown UI
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // The round may have moved on (completed via a correct guess, or
      // transitioned by another device) — the timer must respect that.
      if (state.activeRound?.status != 'drawing') {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(round.startedAt).inSeconds;
      final totalDuration = round.endsAt!.difference(round.startedAt).inSeconds;
      final remainingNow = totalDuration - elapsed;
      if (remainingNow <= 0) {
        timer.cancel();
        transitionToGuessing();
        return;
      }
      // State update triggers rebuild — the draw screen reads the countdown
      state = state.copyWith();
    });
  }

  /// Get remaining seconds for the current round's countdown
  int get remainingSeconds {
    final round = state.activeRound;
    if (round == null || round.endsAt == null) return 0;
    final remaining = round.endsAt!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// End the round early (drawer gives up or time runs out)
  Future<void> endRound() async {
    final client = _client;
    final roundId = state.activeRound?.id;
    if (client == null || roundId == null) return;
    try {
      await client.from('ghost_painter_rounds').update({
        'status': 'completed',
        'endsAt': DateTime.now().toIso8601String(),
      }).eq('id', roundId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _roundWatchChannel?.unsubscribe();
    _strokeBatchTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

final ghostPainterProvider =
    StateNotifierProvider.autoDispose.family<GhostPainterNotifier, GhostPainterState, String>(
  (ref, familyId) => GhostPainterNotifier(ref, familyId),
);
