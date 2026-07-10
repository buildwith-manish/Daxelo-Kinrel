// =============================================================================
// Track C v2.0 — Kinrel Timeline
// timeline.types.ts
// =============================================================================
// Shared types and per-kind payload schemas for Kinrel Timeline events.
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

// =============================================================================
// VISIBILITY MATRIX — Summary whitelist for the default timeline feed
// =============================================================================
//
// The default timeline feed (returned to ALL roles including minors) shows
// ONLY a human-readable summary of meaningful governance actions. Granular /
// low-level events (votes, lifecycle changes, corrections, member joins/
// leaves) are excluded from the summary feed and are only visible via the
// `?raw=true` endpoint (admin/owner only).
//
// This is a WHITELIST (not a blacklist) so that newly added event types are
// private-by-default until explicitly added here. When you add a new kind to
// TIMELINE_KINDS, decide whether it belongs in the public summary feed:
//   - YES → add it to TIMELINE_SUMMARY_EVENT_TYPES
//   - NO  → leave it out (it will only appear in the raw admin log)
//
// Current summary event types (the "headline" governance actions):
//   - decision_created         — a new decision was opened
//   - decision_resolved        — a decision was finalized
//   - constitution_amended     — the constitution was changed
//   - constitution_published   — a new constitution version was published
//                                 (covers both constitution_created and
//                                  constitution_version_published)
//   - meeting_minutes_published — meeting minutes were finalized
//
// Excluded from summary (admin-only via ?raw=true):
//   - decision_voted           — granular per-vote event
//   - decision_expired         — system-generated, not a user action
//   - decision_lifecycle_changed — lifecycle transition, not a headline
//   - member_joined / member_left — membership changes, not governance
//   - role_changed             — admin action, not governance
//   - learning_profile_reset   — system maintenance, not governance
//   - correction               — meta-event (correction of another event)
// =============================================================================
export const TIMELINE_SUMMARY_EVENT_TYPES: ReadonlySet<TimelineKind> = new Set<TimelineKind>([
  'decision_created',
  'decision_resolved',
  'constitution_amended',
  'constitution_version_published',
  'constitution_created',
  'meeting_artifact_published',
]);

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
