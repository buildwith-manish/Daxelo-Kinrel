// lib/features/truth_streak/providers/truth_streak_provider.dart
//
// DAXELO KINREL — Truth Streak Provider
//
// Manages the daily family question game: fetches today's assignment,
// submits answers, tracks streaks, and reveals answers after the user
// has answered.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../models/truth_streak_models.dart';

// ── State ──────────────────────────────────────────────────────────

class TruthStreakState {
  const TruthStreakState({
    this.assignment,
    this.myAnswer,
    this.allAnswers = const [],
    this.stats,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  final TruthStreakAssignment? assignment;
  final TruthStreakAnswer? myAnswer;
  final List<TruthStreakAnswer> allAnswers;
  final TruthStreakStats? stats;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  bool get hasAnswered => myAnswer != null;
  int get answerCount => allAnswers.length;

  TruthStreakState copyWith({
    TruthStreakAssignment? assignment,
    TruthStreakAnswer? myAnswer,
    List<TruthStreakAnswer>? allAnswers,
    TruthStreakStats? stats,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return TruthStreakState(
      assignment: assignment ?? this.assignment,
      myAnswer: myAnswer ?? this.myAnswer,
      allAnswers: allAnswers ?? this.allAnswers,
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────

class TruthStreakNotifier extends StateNotifier<TruthStreakState> {
  TruthStreakNotifier(this._ref, this.familyId)
      : super(const TruthStreakState(isLoading: true)) {
    // Subscribe to realtime changes on truth_streak_answers so new answers
    // from other family members appear automatically without a manual refresh.
    _subscribeToRealtime();
  }

  final Ref _ref;
  final String familyId;
  RealtimeChannel? _channel;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myUserId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ??
      _client?.auth.currentUser?.userMetadata?['full_name'] as String? ??
      'Member';
  String? get _myAvatar =>
      _client?.auth.currentUser?.userMetadata?['avatar_url'] as String?;

  void _subscribeToRealtime() {
    final client = _client;
    if (client == null) return;

    _channel = client.channel('truth_streak_answers:$familyId');
    _channel!.on(
      'postgres_changes',
      payload: {
        'event': 'INSERT',
        'schema': 'public',
        'table': 'truth_streak_answers',
        'filter': 'familyId=eq.$familyId',
      },
      (payload) {
        debugPrint('📨 Truth Streak: new answer received via realtime');
        load();
      },
    );
    _channel!.subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  /// Load today's assignment, the user's answer, all answers, and stats.
  Future<void> load() async {
    final client = _client;
    final myId = _myUserId;
    if (client == null || myId == null) {
      state = state.copyWith(isLoading: false, error: 'Not signed in');
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // 1. Fetch or create today's assignment
      var assignmentResponse = await client
          .from('truth_streak_daily_assignments')
          .select()
          .eq('familyId', familyId)
          .eq('assignedDate', todayStr)
          .limit(1);

      Map<String, dynamic>? assignmentRow;
      if (assignmentResponse.isNotEmpty) {
        assignmentRow = assignmentResponse.first as Map<String, dynamic>;
      } else {
        // Create today's assignment — pick a random active question
        final questionsResponse = await client
            .from('truth_streak_questions')
            .select()
            .eq('isActive', true);

        if (questionsResponse.isEmpty) {
          state = state.copyWith(
            isLoading: false,
            error: 'No questions available',
          );
          return;
        }

        final random = DateTime.now().millisecondsSinceEpoch;
        final questionRow =
            questionsResponse[random % questionsResponse.length]
                as Map<String, dynamic>;
        final questionId = questionRow['id'] as String;

        final newAssignment = await client
            .from('truth_streak_daily_assignments')
            .insert({
              'familyId': familyId,
              'questionId': questionId,
              'assignedDate': todayStr,
            })
            .select()
            .single();
        assignmentRow = newAssignment as Map<String, dynamic>;
      }

      final assignment = TruthStreakAssignment.fromJson(assignmentRow);

      // 2. Fetch the question text
      final questionResponse = await client
          .from('truth_streak_questions')
          .select()
          .eq('id', assignment.questionId)
          .single();
      final question =
          TruthStreakQuestion.fromJson(questionResponse as Map<String, dynamic>);

      final fullAssignment = TruthStreakAssignment(
        id: assignment.id,
        familyId: assignment.familyId,
        questionId: assignment.questionId,
        assignedDate: assignment.assignedDate,
        question: question,
      );

      // 3. Fetch all answers for this assignment
      final answersResponse = await client
          .from('truth_streak_answers')
          .select()
          .eq('assignmentId', assignment.id)
          .order('createdAt', ascending: true);

      final allAnswers = answersResponse
          .map((e) => TruthStreakAnswer.fromJson(e as Map<String, dynamic>))
          .toList();
      final myAnswer = allAnswers
          .where((a) => a.userId == myId)
          .firstOrNull;

      // 4. Fetch user stats
      final statsResponse = await client
          .from('truth_streak_user_stats')
          .select()
          .eq('userId', myId)
          .eq('familyId', familyId)
          .maybeSingle();
      final stats = statsResponse != null
          ? TruthStreakStats.fromJson(statsResponse as Map<String, dynamic>)
          : null;

      state = TruthStreakState(
        assignment: fullAssignment,
        myAnswer: myAnswer,
        allAnswers: allAnswers,
        stats: stats,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('⚠️ TruthStreak load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  /// Submit an answer to today's question.
  Future<bool> submitAnswer(String answerText) async {
    final client = _client;
    final myId = _myUserId;
    if (client == null || myId == null) return false;
    final assignment = state.assignment;
    if (assignment == null) return false;

    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      // 1. Insert the answer
      final answerRow = await client
          .from('truth_streak_answers')
          .insert({
            'assignmentId': assignment.id,
            'userId': myId,
            'userName': _myName,
            'userAvatarUrl': _myAvatar,
            'answer': answerText,
          })
          .select()
          .single();
      final newAnswer =
          TruthStreakAnswer.fromJson(answerRow as Map<String, dynamic>);

      // 2. Update streak stats
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final yesterday = todayDate.subtract(const Duration(days: 1));

      final existingStats = state.stats;
      int newCurrentStreak;
      int newLongestStreak;

      if (existingStats?.lastAnsweredDate != null) {
        final lastDate = DateTime(
          existingStats!.lastAnsweredDate!.year,
          existingStats.lastAnsweredDate!.month,
          existingStats.lastAnsweredDate!.day,
        );
        if (lastDate == yesterday) {
          // Consecutive day — increment streak
          newCurrentStreak = existingStats.currentStreak + 1;
        } else if (lastDate == todayDate) {
          // Already answered today (shouldn't happen, but guard)
          newCurrentStreak = existingStats.currentStreak;
        } else {
          // Streak broken — reset to 1
          newCurrentStreak = 1;
        }
        newLongestStreak =
            newCurrentStreak > existingStats.longestStreak
                ? newCurrentStreak
                : existingStats.longestStreak;
      } else {
        // First ever answer
        newCurrentStreak = 1;
        newLongestStreak = 1;
      }

      // Upsert stats
      if (existingStats != null) {
        await client.from('truth_streak_user_stats').update({
          'currentStreak': newCurrentStreak,
          'longestStreak': newLongestStreak,
          'lastAnsweredDate': todayDate.toIso8601String().split('T')[0],
          'updatedAt': DateTime.now().toIso8601String(),
        }).eq('userId', myId).eq('familyId', familyId);
      } else {
        await client.from('truth_streak_user_stats').insert({
          'userId': myId,
          'familyId': familyId,
          'currentStreak': newCurrentStreak,
          'longestStreak': newLongestStreak,
          'lastAnsweredDate': todayDate.toIso8601String().split('T')[0],
        });
      }

      // 3. Refresh all answers (to include the new one)
      final answersResponse = await client
          .from('truth_streak_answers')
          .select()
          .eq('assignmentId', assignment.id)
          .order('createdAt', ascending: true);
      final allAnswers = answersResponse
          .map((e) => TruthStreakAnswer.fromJson(e as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        myAnswer: newAnswer,
        allAnswers: allAnswers,
        stats: TruthStreakStats(
          userId: myId,
          familyId: familyId,
          currentStreak: newCurrentStreak,
          longestStreak: newLongestStreak,
          lastAnsweredDate: todayDate,
        ),
        isSubmitting: false,
      );

      return true;
    } catch (e) {
      debugPrint('⚠️ TruthStreak submit error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────

final truthStreakProvider =
    StateNotifierProvider.autoDispose.family<TruthStreakNotifier, TruthStreakState, String>(
  (ref, familyId) => TruthStreakNotifier(ref, familyId),
);
