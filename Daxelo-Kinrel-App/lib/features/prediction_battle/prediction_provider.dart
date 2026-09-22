// lib/features/prediction_battle/prediction_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/network/realtime_channel_registry.dart';
import 'prediction_models.dart';

class PredictionState {
  const PredictionState({
    this.activeRound,
    this.activeQuestion,
    this.participationCount = 0,
    this.hasSubmitted = false,
    this.myPrediction,
    this.myConfidence,
    /// All submissions for the active round — used by the expanded
    /// card to show other members' answers AFTER the reveal time has
    /// passed (gated by the UI via AppTime.nowIst() vs round.revealAt).
    /// Before reveal time, the UI should show only the count, not
    /// individual predictions.
    this.allSubmissions = const [],
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
  final List<PredictionSubmission> allSubmissions;
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
    List<PredictionSubmission>? allSubmissions,
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
    allSubmissions: allSubmissions ?? this.allSubmissions,
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
    // Tier 1 #4 — parallelize independent fetches (eagerError: false
    // so partial failure still renders partial UI).
    await Future.wait([
      _fetchActive(),
      _fetchRecentResults(),
      _fetchLeaderboard(),
    ]);
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
        // Check if I've submitted + fetch ALL submissions for this round
        // (used by the expanded card to show other members' answers
        // AFTER reveal time — gated by the UI via AppTime.nowIst()).
        final myId = _myId;
        bool submitted = false;
        String? myPred;
        PredictionConfidence? myConf;
        List<PredictionSubmission> allSubs = [];
        if (myId != null && (round.status == PredictionStatus.open || round.status == PredictionStatus.locked || round.status == PredictionStatus.pending)) {
          // Fetch all submissions for this round — joined with User
          // table for display names (the prediction_submissions table
          // has userId but no userName column, so we join).
          try {
            final subsResp = await client
                .from('prediction_submissions')
                .select('*, User(name)')
                .eq('roundId', round.id)
                .order('submittedAt', ascending: true);
            // Index by roundId for O(1) merge.
            for (final s in subsResp) {
              final sub = PredictionSubmission.fromJson(Map<String, dynamic>.from(s));
              allSubs.add(sub);
              if (sub.userId == myId) {
                submitted = true;
                myPred = sub.prediction;
                myConf = sub.confidence;
              }
            }
          } catch (e) {
            // Fallback: just fetch my own submission.
            debugPrint('[Prediction] fetchActive (all subs) error: $e');
            final subsResp = await client.from('prediction_submissions').select().eq('roundId', round.id).eq('userId', myId).maybeSingle();
            if (subsResp != null) {
              submitted = true;
              myPred = subsResp['prediction'] as String?;
              myConf = PredictionConfidenceX.fromString(subsResp['confidence'] as String?);
            }
          }
        }
        // Join user names for allSubs that have empty userName.
        if (allSubs.any((s) => s.userName.isEmpty)) {
          try {
            final namesResp = await client.rpc('fn_get_family_member_names', params: {'family_id': familyId});
            if (namesResp is List) {
              final namesByUserId = <String, String>{};
              for (final row in namesResp) {
                if (row is Map) {
                  final uid = row['userId'] as String?;
                  final name = row['name'] as String?;
                  if (uid != null && name != null && name.isNotEmpty) {
                    namesByUserId[uid] = name;
                  }
                }
              }
              if (namesByUserId.isNotEmpty) {
                allSubs = allSubs.map((s) {
                  final name = namesByUserId[s.userId];
                  if (name != null && s.userName.isEmpty) {
                    return PredictionSubmission(
                      userId: s.userId,
                      userName: name,
                      prediction: s.prediction,
                      confidence: s.confidence,
                      submittedAt: s.submittedAt,
                    );
                  }
                  return s;
                }).toList();
              }
            }
          } catch (e) {
            debugPrint('[Prediction] fetchActive (sub names) error: $e');
          }
        }
        state = state.copyWith(
          activeRound: round,
          activeQuestion: question,
          participationCount: participation,
          hasSubmitted: submitted,
          myPrediction: myPred,
          myConfidence: myConf,
          allSubmissions: allSubs,
          clearInactiveReason: true,
        );
      }
    } catch (e) { debugPrint('[Prediction] fetchActive error: $e'); }
  }

  Future<void> _fetchRecentResults() async {
    final client = _client;
    if (client == null) return;
    try {
      // Step (locked-in expand): also fetch my own submissions for the
      // recent resolved rounds so the card can show "Your guess: X" in
      // the expanded locked-in / completed state's "Recent rounds" list.
      // We fetch the resolved rounds first (joined with their question),
      // then a separate query for my submissions on those round ids,
      // then merge my prediction + points into each round's `results`
      // list so the UI can find "my result" via `results.firstWhere(
      // (r) => r.userId == myId)`.
      final resp = await client.from('prediction_rounds').select('*, prediction_questions(*)').eq('familyId', familyId).eq('status', 'resolved').order('resolvedAt', ascending: false).limit(20);
      final rounds = resp.map((r) {
        final map = Map<String, dynamic>.from(r);
        if (map['prediction_questions'] is Map) {
          map['question'] = map.remove('prediction_questions');
        }
        return PredictionRound.fromJson(map);
      }).toList();

      // Fetch my submissions for these rounds (one query, not N).
      final myId = _myId;
      if (myId != null && rounds.isNotEmpty) {
        final roundIds = rounds.map((r) => r.id).toList();
        try {
          final subsResp = await client
              .from('prediction_submissions')
              .select('roundId, prediction, confidence')
              .inFilter('roundId', roundIds)
              .eq('userId', myId);
          // Index by roundId for O(1) merge.
          final mySubsByRoundId = <String, Map<String, dynamic>>{};
          for (final s in subsResp) {
            // Supabase returns PostgREST rows as Map<String, dynamic>.
            final rid = s['roundId'] as String?;
            if (rid != null) mySubsByRoundId[rid] = Map<String, dynamic>.from(s);
          }
          // Merge each submission into the matching round's results list
          // so the UI can find "my result" via round.results.firstWhere(
          // (r) => r.userId == myId). For rounds where I didn't submit,
          // we leave the results list as-is (I just didn't play).
          final merged = <PredictionRound>[];
          for (final round in rounds) {
            final mySub = mySubsByRoundId[round.id];
            if (mySub == null) {
              merged.add(round);
              continue;
            }
            // Build a PredictionResult for me. Use the existing result
            // entry if it exists (the resolve RPC populates results with
            // points/rank/correct), otherwise synthesize one with the
            // prediction + confidence (points default to 0).
            final existing = round.results.where((r) => r.userId == myId).toList();
            final myResult = existing.isNotEmpty
                ? existing.first
                : PredictionResult(
                    userId: myId,
                    prediction: (mySub['prediction'] as String?) ?? '',
                    confidence: PredictionConfidenceX.fromString(
                        mySub['confidence'] as String?),
                    correct: false,
                  );
            // If the round's results list already had me, keep it as-is
            // (the resolve RPC may have set points/rank). Otherwise,
            // append my synthesized result so the UI can find it.
            if (existing.isEmpty) {
              merged.add(PredictionRound(
                id: round.id,
                familyId: round.familyId,
                questionId: round.questionId,
                status: round.status,
                lockAt: round.lockAt,
                revealAt: round.revealAt,
                resolvedAt: round.resolvedAt,
                actualAnswer: round.actualAnswer,
                winnerUserIds: round.winnerUserIds,
                results: [...round.results, myResult],
                isLegendary: round.isLegendary,
                createdAt: round.createdAt,
                question: round.question,
              ));
            } else {
              merged.add(round);
            }
          }
          state = state.copyWith(recentResults: merged);
        } catch (e) {
          // Submissions fetch failed — still show the rounds without my
          // submissions merged in. The UI gracefully falls back to
          // "Your guess: —" for past rounds.
          debugPrint('[Prediction] fetchRecent (my submissions) error: $e');
          state = state.copyWith(recentResults: rounds);
        }
      } else {
        state = state.copyWith(recentResults: rounds);
      }
    } catch (e) { debugPrint('[Prediction] fetchRecent error: $e'); }
  }

  Future<void> _fetchLeaderboard() async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.from('prediction_leaderboard').select().eq('familyId', familyId).order('points', ascending: false);
      final entries = resp.map((e) => PredictionLeaderboardEntry.fromJson(e)).toList();
      // Step (locked-in expand): join family-member names so the card's
      // compact leaderboard teaser can show "Manish" instead of
      // "a4e58129". Uses the existing fn_get_family_member_names helper
      // (SECURITY DEFINER, family-self-gated).
      final byUserId = <String, PredictionLeaderboardEntry>{};
      for (final e in entries) {
        byUserId[e.userId] = e;
      }
      try {
        final namesResp =
            await client.rpc('fn_get_family_member_names', params: {'family_id': familyId});
        if (namesResp is List) {
          final namesByUserId = <String, String>{};
          for (final row in namesResp) {
            if (row is Map) {
              final uid = row['userId'] as String?;
              final name = row['name'] as String?;
              if (uid != null && name != null && name.isNotEmpty) {
                namesByUserId[uid] = name;
              }
            }
          }
          if (namesByUserId.isNotEmpty) {
            for (var i = 0; i < entries.length; i++) {
              final e = entries[i];
              final name = namesByUserId[e.userId];
              if (name != null) {
                entries[i] = e.copyWithUserName(name);
              }
            }
          }
        }
      } catch (e) {
        // Names fetch failed — leaderboard still works, just shows
        // truncated userIds as before.
        debugPrint('[Prediction] fetchLeaderboard (names) error: $e');
      }
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

    // Tier 1 #1 — register with the central registry.
    final registry = _ref.read(realtimeChannelRegistryProvider);
    registry.register(
      'prediction_battle:$familyId',
      _channel!,
      _subscribeToRealtime,
      isLiveGame: false,
    );
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
  void dispose() {
    final registry = _ref.read(realtimeChannelRegistryProvider);
    registry.unregister('prediction_battle:$familyId');
    _channel?.unsubscribe(); _tickTimer?.cancel(); super.dispose();
  }
}

final predictionProvider = StateNotifierProvider.autoDispose.family<PredictionNotifier, PredictionState, String>(
  (ref, familyId) => PredictionNotifier(ref, familyId),
);
