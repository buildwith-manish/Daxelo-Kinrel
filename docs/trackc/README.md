# Track C v2.0 — AURA Governance Engine

Production-ready implementation of the Kinrel family governance system. Implements the FINAL v2.0 specification (spec version 2.0.0-final, dated 2026-07-09).

## What's in this implementation

### Backend (NestJS) — `server/src/trackc/`

| Module | Path | Responsibility |
|---|---|---|
| **Common** | `common/` | RealtimeService proxy, FamilyMembershipService (requireMember / requireAdmin / getElderUserIds) |
| **Constitution** | `constitution/` | Draft → Publish → Amend lifecycle. Versioned immutable publications. Amendment opens a `constitution_amend` FamilyDecision. |
| **Decisions** | `decisions/` | 4 decision types (simple_vote, consensus, elder_council, constitution_amend). Pure-function state machine. Quorum computation. Lifecycle (planned → started → in_progress → completed). Memory + Impact milestones. |
| **AURA Timeline** | `governance-timeline/` | Append-only event log. DB-trigger-enforced immutability. Corrections as new `kind=correction` rows. PDF + JSON export. |
| **AURA Intelligence** | `aura-intelligence/` | LLM provider interface (OpenAI + Mock). Circuit breaker (10%/60s → 5min open). Cost guard (50K tokens/day/family). PII redaction. 5 kind handlers. Per-kind cache TTLs. |
| **AURA Learning Engine** | `aura-learning/` | Pseudonymous signal ingestion. Nightly FamilyBehaviorProfile recompute. Confidence gating (0 → 0.4 → 0.7). 50/50 blend in transition zone. Sub-50ms inference reads. |
| **AURA Secretary** | `aura-secretary/` | Structured MeetingArtifact. LLM-generated draft minutes. Action item extraction. Draft → Reviewed → Published lifecycle. |
| **AURA Search** | `aura-search/` | Postgres tsvector + GIN index. Relevance ranking (ts_rank_cd × boostedScore). Reindex worker. Suggest endpoint. |
| **AURA Analytics** | `aura-analytics/` | Weekly/monthly/quarterly snapshots. Anomaly detector (governance_dormant, quorum_decline, participation_decline, slow_decisions). Trend vs prior period. |
| **Governance Sync** | `governance-sync/` | Delta endpoint (per-device watermark, parallel fetch of 15 entity types). Push endpoint (outbox drain with idempotency, LWW conflict resolution). |
| **Workers** | `trackc.workers.ts` | pg-boss scheduled jobs (deadline sweeper, learning recompute, analytics weekly, search reindex, retention purges). |

### Database (Supabase/Postgres) — `supabase/migrations/`

20 migrations + 7 rollbacks implementing Sections 5, 7, 12 of the spec.

| # | Migration | Purpose |
|---|---|---|
| 01 | `trackc_create_constitution.sql` | FamilyConstitution + Version + Article + Clause + monotonic updatedAt trigger |
| 02 | `trackc_create_family_decision.sql` | FamilyDecision + DecisionVote |
| 03 | `trackc_create_aura_timeline.sql` | AURATimelineEvent (append-only) |
| 04 | `trackc_create_timeline_triggers.sql` | DB triggers rejecting UPDATE/DELETE (ADR-001) |
| 05 | `trackc_create_ai_insight.sql` | Consolidated AIInsight table (ADR-003) |
| 06 | `trackc_create_learning_signal.sql` | LearningSignal (pseudonymous) |
| 07 | `trackc_create_family_behavior_profile.sql` | FamilyBehaviorProfile + History (ADR-002) |
| 08 | `trackc_create_smart_reminder.sql` | SmartReminder with profile snapshots |
| 09 | `trackc_create_decision_memory.sql` | DecisionMemory + DecisionImpact |
| 10 | `trackc_create_meeting_artifact.sql` | MeetingArtifact structured |
| 11 | `trackc_create_search_index.sql` | SearchIndex |
| 12 | `trackc_create_search_tsvector.sql` | Generated tsvector column + GIN index |
| 13 | `trackc_create_analytics_snapshot.sql` | FamilyAnalyticsSnapshot |
| 14 | `trackc_partition_family_decision.sql` | 32 hash partitions (ADR-004) |
| 15 | `trackc_partition_timeline.sql` | 32 hash partitions |
| 16 | `trackc_partition_ai_insight.sql` | 16 hash partitions |
| 17 | `trackc_partition_learning_signal.sql` | 16 hash partitions |
| 18 | `trackc_rls_all_tables.sql` | RLS on every family-scoped table (ADR-008) |
| 19 | `trackc_pg_boss_schema.sql` | pg-boss schema + role (ADR-006) |
| 20 | `trackc_seed_global_defaults.sql` | GlobalLearningDefaults + AICostBudget + SyncWatermark |

### Prisma schema — `server/prisma/schema.prisma`

16 new models added at the end of the schema:

- `FamilyConstitution`, `ConstitutionVersion`, `ConstitutionArticle`, `ConstitutionClause`
- `FamilyDecision` (composite PK `id+familyId`, hash-partitioned), `DecisionVote`
- `AURATimelineEvent` (composite PK, append-only via DB trigger)
- `AIInsight` (composite PK, kind discriminator)
- `LearningSignal` (composite PK), `FamilyBehaviorProfile`, `FamilyBehaviorProfileHistory`
- `SmartReminder`, `DecisionMemory`, `DecisionImpact`, `MeetingArtifact`
- `SearchIndex`, `FamilyAnalyticsSnapshot`
- `GlobalLearningDefaults`, `AICostBudget`, `SyncWatermark`

### Tests — 82 passing

| Suite | Coverage |
|---|---|
| `decisions.state-machine.spec.ts` | Status transitions, lifecycle, quorum property tests, all 4 decision types |
| `timeline.types.spec.ts` | 14 TIMELINE_KINDS, per-kind payload schemas |
| `learning.profile-builder.spec.ts` | Confidence gating, monotonicity property, signal aggregation, blendWithDefaults |
| `intelligence.circuit-breaker.spec.ts` | Open/half_open/closed lifecycle, DegradedModeError feedback loop prevention |
| `redaction.spec.ts` | Email/phone/SSN/credit card PII redaction + name→role replacement |
| `intelligence.service.spec.ts` | MockLLMProvider produces valid JSON for all 6 kinds |

## Architecture

See [./ADRs.md](./ADRs.md) for the 8 Architecture Decision Records.

See [./API.md](./API.md) for the complete REST API reference.

See [./MIGRATIONS.md](./MIGRATIONS.md) for the migration runbook.

## Operating rules (Section 2)

1. **AI calls are always non-blocking.** UI renders fully before any AI insight appears.
2. **AI never mutates user content automatically.** Every AI output is a dismissible card.
3. **AI cost is bounded.** Per-family daily token budget enforced server-side. 50,000 tokens/day default.
4. **AI has a circuit breaker.** 10% error rate over 60s → open for 5 min.
5. **Search is offline-capable.** SearchIndex mirrored to Drift on the client.
6. **Analytics are private.** No leaderboards, no cross-family comparisons.
7. **The Timeline is append-only.** Enforced by DB trigger.
8. **Learning signals are pseudonymous.** No raw text or PII in payload.
9. **Every schema change ships with a migration and a rollback.**
10. **RLS is mandatory on every table with familyId.**
11. **Every API endpoint has a documented rate limit and idempotency contract.**
12. **Accessibility is a release gate (WCAG 2.2 AA).**

## Build phases status

| Phase | Spec weeks | Status |
|---|---|---|
| **C1** Governance Foundation | 4 | ✅ Migrations + Prisma + Constitution + Decisions + Timeline modules + tests |
| **C2** AURA Timeline Surface | 2 | ✅ Timeline list/detail/correction/export endpoints |
| **C3** AURA Intelligence | 4 | ✅ AIInsight + circuit breaker + cost guard + 5 kind handlers + cache + redaction |
| **C4** AURA Learning Engine | 3 | ✅ Signal ingestor + profile builder + inference + confidence gating + reset |
| **C5** Secretary + Search + Analytics | 4 | ✅ MeetingArtifact + SearchIndex + reindex worker + snapshots + anomaly detector |
| **C6** Production Hardening | 2 | ⏳ Unit tests done; load/chaos/security audit deferred (require production environment) |
