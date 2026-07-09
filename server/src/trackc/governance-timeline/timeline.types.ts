// =============================================================================
// Track C v2.0 — AURA Timeline
// timeline.types.ts
// =============================================================================
// Shared types and per-kind payload schemas for AURA Timeline events.
// Section 11.1 of the FINAL v2.0 spec.
// =============================================================================

export const TIMELINE_KINDS = [
  'constitution_created',
  'constitution_amended',
  'constitution_version_published',
  'decision_created',
  'decision_voted',
  'decision_resolved',
  'decision_expired',
  'decision_lifecycle_changed',
  'member_joined',
  'member_left',
  'role_changed',
  'meeting_artifact_published',
  'learning_profile_reset',
  'correction',
] as const;

export type TimelineKind = (typeof TIMELINE_KINDS)[number];

export interface TimelineEvent {
  id: string;
  familyId: string;
  kind: TimelineKind;
  actorId: string | null;
  targetEntityType: string | null;
  targetEntityId: string | null;
  title: string;
  description: string | null;
  payload: any;
  parentEventId: string | null;
  occurredAt: Date;
  createdAt: Date;
}

export interface TimelineEventPayload {
  [key: string]: any;
}

/**
 * Per-kind payload schemas. Each schema is a function that takes the raw
 * payload and returns a sanitized payload with required fields defaulted.
 * This prevents malformed payloads from being persisted.
 */
export const TimelineEventPayloadSchemas: Record<
  TimelineKind,
  (input: TimelineEventPayload) => TimelineEventPayload
> = {
  constitution_created: (i) => ({
    versionId: i.versionId ?? null,
    articleCount: i.articleCount ?? 0,
  }),
  constitution_amended: (i) => ({
    fromVersionId: i.fromVersionId ?? null,
    toVersionId: i.toVersionId ?? null,
    changeCount: i.changeCount ?? 0,
    decisionId: i.decisionId ?? null,
  }),
  constitution_version_published: (i) => ({
    versionId: i.versionId ?? null,
    articleCount: i.articleCount ?? 0,
    clauseCount: i.clauseCount ?? 0,
  }),
  decision_created: (i) => ({
    decisionId: i.decisionId ?? null,
    type: i.type ?? null,
    deadlineAt: i.deadlineAt ?? null,
  }),
  decision_voted: (i) => ({
    decisionId: i.decisionId ?? null,
    userId: i.userId ?? null,
    option: i.option ?? null,
  }),
  decision_resolved: (i) => ({
    decisionId: i.decisionId ?? null,
    outcome: i.outcome ?? null,
    voteCount: i.voteCount ?? 0,
    eligibleCount: i.eligibleCount ?? 0,
  }),
  decision_expired: (i) => ({
    decisionId: i.decisionId ?? null,
    voteCount: i.voteCount ?? 0,
    eligibleCount: i.eligibleCount ?? 0,
  }),
  decision_lifecycle_changed: (i) => ({
    decisionId: i.decisionId ?? null,
    from: i.from ?? null,
    to: i.to ?? null,
    actorId: i.actorId ?? null,
  }),
  member_joined: (i) => ({
    userId: i.userId ?? null,
    role: i.role ?? null,
    invitedBy: i.invitedBy ?? null,
  }),
  member_left: (i) => ({
    userId: i.userId ?? null,
    reason: i.reason ?? null,
  }),
  role_changed: (i) => ({
    userId: i.userId ?? null,
    fromRole: i.fromRole ?? null,
    toRole: i.toRole ?? null,
  }),
  meeting_artifact_published: (i) => ({
    artifactId: i.artifactId ?? null,
    decisionId: i.decisionId ?? null,
  }),
  learning_profile_reset: (i) => ({
    actorId: i.actorId ?? null,
    reason: i.reason ?? null,
  }),
  correction: (i) => ({
    parentEventId: i.parentEventId ?? null,
    correctedFields: i.correctedFields ?? {},
    note: i.note ?? null,
  }),
};
