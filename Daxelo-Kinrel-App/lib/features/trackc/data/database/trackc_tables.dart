// =============================================================================
// Track C v2.0 — Kinrel Governance Engine — Flutter Drift Schema
// =============================================================================
// Offline mirror of all tier-1 entities (Section 7.1 strong consistency tier):
//   - FamilyConstitution + Version + Article + Clause
//   - FamilyDecision + DecisionVote
//   - KinrelTimelineEvent (read-only mirror)
//   - DecisionMemory + DecisionImpact
//   - MeetingArtifact
//
// Tier 2 (eventual) entities (AIInsight, SearchIndex, FamilyBehaviorProfile)
// are mirrored here too for offline browse, but mutations are rejected.
//
// Tier 3 (queued) operations go into TrackcOutbox.
//
// Per-device per-family watermark is stored in TrackcSyncWatermark.
// =============================================================================

import 'package:drift/drift.dart';

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Constitution (tier 1 — strong)
// ────────────────────────────────────────────────────────────────────────────

class TrackcConstitutions extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get title => text()();
  TextColumn get preamble => text().nullable()();
  TextColumn get currentVersionId => text().nullable()();
  TextColumn get draftVersionId => text().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TrackcConstitutionVersions extends Table {
  TextColumn get id => text()();
  TextColumn get constitutionId => text()();
  TextColumn get familyId => text()();
  IntColumn get versionNumber => integer()();
  TextColumn get status => text()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  TextColumn get publishedById => text().nullable()();
  TextColumn get changeSummary => text().nullable()();
  IntColumn get articleCount => integer()();
  IntColumn get clauseCount => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TrackcConstitutionArticles extends Table {
  TextColumn get id => text()();
  TextColumn get versionId => text()();
  TextColumn get familyId => text()();
  IntColumn get orderIndex => integer()();
  TextColumn get title => text()();
  TextColumn get intent => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TrackcConstitutionClauses extends Table {
  TextColumn get id => text()();
  TextColumn get articleId => text()();
  TextColumn get versionId => text()();
  TextColumn get familyId => text()();
  IntColumn get orderIndex => integer()();
  TextColumn get clauseText => text()();
  TextColumn get intent => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Decisions (tier 1 — strong)
// ────────────────────────────────────────────────────────────────────────────

class TrackcDecisions extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get createdById => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get type => text()(); // simple_vote|consensus|elder_council|constitution_amend
  TextColumn get status => text()(); // open|resolved|expired|cancelled
  TextColumn get outcome => text().nullable()();
  TextColumn get optionsJson => text()(); // JSON array
  TextColumn get eligibleUserIdsJson => text()(); // JSON array
  IntColumn get quorumPct => integer()();
  BoolColumn get showVotesLive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deadlineAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get resolutionNote => text().nullable()();
  TextColumn get lifecycleState => text().nullable()();
  DateTimeColumn get lifecycleUpdatedAt => dateTime().nullable()();
  TextColumn get constitutionVersionId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TrackcDecisionVotes extends Table {
  TextColumn get id => text()();
  TextColumn get decisionId => text()();
  TextColumn get familyId => text()();
  TextColumn get userId => text()();
  TextColumn get option => text()();
  DateTimeColumn get votedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Kinrel Timeline (tier 1 — read-only mirror)
// ────────────────────────────────────────────────────────────────────────────

class TrackcTimelineEvents extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get kind => text()();
  TextColumn get actorId => text().nullable()();
  TextColumn get targetEntityType => text().nullable()();
  TextColumn get targetEntityId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get payloadJson => text()(); // JSON object
  TextColumn get parentEventId => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Decision Memory + Impact (tier 1 — strong)
// ────────────────────────────────────────────────────────────────────────────

class TrackcDecisionMemories extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get decisionId => text()();
  TextColumn get summaryText => text()();
  TextColumn get keyTakeawaysJson => text()();
  TextColumn get searchKeywordsJson => text()();
  TextColumn get relatedConstitutionArticleIdsJson => text()();
  TextColumn get relatedMemoryIdsJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TrackcDecisionImpacts extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get decisionId => text()();
  TextColumn get milestoneText => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get evidenceUrlsJson => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Meeting Artifacts (tier 1 — strong)
// ────────────────────────────────────────────────────────────────────────────

class TrackcMeetingArtifacts extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get decisionId => text().nullable()();
  TextColumn get title => text()();
  DateTimeColumn get heldAt => dateTime()();
  TextColumn get participantsJson => text()();
  TextColumn get agendaJson => text()();
  TextColumn get discussionPointsJson => text()();
  TextColumn get decisionsJson => text()();
  TextColumn get actionItemsJson => text()();
  TextColumn get draftMinutesMd => text()();
  TextColumn get finalMinutesMd => text().nullable()();
  TextColumn get status => text()(); // draft|reviewed|published
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: AI Insight (tier 2 — eventual, read-only cache)
// ────────────────────────────────────────────────────────────────────────────

class TrackcAiInsights extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  TextColumn get decisionId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get payloadJson => text()();
  TextColumn get modelId => text()();
  IntColumn get tokensIn => integer()();
  IntColumn get tokensOut => integer()();
  RealColumn get costUsd => real().nullable()();
  DateTimeColumn get presentedAt => dateTime().nullable()();
  DateTimeColumn get acceptedAt => dateTime().nullable()();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
  TextColumn get dismissedReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Family Behavior Profile (tier 2 — eventual, read-only)
// ────────────────────────────────────────────────────────────────────────────

class TrackcBehaviorProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text()();
  IntColumn get version => integer()();
  DateTimeColumn get computedAt => dateTime()();
  TextColumn get preferredReminderLeadHoursJson => text()();
  TextColumn get reminderActionRateJson => text()();
  TextColumn get preferredWeekdayDistributionJson => text()();
  TextColumn get preferredTimeOfDayBucketsJson => text()();
  RealColumn get elderAutoIncludeThreshold => real()();
  TextColumn get insightAcceptRateByKindJson => text()();
  RealColumn get averageDecisionDurationHours => real().nullable()();
  BoolColumn get typicalQuorumMet => boolean().nullable()();
  IntColumn get sampleSize => integer()();
  RealColumn get confidenceScore => real()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Sync Watermark (per-device per-family)
// ────────────────────────────────────────────────────────────────────────────

class TrackcSyncWatermarks extends Table {
  TextColumn get userId => text()();
  TextColumn get familyId => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get watermark => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, familyId, deviceId};
}

// ────────────────────────────────────────────────────────────────────────────
// TABLE: Outbox (Section 7.4 — queued operations)
// ────────────────────────────────────────────────────────────────────────────

class TrackcOutbox extends Table {
  TextColumn get clientOpId => text()(); // UUID generated client-side
  TextColumn get familyId => text()();
  TextColumn get kind => text()(); // create|update|delete
  TextColumn get entity => text()(); // decision|constitution|reminder
  TextColumn get op => text()(); // vote|editTitle|lifecycle|...
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending|applied|rejected|conflict
  TextColumn get errorMessage => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get appliedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {clientOpId};
}
