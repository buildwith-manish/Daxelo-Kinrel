// =============================================================================
// Track C v2.0 — AURA Governance Engine — Flutter API Client
// =============================================================================
// Thin typed wrapper around Dio for the Track C REST endpoints.
// Section 6 of the FINAL v2.0 spec.
// =============================================================================

import 'package:dio/dio.dart';

class TrackcApiClient {
  TrackcApiClient(this._dio);

  final Dio _dio;

  // ── Constitution ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getConstitution(String familyId) async {
    final r = await _dio.get('/api/v1/families/$familyId/constitution');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveConstitutionDraft(
    String familyId,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post('/api/v1/families/$familyId/constitution/draft', data: body);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> publishConstitution(
    String familyId,
    String? changeSummary,
  ) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/constitution/publish',
      data: {'changeSummary': changeSummary},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> listConstitutionVersions(String familyId) async {
    final r = await _dio.get('/api/v1/families/$familyId/constitution/versions');
    return r.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> openAmendment(
    String familyId,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post('/api/v1/families/$familyId/constitution/amend', data: body);
    return r.data as Map<String, dynamic>;
  }

  // ── Decisions ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> listDecisions(
    String familyId, {
    String? status,
    String? lifecycleState,
    String? cursor,
    int limit = 50,
  }) async {
    final qs = <String, dynamic>{'limit': limit};
    if (status != null) qs['status'] = status;
    if (lifecycleState != null) qs['lifecycleState'] = lifecycleState;
    if (cursor != null) qs['cursor'] = cursor;
    final r = await _dio.get(
      '/api/v1/families/$familyId/decisions',
      queryParameters: qs,
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createDecision(
    String familyId,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post('/api/v1/families/$familyId/decisions', data: body);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDecision(String familyId, String decisionId) async {
    final r = await _dio.get('/api/v1/families/$familyId/decisions/$decisionId');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> vote(
    String familyId,
    String decisionId,
    String option,
  ) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/decisions/$decisionId/vote',
      data: {'option': option},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resolveDecision(
    String familyId,
    String decisionId, {
    String? resolutionNote,
  }) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/decisions/$decisionId/resolve',
      data: {'resolutionNote': resolutionNote},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelDecision(String familyId, String decisionId) async {
    final r = await _dio.post('/api/v1/families/$familyId/decisions/$decisionId/cancel');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> transitionLifecycle(
    String familyId,
    String decisionId,
    String to,
  ) async {
    final r = await _dio.patch(
      '/api/v1/families/$familyId/decisions/$decisionId/lifecycle',
      data: {'to': to},
    );
    return r.data as Map<String, dynamic>;
  }

  // ── Memory + Impact ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getMemory(String familyId, String decisionId) async {
    final r = await _dio.get('/api/v1/families/$familyId/decisions/$decisionId/memory');
    return r.data as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> upsertMemory(
    String familyId,
    String decisionId,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/decisions/$decisionId/memory',
      data: body,
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addImpact(
    String familyId,
    String decisionId,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/decisions/$decisionId/impacts',
      data: body,
    );
    return r.data as Map<String, dynamic>;
  }

  // ── Timeline ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> listTimeline(
    String familyId, {
    String? kind,
    String? cursor,
    int limit = 50,
  }) async {
    final qs = <String, dynamic>{'limit': limit};
    if (kind != null) qs['kind'] = kind;
    if (cursor != null) qs['cursor'] = cursor;
    final r = await _dio.get(
      '/api/v1/families/$familyId/timeline',
      queryParameters: qs,
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> correctTimelineEvent(
    String familyId,
    String eventId,
    Map<String, dynamic> correctedFields, {
    String? note,
  }) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/timeline/$eventId/correct',
      data: {'correctedFields': correctedFields, 'note': note},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<String> exportTimelineHtml(String familyId, {int? year}) async {
    final qs = <String, dynamic>{'format': 'pdf'};
    if (year != null) qs['year'] = year;
    final r = await _dio.get(
      '/api/v1/families/$familyId/timeline/export',
      queryParameters: qs,
      options: Options(responseType: ResponseType.plain),
    );
    return r.data as String;
  }

  // ── AURA Intelligence ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> requestInsights(
    String familyId,
    String decisionId,
    List<String> kinds,
  ) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/decisions/$decisionId/insights/request',
      data: {'kinds': kinds},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> listInsights(
    String familyId,
    String decisionId, {
    String? kind,
  }) async {
    final qs = <String, dynamic>{};
    if (kind != null) qs['kind'] = kind;
    final r = await _dio.get(
      '/api/v1/families/$familyId/decisions/$decisionId/insights',
      queryParameters: qs,
    );
    return r.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> acceptInsight(String insightId, String familyId) async {
    final r = await _dio.post(
      '/api/v1/insights/$insightId/accept',
      data: {'familyId': familyId},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> dismissInsight(
    String insightId,
    String familyId,
    String reason,
  ) async {
    final r = await _dio.post(
      '/api/v1/insights/$insightId/dismiss',
      data: {'familyId': familyId, 'reason': reason},
    );
    return r.data as Map<String, dynamic>;
  }

  // ── AURA Learning ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getLearningProfile(String familyId) async {
    final r = await _dio.get('/api/v1/families/$familyId/learning/profile');
    return r.data as Map<String, dynamic>;
  }

  /// Plain-language summary of the learning profile — available to ALL
  /// members (including minors). Returns a pre-templated sentence, never
  /// raw signal fields.
  Future<Map<String, dynamic>> getLearningProfileSummary(String familyId) async {
    final r = await _dio.get('/api/v1/families/$familyId/learning/profile/summary');
    return r.data as Map<String, dynamic>;
  }

  Future<void> resetLearningProfile(String familyId, {String reason = 'user_request'}) async {
    await _dio.post(
      '/api/v1/families/$familyId/learning/reset',
      data: {'reason': reason},
    );
  }

  // ── AURA Search ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> search(
    String familyId,
    String query, {
    String? entityType,
    int limit = 20,
  }) async {
    final qs = <String, dynamic>{'q': query, 'limit': limit};
    if (entityType != null) qs['entityType'] = entityType;
    final r = await _dio.get(
      '/api/v1/families/$familyId/search',
      queryParameters: qs,
    );
    return r.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> searchSuggest(String familyId, String q) async {
    final r = await _dio.get(
      '/api/v1/families/$familyId/search/suggest',
      queryParameters: {'q': q},
    );
    return (r.data as Map<String, dynamic>)['suggestions'] as List<dynamic>;
  }

  // ── AURA Secretary ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createArtifact(
    String familyId,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/secretary/artifacts',
      data: body,
    );
    return r.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> listArtifacts(String familyId, {String? status}) async {
    final qs = <String, dynamic>{};
    if (status != null) qs['status'] = status;
    final r = await _dio.get(
      '/api/v1/families/$familyId/secretary/artifacts',
      queryParameters: qs,
    );
    return r.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> publishArtifact(
    String familyId,
    String artifactId, {
    String? finalMinutesMd,
  }) async {
    final r = await _dio.post(
      '/api/v1/families/$familyId/secretary/artifacts/$artifactId/publish',
      data: {'finalMinutesMd': finalMinutesMd},
    );
    return r.data as Map<String, dynamic>;
  }

  // ── AURA Analytics ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAnalyticsSummary(
    String familyId, {
    String granularity = 'weekly',
  }) async {
    final r = await _dio.get(
      '/api/v1/families/$familyId/analytics/summary',
      queryParameters: {'granularity': granularity},
    );
    return r.data as Map<String, dynamic>;
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDelta({
    required String deviceId,
    String? since,
    List<String>? families,
    int limit = 500,
  }) async {
    final qs = <String, dynamic>{'limit': limit};
    if (since != null) qs['since'] = since;
    if (families != null && families.isNotEmpty) qs['families'] = families.join(',');
    final r = await _dio.get(
      '/api/v1/sync/delta',
      queryParameters: qs,
      options: Options(headers: {'X-Device-Id': deviceId}),
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pushOperations(List<Map<String, dynamic>> operations) async {
    final r = await _dio.post(
      '/api/v1/sync/push',
      data: {'operations': operations},
    );
    return r.data as Map<String, dynamic>;
  }
}
