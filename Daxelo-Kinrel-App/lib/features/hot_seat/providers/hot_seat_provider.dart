import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class HotSeatQuestion {
  const HotSeatQuestion({required this.id, required this.askerId, required this.askerName, required this.question, this.answer, required this.createdAt});
  final String id;
  final String askerId;
  final String askerName;
  final String question;
  final String? answer;
  final DateTime createdAt;
  factory HotSeatQuestion.fromJson(Map<String, dynamic> json) => HotSeatQuestion(
    id: json['id'] ?? '', askerId: json['askerId'] ?? '', askerName: json['askerName'] ?? 'Member',
    question: json['question'] ?? '', answer: json['answer'] as String?, createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}

class HotSeatState {
  const HotSeatState({this.dailyId, this.seatHolderName, this.isMeInHotSeat = false, this.questions = const [], this.isLoading = false, this.isSubmitting = false, this.error});
  final String? dailyId;
  final String? seatHolderName;
  final bool isMeInHotSeat;
  final List<HotSeatQuestion> questions;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  HotSeatState copyWith({String? dailyId, String? seatHolderName, bool? isMeInHotSeat, List<HotSeatQuestion>? questions, bool? isLoading, bool? isSubmitting, String? error, bool clearError = false}) =>
    HotSeatState(dailyId: dailyId ?? this.dailyId, seatHolderName: seatHolderName ?? this.seatHolderName,
      isMeInHotSeat: isMeInHotSeat ?? this.isMeInHotSeat, questions: questions ?? this.questions,
      isLoading: isLoading ?? this.isLoading, isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error));
}

class HotSeatNotifier extends StateNotifier<HotSeatState> {
  HotSeatNotifier(this._ref, this.familyId) : super(const HotSeatState(isLoading: true));
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Member';

  Future<void> load() async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(isLoading: false, error: 'Not signed in'); return; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';

      var dailyResp = await client.from('hot_seat_daily').select().eq('"familyId"', familyId).eq('"assignedDate"', todayStr).limit(1);
      Map<String, dynamic>? dailyRow;
      if (dailyResp.isNotEmpty) {
        dailyRow = dailyResp.first as Map<String, dynamic>;
      } else {
        // Pick a random family member for the hot seat
        final membersResp = await client.from('Person').select('id, name').eq('"familyId"', familyId).isFilter('"deletedAt"', null);
        if (membersResp.isEmpty) { state = state.copyWith(isLoading: false); return; }
        final random = DateTime.now().millisecondsSinceEpoch;
        final chosen = membersResp[random % membersResp.length] as Map<String, dynamic>;
        final newDaily = await client.from('hot_seat_daily').insert({'"familyId"': familyId, '"userId"': chosen['id'], '"userName"': chosen['name'], '"assignedDate"': todayStr}).select().single();
        dailyRow = newDaily as Map<String, dynamic>;
      }

      final dailyId = dailyRow['id'] as String;
      final seatHolderName = dailyRow['userName'] as String? ?? 'Member';
      final seatHolderId = dailyRow['userId'] as String? ?? '';
      final isMe = seatHolderId == myId;

      // Fetch questions + answers
      final questionsResp = await client.from('hot_seat_questions').select().eq('"assignmentId"', dailyId).order('"createdAt"', ascending: true);
      final questions = <HotSeatQuestion>[];
      for (final q in questionsResp) {
        final qMap = q as Map<String, dynamic>;
        String? answer;
        try {
          final ansResp = await client.from('hot_seat_answers').select('answer').eq('"questionId"', qMap['id']).maybeSingle();
          if (ansResp != null) answer = ansResp['answer'] as String?;
        } catch (_) {}
        questions.add(HotSeatQuestion.fromJson(qMap).copyWith(answer: answer));
      }

      state = HotSeatState(dailyId: dailyId, seatHolderName: seatHolderName, isMeInHotSeat: isMe, questions: questions, isLoading: false);
    } catch (e) {
      debugPrint('⚠️ HotSeat load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  Future<bool> submitQuestion(String text) async {
    final client = _client; final myId = _myId; final dailyId = state.dailyId;
    if (client == null || myId == null || dailyId == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await client.from('hot_seat_questions').insert({'"assignmentId"': dailyId, '"askerId"': myId, '"askerName"': _myName, 'question': text});
      await load(); // refresh
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  Future<bool> submitAnswer(String questionId, String answerText) async {
    final client = _client;
    if (client == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await client.from('hot_seat_answers').insert({'"questionId"': questionId, 'answer': answerText});
      await load();
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }
}

final hotSeatProvider =
    StateNotifierProvider.autoDispose.family<HotSeatNotifier, HotSeatState, String>(
  (ref, familyId) => HotSeatNotifier(ref, familyId),
);
