// lib/features/prediction_battle/prediction_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import 'prediction_models.dart';

class PredictionState {
  const PredictionState({
    this.activeRound,
    this.activeQuestion,
    this.participationCount = 0,
    this.hasSubmitted = false,
    this.myPrediction,
    this.myConfidence,
    this.recentResults = const [],
    this.leaderboard = const [],
    this.myStats,
    this.isLoading = false,
    this.error,
    this.inactiveReason,
  });
  final PredictionRound? activeRound;
  final PredictionQuestion? activeQuestion;
  final int participationCount;
  final bool hasSubmitted;
  final String? myPrediction;
  final PredictionConfidence? myConfidence;
  final List<PredictionRound> recentResults;
  final List<PredictionLeaderboardEntry> leaderboard;
  final PredictionLeaderboardEntry? myStats;
  final bool isLoading;
  final String? error;
  /// Why there's no active round, when applicable:
  ///   'before_window'  — current time is before 8:00 AM IST (opens soon)
  ///   'after_window'   — current time is after 9:30 PM IST (closed for today)
  ///   'no_questions_available' — question pool exhausted
  ///   null — either there's an active round, or loading/unknown.
  final String? inactiveReason;

  PredictionState copyWith({
    PredictionRound? activeRound,
    PredictionQuestion? activeQuestion,
    int? participationCount,
    bool? hasSubmitted,
    String? myPrediction,
    PredictionConfidence? myConfidence,
    List<PredictionRound>? recentResults,
    List<PredictionLeaderboardEntry>? leaderboard,
    PredictionLeaderboardEntry? myStats,
    bool? isLoading,
    bool clearError = false,
    String? error,
    String? inactiveReason,
    bool clearInactiveReason = false,
  }) => PredictionState(
    activeRound: activeRound ?? this.activeRound,
    activeQuestion: activeQuestion ?? this.activeQuestion,
    participationCount: participationCount ?? this.participationCount,
    hasSubmitted: hasSubmitted ?? this.hasSubmitted,
    myPrediction: myPrediction ?? this.myPrediction,
    myConfidence: myConfidence ?? this.myConfidence,
    recentResults: recentResults ?? this.recentResults,
    leaderboard: leaderboard ?? this.leaderboard,
    myStats: myStats ?? this.myStats,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    inactiveReason: clearInactiveReason ? null : (inactiveReason ?? this.inactiveReason),
  );
}

class PredictionNotifier extends StateNotifier<PredictionState> {
  PredictionNotifier(this._ref, this.familyId) : super(const PredictionState());
  final Ref _ref;
  final String familyId;
  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  RealtimeChannel? _channel;
  Timer? _tickTimer;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _fetchActive();
    await _fetchRecentResults();
    await _fetchLeaderboard();
    _subscribeToRealtime();
    _startTick();
    state = state.copyWith(isLoading: false);
  }

  Future<void> _fetchActive() async {
    final client = _client;
    if (client == null) return;
    try {
      final raw = await client.rpc('fn_prediction_get_active', params: {'p_family_id': familyId});
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        if (map['ok'] == false) {
          // No active round. Capture the reason so the UI can show
          // "Opens at 8:00 AM" vs "Closed for today" appropriately.
          final reason = map['reason'] as String?;
          state = state.copyWith(
            activeRound: null,
            activeQuestion: null,
            inactiveReason: reason,
            clearInactiveReason: reason == null,
          );
          return;
        }
        final round = PredictionRound.fromJson(Map<String, dynamic>.from(map['round'] as Map));
        final question = PredictionQuestion.fromJson(Map<String, dynamic>.from(map['question'] as Map));
        final participation = (map['participationCount'] as num?)?.toInt() ?? 0;
        // Check if I've submitted
        final myId = _myId;
        bool submitted = false;
        String? myPred;
        PredictionConfidence? myConf;
        if (myId != null && (round.status == PredictionStatus.open || round.status == PredictionStatus.locked)) {
          final subsResp = await client.from('prediction_submissions').select().eq('roundId', round.id).eq('userId', myId).maybeSingle();
          if (subsResp != null) {
            submitted = true;
            myPred = subsResp['prediction'] as String?;
            myConf = PredictionConfidenceX.fromString(subsResp['confidence'] as String?);
          }
        }
        state = state.copyWith(
          activeRound: round,
          activeQuestion: question,
          participationCount: participation,
          hasSubmitted: submitted,
          myPrediction: myPred,
          myConfidence: myConf,
          clearInactiveReason: true,
        );
      }
    } catch (e) { debugPrint('[Prediction] fetchActive error: $e'); }
  }

  Future<void> _fetchRecentResults() async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.from('prediction_rounds').select('*, prediction_questions(*)').eq('familyId', familyId).eq('status', 'resolved').order('resolvedAt', ascending: false).limit(20);
      final rounds = resp.map((r) {
        final map = Map<String, dynamic>.from(r);
        if (map['prediction_questions'] is Map) {
          map['question'] = map.remove('prediction_questions');
        }
        return PredictionRound.fromJson(map);
      }).toList();
      state = state.copyWith(recentResults: rounds);
    } catch (e) { debugPrint('[Prediction] fetchRecent error: $e'); }
  }

  Future<void> _fetchLeaderboard() async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.from('prediction_leaderboard').select().eq('familyId', familyId).order('points', ascending: false);
      final entries = resp.map((e) => PredictionLeaderboardEntry.fromJson(e)).toList();
      final myId = _myId;
      PredictionLeaderboardEntry? myStats;
      if (myId != null) {
        for (final e in entries) { if (e.userId == myId) { myStats = e; break; } }
      }
      state = state.copyWith(leaderboard: entries, myStats: myStats);
    } catch (e) { debugPrint('[Prediction] fetchLeaderboard error: $e'); }
  }

  Future<bool> submitPrediction(String prediction, PredictionConfidence confidence) async {
    final client = _client;
    final myId = _myId;
    final round = state.activeRound;
    if (client == null || myId == null || round == null) return false;
    try {
      final raw = await client.rpc('fn_prediction_submit', params: {
        'p_round_id': round.id, 'p_user_id': myId, 'p_family_id': familyId,
        'p_prediction': prediction, 'p_confidence': confidence.wire,
      });
      if (raw is Map && raw['ok'] == true) {
        state = state.copyWith(hasSubmitted: true, myPrediction: prediction, myConfidence: confidence, participationCount: state.participationCount + 1);
        return true;
      }
      return false;
    } catch (e) { debugPrint('[Prediction] submit error: $e'); return false; }
  }

  void _subscribeToRealtime() {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _channel = client.channel('prediction_battle:$familyId')
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'prediction_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'familyId', value: familyId),
        callback: (_) => _fetchActive())
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'prediction_submissions',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'familyId', value: familyId),
        callback: (_) { state = state.copyWith(participationCount: state.participationCount + 1); })
      .subscribe();
  }

  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _tryRpc('fn_prediction_tick', {'p_family_id': familyId});
    });
  }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async {
    final client = _client;
    if (client == null) return false;
    try { await client.rpc(fn, params: params); return true; }
    catch (e) { debugPrint('[Prediction] $fn error: $e'); return false; }
  }

  @override
  void dispose() { _channel?.unsubscribe(); _tickTimer?.cancel(); super.dispose(); }
}

final predictionProvider = StateNotifierProvider.autoDispose.family<PredictionNotifier, PredictionState, String>(
  (ref, familyId) => PredictionNotifier(ref, familyId),
);
