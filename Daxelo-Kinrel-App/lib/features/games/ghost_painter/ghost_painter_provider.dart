// lib/features/games/ghost_painter/ghost_painter_provider.dart

import 'dart:async';
import 'dart:convert';
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
  Timer? _strokeBatchTimer;
  final List<Map<String, dynamic>> _pendingStrokes = [];

  Future<void> load() async {
    final client = _client;
    if (client == null) { state = state.copyWith(isLoading: false, error: 'Not signed in'); return; }
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
        return;
      }
      final round = GhostPainterRound.fromJson(roundResp.first as Map<String, dynamic>);
      // Fetch strokes
      final strokesResp = await client
          .from('ghost_painter_strokes')
          .select()
          .eq('roundId', round.id)
          .order('sequenceOrder', ascending: true);
      final strokes = strokesResp.map((s) => GhostPainterStroke.fromJson(s as Map<String, dynamic>)).toList();
      // Fetch guesses
      final guessesResp = await client
          .from('ghost_painter_guesses')
          .select()
          .eq('roundId', round.id)
          .order('guessedAt', ascending: true);
      final guesses = guessesResp.map((g) => GhostPainterGuess.fromJson(g as Map<String, dynamic>)).toList();
      final myId = _myId;
      final myGuess = guesses.where((g) => g.userId == myId).firstOrNull;
      state = GhostPainterState(activeRound: round, strokes: strokes, guesses: guesses, myGuess: myGuess, isLoading: false);
      _subscribeToRealtime(round.id);
    } catch (e) {
      debugPrint('⚠️ GhostPainter load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
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
      final round = GhostPainterRound.fromJson(resp as Map<String, dynamic>);
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
    _pendingStrokes.add({
      'roundId': state.activeRound?.id,
      'strokeData': jsonEncode(points.map((p) => p.toJson()).toList()),
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
      final promptWord = state.activeRound!.promptWord.toLowerCase();
      final guessLower = text.toLowerCase().trim();
      final isCorrect = guessLower == promptWord || guessLower.contains(promptWord) || promptWord.contains(guessLower);
      final resp = await client.from('ghost_painter_guesses').insert({
        'roundId': roundId,
        'userId': myId,
        'userName': _myName,
        'guessText': text,
        'isCorrect': isCorrect,
      }).select().single();
      final guess = GhostPainterGuess.fromJson(resp as Map<String, dynamic>);
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
    _strokeBatchTimer?.cancel();
    super.dispose();
  }
}

final ghostPainterProvider =
    StateNotifierProvider.autoDispose.family<GhostPainterNotifier, GhostPainterState, String>(
  (ref, familyId) => GhostPainterNotifier(ref, familyId),
);
