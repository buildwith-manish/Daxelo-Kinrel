import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class RiddleOption {
  final String text;
  final bool isCorrect;
  const RiddleOption(this.text, this.isCorrect);
}

class RelationRiddleState {
  const RelationRiddleState({this.riddleId, this.personAName, this.personBName, this.options = const [], this.myAnswer, this.wasCorrect, this.isLoading = false, this.isSubmitting = false, this.error});
  final String? riddleId;
  final String? personAName;
  final String? personBName;
  final List<RiddleOption> options;
  final String? myAnswer;
  final bool? wasCorrect;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  bool get hasAnswered => myAnswer != null;

  RelationRiddleState copyWith({String? riddleId, String? personAName, String? personBName, List<RiddleOption>? options, String? myAnswer, bool? wasCorrect, bool? isLoading, bool? isSubmitting, String? error, bool clearError = false}) =>
    RelationRiddleState(riddleId: riddleId ?? this.riddleId, personAName: personAName ?? this.personAName, personBName: personBName ?? this.personBName,
      options: options ?? this.options, myAnswer: myAnswer ?? this.myAnswer, wasCorrect: wasCorrect ?? this.wasCorrect,
      isLoading: isLoading ?? this.isLoading, isSubmitting: isSubmitting ?? this.isSubmitting, error: clearError ? null : (error ?? this.error));
}

class RelationRiddleNotifier extends StateNotifier<RelationRiddleState> {
  RelationRiddleNotifier(this._ref, this.familyId) : super(const RelationRiddleState(isLoading: true));
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;

  Future<void> load() async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(isLoading: false, error: 'Not signed in'); return; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';

      var riddleResp = await client.from('relation_riddle_daily').select().eq('"familyId"', familyId).eq('"assignedDate"', todayStr).limit(1);
      Map<String, dynamic>? riddleRow;
      if (riddleResp.isNotEmpty) {
        riddleRow = riddleResp.first as Map<String, dynamic>;
      } else {
        // Need at least 2 members to create a riddle
        final membersResp = await client.from('Person').select('id, name').eq('"familyId"', familyId).isFilter('"deletedAt"', null);
        if (membersResp.length < 2) { state = state.copyWith(isLoading: false); return; }

        final random = DateTime.now().millisecondsSinceEpoch;
        final personA = membersResp[random % membersResp.length] as Map<String, dynamic>;
        final personB = membersResp[(random + 1) % membersResp.length] as Map<String, dynamic>;
        final correctAnswer = 'Related (see graph for path)';

        // Generate plausible wrong answers
        const wrongOptions = ['Not related', 'Same generation', 'Married into family'];
        final shuffled = wrongOptions.toList()..shuffle();
        final newRiddle = await client.from('relation_riddle_daily').insert({
          '"familyId"': familyId, '"personAId"': personA['id'], '"personBId"': personB['id'],
          '"personAName"': personA['name'], '"personBName"': personB['name'],
          '"correctAnswer"': correctAnswer, '"option1"': shuffled[0], '"option2"': shuffled[1], '"option3"': shuffled[2],
          '"assignedDate"': todayStr,
        }).select().single();
        riddleRow = newRiddle as Map<String, dynamic>;
      }

      final riddleId = riddleRow['id'] as String;
      final options = [
        RiddleOption(riddleRow['correctAnswer'] as String, true),
        RiddleOption(riddleRow['option1'] as String, false),
        RiddleOption(riddleRow['option2'] as String, false),
        RiddleOption(riddleRow['option3'] as String, false),
      ]..shuffle();

      // Check if user already answered
      String? myAnswer; bool? wasCorrect;
      try {
        final attemptResp = await client.from('relation_riddle_attempts').select().eq('"riddleId"', riddleId).eq('"userId"', myId).maybeSingle();
        if (attemptResp != null) {
          myAnswer = attemptResp['selectedAnswer'] as String?;
          wasCorrect = attemptResp['wasCorrect'] as bool? ?? false;
        }
      } catch (_) {}

      state = RelationRiddleState(riddleId: riddleId, personAName: riddleRow['personAName'] as String?, personBName: riddleRow['personBName'] as String?, options: options, myAnswer: myAnswer, wasCorrect: wasCorrect, isLoading: false);
    } catch (e) {
      debugPrint('⚠️ RelationRiddle load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  Future<bool> submitAnswer(String selectedAnswer, bool isCorrect) async {
    final client = _client; final myId = _myId; final riddleId = state.riddleId;
    if (client == null || myId == null || riddleId == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await client.from('relation_riddle_attempts').insert({'"riddleId"': riddleId, '"userId"': myId, '"selectedAnswer"': selectedAnswer, '"wasCorrect"': isCorrect});
      state = state.copyWith(myAnswer: selectedAnswer, wasCorrect: isCorrect, isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }
}

final relationRiddleProvider =
    StateNotifierProvider.autoDispose.family<RelationRiddleNotifier, RelationRiddleState, String>(
  (ref, familyId) => RelationRiddleNotifier(ref, familyId),
);
