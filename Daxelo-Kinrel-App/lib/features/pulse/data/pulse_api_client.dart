// lib/features/pulse/data/pulse_api_client.dart
//
// DAXELO KINREL — Pulse + Pitru + Addictiveness API client
//
// Wraps the Dio HTTP client (dioProvider) with typed methods for all the new
// backend endpoints. All methods return parsed models from pulse_models.dart.
//
// Endpoints covered:
//   Pulse:    /pulse/today, /pulse/today/generate, /pulse/history, /pulse/:date,
//             /pulse/items/:id/interact, /pulse/weather, /pulse/streaks, /pulse/karma
//   Pitru:    /pitru/memories, /pitru/memories/:id, /pitru/memories/:id/listen,
//             /pitru/memorial/:personId, /pitru/memorial/:personId/feed, /pitru/memorials
//   A-6:      /addictiveness/festivals/upcoming, /addictiveness/festivals/today
//   A-1:      /addictiveness/blessings, /addictiveness/blessings/for-me
//   A-2:      /addictiveness/time-capsules, /addictiveness/time-capsules/for-me
//   A-3:      /addictiveness/quests/active, /addictiveness/quests/history
//   A-4:      /addictiveness/alarms
//   A-7:      /addictiveness/chronicle

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';
import 'pulse_models.dart';

/// Provider for the PulseApiClient — injects the global Dio client.
final pulseApiClientProvider = Provider<PulseApiClient>((ref) {
  return PulseApiClient(ref.read(dioProvider));
});

class PulseApiClient {
  final Dio _dio;
  PulseApiClient(this._dio);

  // ────────────────────────────────────────────────────────────────────────
  // PULSE — Daily Brief
  // ────────────────────────────────────────────────────────────────────────

  /// Get today's brief. Returns null if not generated yet.
  Future<DailyBrief?> getTodayBrief() async {
    try {
      final r = await _dio.get('/api/pulse/today');
      if (r.statusCode == 200) {
        return DailyBrief.fromJson(r.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Generate today's brief on-demand (lazy generation before 7am cron).
  Future<DailyBrief> generateTodayBrief() async {
    final r = await _dio.post('/api/pulse/today/generate');
    return DailyBrief.fromJson(r.data as Map<String, dynamic>);
  }

  /// Get brief history (last N days).
  Future<List<DailyBrief>> getBriefHistory({int days = 30, int limit = 30}) async {
    final r = await _dio.get('/api/pulse/history', queryParameters: {'days': days, 'limit': limit});
    final list = (r.data as List?) ?? [];
    return list.map((e) => DailyBrief.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get a specific date's brief.
  Future<DailyBrief?> getBriefByDate(String dateStr) async {
    try {
      final r = await _dio.get('/api/pulse/$dateStr');
      if (r.statusCode == 200) {
        return DailyBrief.fromJson(r.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Mark a brief as viewed.
  Future<void> markBriefViewed(String briefId) async {
    await _dio.post('/api/pulse/briefs/$briefId/view');
  }

  /// Record an interaction on a brief item (call/message/view/dismiss/skip).
  Future<InteractionResult> recordInteraction(
    String briefItemId,
    String interactionType, {
    Map<String, dynamic>? data,
  }) async {
    final r = await _dio.post(
      '/api/pulse/items/$briefItemId/interact',
      data: {'interactionType': interactionType, 'data': data ?? {}},
    );
    return InteractionResult.fromJson(r.data as Map<String, dynamic>);
  }

  /// Get all relationship weather rows for the user.
  Future<List<RelationshipWeather>> getWeather() async {
    final r = await _dio.get('/api/pulse/weather');
    final list = (r.data as List?) ?? [];
    return list.map((e) => RelationshipWeather.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get all connection streaks for the user.
  Future<List<ConnectionStreak>> getStreaks() async {
    final r = await _dio.get('/api/pulse/streaks');
    final list = (r.data as List?) ?? [];
    return list.map((e) => ConnectionStreak.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get all FamilyKarma rows for the user (one per family).
  Future<List<FamilyKarma>> getKarma() async {
    final r = await _dio.get('/api/pulse/karma');
    final list = (r.data as List?) ?? [];
    return list.map((e) => FamilyKarma.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ────────────────────────────────────────────────────────────────────────
  // PITRU — Ancestral Memories
  // ────────────────────────────────────────────────────────────────────────

  Future<List<AncestralMemory>> listMemories(String familyId, {String? status, int limit = 50}) async {
    final r = await _dio.get('/api/pitru/memories', queryParameters: {
      'familyId': familyId,
      if (status != null) 'status': status,
      'limit': limit,
    });
    final list = (r.data as List?) ?? [];
    return list.map((e) => AncestralMemory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AncestralMemory> getMemory(String memoryId) async {
    final r = await _dio.get('/api/pitru/memories/$memoryId');
    return AncestralMemory.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> incrementMemoryListen(String memoryId) async {
    await _dio.post('/api/pitru/memories/$memoryId/listen');
  }

  // ────────────────────────────────────────────────────────────────────────
  // PITRU — Memorial
  // ────────────────────────────────────────────────────────────────────────

  Future<MemorialProfile> getMemorial(String personId) async {
    final r = await _dio.get('/api/pitru/memorial/$personId');
    return MemorialProfile.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getMemorialFeed(String personId) async {
    final r = await _dio.get('/api/pitru/memorial/$personId/feed');
    return r.data as Map<String, dynamic>;
  }

  Future<List<MemorialProfile>> listMemorials(String familyId) async {
    final r = await _dio.get('/api/pitru/memorials', queryParameters: {'familyId': familyId});
    final list = (r.data as List?) ?? [];
    return list.map((e) => MemorialProfile.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-6 Festival Intelligence
  // ────────────────────────────────────────────────────────────────────────

  Future<List<Festival>> getUpcomingFestivals({int days = 90, String? region}) async {
    final r = await _dio.get('/api/addictiveness/festivals/upcoming', queryParameters: {
      'days': days,
      if (region != null) 'region': region,
    });
    final list = (r.data as List?) ?? [];
    return list.map((e) => Festival.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Festival>> getFestivalsToday() async {
    final r = await _dio.get('/api/addictiveness/festivals/today');
    final list = (r.data as List?) ?? [];
    return list.map((e) => Festival.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-1 Blessing Chain
  // ────────────────────────────────────────────────────────────────────────

  Future<List<BlessingChain>> listBlessings(String familyId, {String? status}) async {
    final r = await _dio.get('/api/addictiveness/blessings', queryParameters: {
      'familyId': familyId,
      if (status != null) 'status': status,
    });
    final list = (r.data as List?) ?? [];
    return list.map((e) => BlessingChain.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<BlessingChain>> getBlessingsForMe() async {
    final r = await _dio.get('/api/addictiveness/blessings/for-me');
    final list = (r.data as List?) ?? [];
    return list.map((e) => BlessingChain.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BlessingChain> createBlessing(Map<String, dynamic> body) async {
    final r = await _dio.post('/api/addictiveness/blessings', data: body);
    return BlessingChain.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> markBlessingViewed(String blessingId) async {
    await _dio.post('/api/addictiveness/blessings/$blessingId/view');
  }

  Future<void> cancelBlessing(String blessingId, {String? reason}) async {
    await _dio.post('/api/addictiveness/blessings/$blessingId/cancel', data: {'reason': reason});
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-2 Time Capsule
  // ────────────────────────────────────────────────────────────────────────

  Future<List<TimeCapsule>> listTimeCapsules(String familyId, {String? status}) async {
    final r = await _dio.get('/api/addictiveness/time-capsules', queryParameters: {
      'familyId': familyId,
      if (status != null) 'status': status,
    });
    final list = (r.data as List?) ?? [];
    return list.map((e) => TimeCapsule.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<TimeCapsule>> getTimeCapsulesForMe() async {
    final r = await _dio.get('/api/addictiveness/time-capsules/for-me');
    final list = (r.data as List?) ?? [];
    return list.map((e) => TimeCapsule.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TimeCapsule> createTimeCapsule(Map<String, dynamic> body) async {
    final r = await _dio.post('/api/addictiveness/time-capsules', data: body);
    return TimeCapsule.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> markCapsuleViewed(String capsuleId) async {
    await _dio.post('/api/addictiveness/time-capsules/$capsuleId/view');
  }

  Future<void> cancelCapsule(String capsuleId) async {
    await _dio.post('/api/addictiveness/time-capsules/$capsuleId/cancel');
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-3 Family Quests
  // ────────────────────────────────────────────────────────────────────────

  Future<List<FamilyQuest>> getActiveQuests() async {
    final r = await _dio.get('/api/addictiveness/quests/active');
    final list = (r.data as List?) ?? [];
    return list.map((e) => FamilyQuest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<FamilyQuest>> getQuestHistory({int limit = 20}) async {
    final r = await _dio.get('/api/addictiveness/quests/history', queryParameters: {'limit': limit});
    final list = (r.data as List?) ?? [];
    return list.map((e) => FamilyQuest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<InteractionResult> completeQuest(String questId) async {
    final r = await _dio.post('/api/addictiveness/quests/$questId/complete');
    return InteractionResult.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> skipQuest(String questId) async {
    await _dio.post('/api/addictiveness/quests/$questId/skip');
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-4 Silent Alarms
  // ────────────────────────────────────────────────────────────────────────

  Future<List<SilentAlarm>> getAlarms() async {
    final r = await _dio.get('/api/addictiveness/alarms');
    final list = (r.data as List?) ?? [];
    return list.map((e) => SilentAlarm.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> acknowledgeAlarm(String alarmId) async {
    await _dio.post('/api/addictiveness/alarms/$alarmId/acknowledge');
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-7 Family Chronicle
  // ────────────────────────────────────────────────────────────────────────

  Future<FamilyChronicle?> getChronicle(String familyId) async {
    try {
      final r = await _dio.get('/api/addictiveness/chronicle', queryParameters: {'familyId': familyId});
      if (r.statusCode == 200 && r.data != null) {
        return FamilyChronicle.fromJson(r.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generateChronicle(String familyId) async {
    final r = await _dio.post('/api/addictiveness/chronicle/generate', queryParameters: {'familyId': familyId});
    return r.data as Map<String, dynamic>;
  }
}
