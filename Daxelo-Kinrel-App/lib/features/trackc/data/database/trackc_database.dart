// =============================================================================
// Track C v2.0 — AURA Governance Engine — Flutter Drift Database
// =============================================================================
// Wraps the Track C tables into a separate Drift database. Keeping it
// separate from the main AppDatabase avoids regenerating the existing
// generated file (which is large and well-tested).
// =============================================================================

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'trackc_tables.dart';

part 'trackc_database.g.dart';

@DriftDatabase(tables: [
  TrackcConstitutions,
  TrackcConstitutionVersions,
  TrackcConstitutionArticles,
  TrackcConstitutionClauses,
  TrackcDecisions,
  TrackcDecisionVotes,
  TrackcTimelineEvents,
  TrackcDecisionMemories,
  TrackcDecisionImpacts,
  TrackcMeetingArtifacts,
  TrackcAiInsights,
  TrackcBehaviorProfiles,
  TrackcSyncWatermarks,
  TrackcOutbox,
])
class TrackcDatabase extends _$TrackcDatabase {
  TrackcDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'trackc_governance');
  }

  // ── Constitution ──────────────────────────────────────────────────────────

  Future<List<TrackcConstitution>> getConstitutionsForFamily(String familyId) {
    return (select(trackcConstitutions)..where((t) => t.familyId.equals(familyId))).get();
  }

  Future<void> upsertConstitution(TrackcConstitutionsCompanion entry) {
    return into(trackcConstitutions).insertOnConflictUpdate(entry);
  }

  Future<void> upsertConstitutionVersion(TrackcConstitutionVersionsCompanion entry) {
    return into(trackcConstitutionVersions).insertOnConflictUpdate(entry);
  }

  Future<void> upsertArticle(TrackcConstitutionArticlesCompanion entry) {
    return into(trackcConstitutionArticles).insertOnConflictUpdate(entry);
  }

  Future<void> upsertClause(TrackcConstitutionClausesCompanion entry) {
    return into(trackcConstitutionClauses).insertOnConflictUpdate(entry);
  }

  Future<List<TrackcConstitutionArticle>> getArticlesForVersion(String versionId) {
    return (select(trackcConstitutionArticles)
          ..where((t) => t.versionId.equals(versionId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();
  }

  Future<List<TrackcConstitutionClause>> getClausesForArticle(String articleId) {
    return (select(trackcConstitutionClauses)
          ..where((t) => t.articleId.equals(articleId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();
  }

  // ── Decisions ─────────────────────────────────────────────────────────────

  Future<List<TrackcDecision>> getDecisionsForFamily(String familyId, {String? status}) {
    final q = select(trackcDecisions)..where((t) => t.familyId.equals(familyId));
    if (status != null) {
      q.where((t) => t.status.equals(status));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.get();
  }

  Stream<List<TrackcDecision>> watchDecisionsForFamily(String familyId, {String? status}) {
    final q = select(trackcDecisions)..where((t) => t.familyId.equals(familyId));
    if (status != null) {
      q.where((t) => t.status.equals(status));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.watch();
  }

  Future<TrackcDecision?> getDecision(String decisionId) {
    return (select(trackcDecisions)..where((t) => t.id.equals(decisionId))).getSingleOrNull();
  }

  Future<void> upsertDecision(TrackcDecisionsCompanion entry) {
    return into(trackcDecisions).insertOnConflictUpdate(entry);
  }

  Future<List<TrackcDecisionVote>> getVotesForDecision(String decisionId) {
    return (select(trackcDecisionVotes)..where((t) => t.decisionId.equals(decisionId))).get();
  }

  Future<void> upsertVote(TrackcDecisionVotesCompanion entry) {
    return into(trackcDecisionVotes).insertOnConflictUpdate(entry);
  }

  // ── Timeline ──────────────────────────────────────────────────────────────

  Future<List<TrackcTimelineEvent>> getTimelineForFamily(
    String familyId, {
    String? kind,
    int limit = 50,
  }) {
    final q = select(trackcTimelineEvents)..where((t) => t.familyId.equals(familyId));
    if (kind != null) {
      q.where((t) => t.kind.equals(kind));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    q.limit(limit);
    return q.get();
  }

  Stream<List<TrackcTimelineEvent>> watchTimelineForFamily(
    String familyId, {
    String? kind,
    int limit = 50,
  }) {
    final q = select(trackcTimelineEvents)..where((t) => t.familyId.equals(familyId));
    if (kind != null) {
      q.where((t) => t.kind.equals(kind));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    q.limit(limit);
    return q.watch();
  }

  Future<void> upsertTimelineEvent(TrackcTimelineEventsCompanion entry) {
    return into(trackcTimelineEvents).insertOnConflictUpdate(entry);
  }

  // ── Memory + Impact ───────────────────────────────────────────────────────

  Future<TrackcDecisionMemory?> getMemoryForDecision(String decisionId) {
    return (select(trackcDecisionMemories)..where((t) => t.decisionId.equals(decisionId)))
        .getSingleOrNull();
  }

  Future<void> upsertMemory(TrackcDecisionMemoriesCompanion entry) {
    return into(trackcDecisionMemories).insertOnConflictUpdate(entry);
  }

  Future<List<TrackcDecisionImpact>> getImpactsForDecision(String decisionId) {
    return (select(trackcDecisionImpacts)..where((t) => t.decisionId.equals(decisionId)))
        .get();
  }

  Future<void> upsertImpact(TrackcDecisionImpactsCompanion entry) {
    return into(trackcDecisionImpacts).insertOnConflictUpdate(entry);
  }

  // ── Meeting Artifacts ─────────────────────────────────────────────────────

  Future<List<TrackcMeetingArtifact>> getArtifactsForFamily(String familyId) {
    return (select(trackcMeetingArtifacts)..where((t) => t.familyId.equals(familyId))
          ..orderBy([(t) => OrderingTerm.desc(t.heldAt)]))
        .get();
  }

  Future<void> upsertArtifact(TrackcMeetingArtifactsCompanion entry) {
    return into(trackcMeetingArtifacts).insertOnConflictUpdate(entry);
  }

  // ── AI Insights (cache) ───────────────────────────────────────────────────

  Future<List<TrackcAiInsight>> getInsightsForDecision(String decisionId) {
    return (select(trackcAiInsights)..where((t) => t.decisionId.equals(decisionId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> upsertInsight(TrackcAiInsightsCompanion entry) {
    return into(trackcAiInsights).insertOnConflictUpdate(entry);
  }

  // ── Behavior Profile ──────────────────────────────────────────────────────

  Future<TrackcBehaviorProfile?> getBehaviorProfile(String familyId) {
    return (select(trackcBehaviorProfiles)..where((t) => t.familyId.equals(familyId)))
        .getSingleOrNull();
  }

  Future<void> upsertBehaviorProfile(TrackcBehaviorProfilesCompanion entry) {
    return into(trackcBehaviorProfiles).insertOnConflictUpdate(entry);
  }

  // ── Sync Watermark ────────────────────────────────────────────────────────

  Future<TrackcSyncWatermark?> getWatermark(String userId, String familyId, String deviceId) {
    return (select(trackcSyncWatermarks)
          ..where((t) =>
              t.userId.equals(userId) &
              t.familyId.equals(familyId) &
              t.deviceId.equals(deviceId)))
        .getSingleOrNull();
  }

  Future<void> upsertWatermark(TrackcSyncWatermarksCompanion entry) {
    return into(trackcSyncWatermarks).insertOnConflictUpdate(entry);
  }

  // ── Outbox ────────────────────────────────────────────────────────────────

  Future<List<TrackcOutboxData>> getPendingOutbox() {
    return (select(trackcOutbox)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> insertOutbox(TrackcOutboxCompanion entry) {
    return into(trackcOutbox).insert(entry);
  }

  Future<void> markOutboxApplied(String clientOpId) {
    return (update(trackcOutbox)..where((t) => t.clientOpId.equals(clientOpId))).write(
      TrackcOutboxCompanion(
        status: const Value('applied'),
        appliedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markOutboxRejected(String clientOpId, String errorMessage) {
    return (update(trackcOutbox)..where((t) => t.clientOpId.equals(clientOpId))).write(
      TrackcOutboxCompanion(
        status: const Value('rejected'),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  Future<void> incrementOutboxRetry(String clientOpId) async {
    final current = await (select(trackcOutbox)..where((t) => t.clientOpId.equals(clientOpId))).getSingleOrNull();
    if (current == null) return;
    await (update(trackcOutbox)..where((t) => t.clientOpId.equals(clientOpId))).write(
      TrackcOutboxCompanion(
        retryCount: Value(current.retryCount + 1),
      ),
    );
  }
}
