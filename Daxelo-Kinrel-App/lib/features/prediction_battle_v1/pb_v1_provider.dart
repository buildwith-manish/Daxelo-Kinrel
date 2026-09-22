// lib/features/prediction_battle_v1/pb_v1_provider.dart
//
// Prediction Battle v1 — Riverpod provider for the scheduled numeric-
// estimation game. Fetches the current round + question + guesses via
// backend RPCs that enforce reveal-timing server-side.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/network/realtime_channel_registry.dart';
import '../../../core/utils/app_time.dart';
import 'pb_v1_models.dart';

class PBv1Notifier extends StateNotifier<PBv1State> {
  PBv1Notifier(this._ref, this.familyId) : super(const PBv1State(isLoading: true));
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  RealtimeChannel? _channel;
  Timer? _pollTimer;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final client = _client;
    if (client == null) {
      state = state.copyWith(isLoading: false, error: 'Not signed in');
      return;
    }
    try {
      // 1. Get the current round + question (creates one if needed)
      final roundResp = await client.rpc('fn_pb_v1_get_next_question', params: {'p_family_id': familyId});
      if (roundResp is Map) {
        final map = Map<String, dynamic>.from(roundResp);
        if (map['ok'] == true) {
          final round = PBv1Round.fromJson(Map<String, dynamic>.from(map['round'] as Map));
          final question = PBv1Question.fromJson(Map<String, dynamic>.from(map['question'] as Map));
          state = state.copyWith(round: round, question: question, isLoading: false);

          // 2. Get guesses (reveal-gated server-side)
          await _fetchGuesses(round.id);
          _subscribeToRealtime(round.id);
          _startPolling();
          return;
        }
      }
      state = state.copyWith(isLoading: false, round: null, question: null);
    } catch (e) {
      debugPrint('[PBv1] load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  Future<void> _fetchGuesses(String roundId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final resp = await client.rpc('fn_pb_v1_get_round_guesses', params: {
        'p_round_id': roundId,
        'p_requesting_user_id': myId,
      });
      if (resp is Map) {
        final map = Map<String, dynamic>.from(resp);
        final revealed = map['revealed'] == true;
        final myGuessJson = map['my_guess'];
        PBv1Guess? myGuess;
        if (myGuessJson is Map) {
          myGuess = PBv1Guess.fromJson(Map<String, dynamic>.from(myGuessJson));
        }
        List<PBv1Guess> allGuesses = [];
        if (revealed && map['guesses'] is List) {
          allGuesses = (map['guesses'] as List)
              .map((g) => PBv1Guess.fromJson(Map<String, dynamic>.from(g as Map)))
              .toList();
        }
        final winnerIds = <String>[];
        if (revealed && map['winner_user_ids'] is List) {
          winnerIds.addAll((map['winner_user_ids'] as List).whereType<String>());
        }
        state = state.copyWith(
          myGuess: myGuess,
          allGuesses: allGuesses,
          winnerUserIds: winnerIds,
          revealed: revealed,
        );
      }
    } catch (e) {
      debugPrint('[PBv1] fetchGuesses error: $e');
    }
  }

  Future<bool> submitGuess(double value) async {
    final client = _client;
    final myId = _myId;
    final round = state.round;
    if (client == null || myId == null || round == null) return false;
    try {
      final resp = await client.rpc('fn_pb_v1_submit_guess', params: {
        'p_round_id': round.id,
        'p_user_id': myId,
        'p_guess_value': value,
      });
      if (resp is Map && resp['ok'] == true) {
        final warning = resp['warning'] == true;
        state = state.copyWith(
          myGuess: PBv1Guess(userId: myId, guessValue: value, submittedAt: DateTime.now()),
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[PBv1] submit error: $e');
      return false;
    }
  }

  void _subscribeToRealtime(String roundId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _channel = client.channel('pb_v1:$roundId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'pb_v1_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: roundId),
        callback: (_) => _fetchGuesses(roundId),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'pb_v1_guesses',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'round_id', value: roundId),
        callback: (_) => _fetchGuesses(roundId),
      )
      .subscribe();

    final registry = _ref.read(realtimeChannelRegistryProvider);
    registry.register('pb_v1:$roundId', _channel!, () => _subscribeToRealtime(roundId), isLiveGame: false);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final round = state.round;
      if (round != null) _fetchGuesses(round.id);
    });
  }

  String get revealCountdown {
    final round = state.round;
    if (round == null) return '';
    final diff = round.revealAt.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'Reveal imminent';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${diff.inSeconds}s';
  }

  @override
  void dispose() {
    final roundId = state.round?.id;
    if (roundId != null) {
      final registry = _ref.read(realtimeChannelRegistryProvider);
      registry.unregister('pb_v1:$roundId');
    }
    _channel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }
}

final pbV1Provider = StateNotifierProvider.autoDispose.family<PBv1Notifier, PBv1State, String>(
  (ref, familyId) => PBv1Notifier(ref, familyId),
);
