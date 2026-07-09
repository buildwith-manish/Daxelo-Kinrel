// =============================================================================
// Track C v2.0 — Riverpod Providers
// =============================================================================
// Wires up the TrackcDatabase, TrackcApiClient, and TrackcSyncEngine as
// Riverpod providers. Also exposes feature-specific providers for the UI.
// =============================================================================

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../data/api/trackc_api_client.dart';
import '../../data/database/trackc_database.dart';
import '../../data/sync/trackc_sync_engine.dart';

// ── Database (singleton) ─────────────────────────────────────────────────────

final trackcDatabaseProvider = Provider<TrackcDatabase>((ref) {
  final db = TrackcDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── Device ID (generated once, persisted) ────────────────────────────────────

final deviceIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('trackc_device_id');
  if (id == null) {
    // Generate a simple unique ID (not cryptographically strong; sufficient for sync)
    id = 'dev_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
    await prefs.setString('trackc_device_id', id);
  }
  return id;
});

// ── API client (uses Supabase auth token) ────────────────────────────────────

final trackcApiClientProvider = Provider<TrackcApiClient>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
  ));
  ref.onDispose(dio.close);
  return TrackcApiClient(dio);
});

// ── Sync engine (per-user) ───────────────────────────────────────────────────

final trackcSyncEngineProvider = Provider<TrackcSyncEngine?>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  final deviceId = ref.watch(deviceIdProvider).maybeWhen(data: (d) => d, orElse: () => null);
  if (deviceId == null) return null;

  final engine = TrackcSyncEngine(
    db: ref.watch(trackcDatabaseProvider),
    api: ref.watch(trackcApiClientProvider),
    userId: user.id,
    deviceId: deviceId,
  );
  ref.onDispose(engine.dispose);
  return engine;
});

// ── Selected family (the user can be in multiple families) ──────────────────

final selectedFamilyIdProvider = StateProvider<String?>((ref) => null);

// ── Constitution ─────────────────────────────────────────────────────────────

final constitutionProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  if (familyId == null) return null;
  final api = ref.watch(trackcApiClientProvider);
  try {
    return await api.getConstitution(familyId);
  } catch (e) {
    return null;
  }
});

// ── Decisions ────────────────────────────────────────────────────────────────

final decisionsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String?>((ref, status) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  if (familyId == null) return [];
  final api = ref.watch(trackcApiClientProvider);
  try {
    final result = await api.listDecisions(familyId, status: status);
    return (result['items'] as List).cast<Map<String, dynamic>>();
  } catch (e) {
    return [];
  }
});

final decisionDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, decisionId) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  if (familyId == null) return null;
  final api = ref.watch(trackcApiClientProvider);
  try {
    return await api.getDecision(familyId, decisionId);
  } catch (e) {
    return null;
  }
});

// ── Timeline ─────────────────────────────────────────────────────────────────

final timelineProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String?>((ref, kind) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  if (familyId == null) return [];
  final api = ref.watch(trackcApiClientProvider);
  try {
    final result = await api.listTimeline(familyId, kind: kind);
    return (result['items'] as List).cast<Map<String, dynamic>>();
  } catch (e) {
    return [];
  }
});

// ── Insights ─────────────────────────────────────────────────────────────────

final insightsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, decisionId) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  if (familyId == null) return [];
  final api = ref.watch(trackcApiClientProvider);
  try {
    final result = await api.listInsights(familyId, decisionId);
    return result.cast<Map<String, dynamic>>();
  } catch (e) {
    return [];
  }
});

// ── Learning Profile ─────────────────────────────────────────────────────────

final learningProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  if (familyId == null) return null;
  final api = ref.watch(trackcApiClientProvider);
  try {
    return await api.getLearningProfile(familyId);
  } catch (e) {
    return null;
  }
});

// ── Analytics Summary ────────────────────────────────────────────────────────

final analyticsSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  if (familyId == null) return null;
  final api = ref.watch(trackcApiClientProvider);
  try {
    return await api.getAnalyticsSummary(familyId);
  } catch (e) {
    return null;
  }
});

// ── Search ───────────────────────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');
final searchResultsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final familyId = ref.watch(selectedFamilyIdProvider);
  final query = ref.watch(searchQueryProvider);
  if (familyId == null || query.trim().isEmpty) return null;
  final api = ref.watch(trackcApiClientProvider);
  try {
    return await api.search(familyId, query);
  } catch (e) {
    return null;
  }
});
