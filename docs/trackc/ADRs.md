# Track C v2.0 — Architecture Decision Records

All 8 ADRs from Section 17 of the FINAL v2.0 spec, mapped to their implementation.

---

## ADR-001: Append-only timeline enforced by DB trigger

**Status:** Accepted · **Implemented in:** `supabase/migrations/20260711000004_trackc_create_timeline_triggers.sql`

**Context:** The AURA Timeline must never be edited or deleted. Application-layer enforcement is brittle — a bug in any code path that updates the table would compromise the audit trail.

**Decision:** Use Postgres triggers to reject UPDATE and DELETE on `AURATimelineEvent`. The trigger function `enforce_timeline_append_only()` raises an exception with `check_violation` SQLSTATE on any UPDATE or DELETE attempt.

**Consequences:**
- Corrections are explicit new events with `kind='correction'` and `parentEventId` pointing to the original event.
- The UI renders corrections inline beneath the original with a "Corrected on {date}" badge.
- No UPDATE ergonomics — slightly more complex update flow.
- Zero risk of accidental mutation.

**Tradeoff accepted:** Loss of UPDATE ergonomics in exchange for a hard guarantee.

**Tested by:** `governance-timeline/timeline.types.spec.ts` verifies all 14 TIMELINE_KINDS have payload schemas that work with the append-only model.

---

## ADR-002: Materialized behavior profile instead of per-call ML

**Status:** Accepted · **Implemented in:** `server/src/trackc/aura-learning/learning.profile-builder.ts`

**Context:** The AURA Learning Engine needs to personalize AI suggestions in <50ms. A trained per-family ML model would be operationally expensive, privacy-risky (weights encode behavior), hard to debug, and brittle at small sample sizes.

**Decision:** Compute a `FamilyBehaviorProfile` nightly via a pg-boss worker (`trackc-learning-recompute`). Serve single-row reads at inference time. Confidence gating (Section 9.4) prevents overfitting:
- `confidenceScore < 0.4` → use global defaults
- `0.4 ≤ confidenceScore < 0.7` → blend 50% learned + 50% defaults
- `confidenceScore ≥ 0.7` → use learned values

**Consequences:**
- Personalization is statistical, not learned. Fully auditable (every field is human-readable).
- Sample-size aware via `confidenceScore`.
- Trivially resettable (admin "reset" returns to defaults).
- Forward-compatible: the same `LearningSignal` table can feed a future ML training pipeline.

**Tradeoff accepted:** Slightly less nuanced personalization in exchange for simplicity, cost, and debuggability.

**Tested by:** `learning.profile-builder.spec.ts` — confidence gating, monotonicity property test, blendWithDefaults at 0/50/100% weight.

---

## ADR-003: Consolidated AIInsight table with kind discriminator

**Status:** Accepted · **Implemented in:** `supabase/migrations/20260711000005_trackc_create_ai_insight.sql`

**Context:** The v2.0 draft had two separate tables (`AISuggestion` and `AIAnalysis`) sharing 90% of columns and always joined together. This doubled the query complexity and cache surface.

**Decision:** Single `AIInsight` table with a `kind` discriminator column. Kinds: `decision_analysis`, `duplicate_detection`, `summary`, `pros_cons`, `smart_reminder`, `action_items`, `draft_minutes`, `search_synonym`.

**Consequences:**
- Simpler queries, simpler caching, simpler governance.
- Slightly larger single table (mitigated by hash-partitioning on `familyId` — ADR-004).
- Per-kind cache TTLs enforced by the `IntelligenceCache` service.

**Tradeoff accepted:** Larger single table in exchange for fewer joins and simpler service code.

---

## ADR-004: Hash-partition four high-volume tables on familyId

**Status:** Accepted · **Implemented in:** `supabase/migrations/20260711000014-17_trackc_partition_*.sql`

**Context:** Projected 3 billion timeline events over 3 years (Section 13.1). Unpartitioned tables would suffer write throughput degradation and index bloat.

**Decision:** Hash-partition on `familyId`:
- `FamilyDecision` → 32 partitions
- `AURATimelineEvent` → 32 partitions
- `AIInsight` → 16 partitions
- `LearningSignal` → 16 partitions

Each partitioned table uses a **composite primary key** `(id, familyId)`. Foreign keys from referring tables are composite (e.g. `DecisionVote(decisionId, familyId) → FamilyDecision(id, familyId)`) to satisfy Postgres's requirement that FKs to partitioned tables include the partition key.

**Consequences:**
- Linear write throughput scaling.
- Cross-family queries impossible without UNION ALL (which we never need — all queries are family-scoped).
- Migration is non-trivial: rename old table → create new partitioned → copy data → drop old → recreate FKs as composite.

**Tradeoff accepted:** Migration complexity in exchange for scale headroom.

**Idempotent:** All 4 partitioning migrations check `pg_partitioned_table` first and no-op if already partitioned.

---

## ADR-005: LLM provider behind circuit breaker + cost ceiling

**Status:** Accepted · **Implemented in:** `server/src/trackc/aura-intelligence/{intelligence.circuit-breaker.ts, intelligence.cost-guard.ts, llm-provider.ts, llm-providers/}`

**Context:** LLM costs and outages must not break the app. A single LLM provider outage should not cascade into application errors.

**Decision:**
- **Circuit breaker:** 10% error rate over 60s window → OPEN for 5 min → HALF_OPEN trial → CLOSE on success / re-OPEN on failure.
- **Cost ceiling:** Per-family daily token budget (50,000 tokens default). When exhausted, AI endpoints return `degraded_mode = true` and serve cached insights only.
- **Model routing:** `gpt-4o-mini` for routine analyses, `gpt-4o` for constitutional amendments (via the `modelId` field on each kind handler).
- **Provider abstraction:** `LLMProvider` interface with `OpenAIProvider` and `MockLLMProvider` implementations. The Mock provider produces valid structured payloads for all 6 kinds, enabling end-to-end testing without an OpenAI key.

**Consequences:**
- AI features degrade gracefully. During outages, all AI endpoints return cached/degraded within 5s (chaos test target).
- Costs are predictable. Per-family daily cap prevents runaway spend.
- Provider lock-in avoided: every AIInsight row records `modelId` for replay/audit.

**Tradeoff accepted:** Slightly worse UX during outages in exchange for system stability.

**Tested by:** `intelligence.circuit-breaker.spec.ts` — full open/half_open/closed lifecycle, DegradedModeError feedback loop prevention.

---

## ADR-006: pg-boss for all background work

**Status:** Accepted · **Implemented in:** `server/src/trackc/trackc.workers.ts` + `supabase/migrations/20260711000019_trackc_pg_boss_schema.sql`

**Context:** Cron-based scheduling is non-idempotent and fragile across restarts. The previous v1.0 cron jobs duplicated work after process restarts.

**Decision:** All scheduled work flows through pg-boss with idempotency keys. pg-boss persists its queue in the `pgboss` Postgres schema (owned by a restricted `pgboss` role).

**Workers registered:**
1. `trackc-deadline-sweeper` — every 5 min, auto-expires decisions past deadline
2. `trackc-learning-recompute` — daily 02:00 UTC, recomputes FamilyBehaviorProfile
3. `trackc-analytics-weekly` — Sundays 01:00 UTC, snapshots for all active families
4. `trackc-search-reindex` — hourly, incremental reindex of recently-updated entities
5. `trackc-signal-purge` — weekly, purges LearningSignal older than 365 days
6. `trackc-profile-history-purge` — daily, purges profile history older than 90 days
7. `trackc-insight-purge` — daily, purges AIInsight older than 365 days

**Consequences:**
- Survives restarts (queue state is in Postgres).
- Retries with exponential backoff (`retryLimit: 5`, `retryDelay: 60s`).
- Deduplicates via `publishAfter` with a named singleton key.

**Tradeoff accepted:** Additional dependency (pg-boss + `pgboss` Postgres role) in exchange for reliability.

**Graceful degradation:** If pg-boss is not installed (`require('pg-boss')` throws) or `DATABASE_URL` is missing, the server still boots — workers are disabled and a warning is logged.

---

## ADR-007: Three-tier consistency model for offline

**Status:** Accepted · **Implemented in:** `server/src/trackc/governance-sync/` + offline Flutter sync engine (planned)

**Context:** Ambiguous offline behavior caused UX bugs in the v1.0 prototype. Users didn't know what worked offline and what didn't.

**Decision:** Explicit consistency tiers per entity (Section 7.1):

| Tier | Entities | Behavior when offline |
|---|---|---|
| **Strong** | Constitution, Decisions, Votes, DecisionMemory, Timeline | Full read/write offline; optimistic mutations queued in Drift outbox; conflicts surfaced on reconnect |
| **Eventual** | AIInsight, SearchIndex, FamilyBehaviorProfile | Read from local cache; mutations rejected with banner "AI features require connection" |
| **Queued** | AI insight generation requests, search reindex, analytics export | Persisted in outbox; flushed on reconnect with dedup by `Idempotency-Key` |

**Consequences:**
- Users know exactly what works offline.
- Engineers know what to test (Section 14 lists per-tier test cases).
- Slight UX complexity (banners) in exchange for clarity.

**Watermark protocol:** Each device maintains a per-family `SyncWatermark` (ISO timestamp of last successful delta fetch). The delta endpoint returns all rows where `updatedAt > watermark`. Monotonic clock enforced by `fn_trackc_monotonic_updated_at()` trigger.

**Conflict resolution:** LWW for decision title/description; concurrent votes never conflict (append-only); constitution clause edits use structured merge with user-visible conflict resolution.

**Tradeoff accepted:** Slight UX complexity (offline banners) in exchange for clarity.

---

## ADR-008: No `service_role` from application code

**Status:** Accepted · **Implemented in:** `supabase/migrations/20260711000018_trackc_rls_all_tables.sql`

**Context:** Supabase's `service_role` bypasses RLS. Using it from application code is a footgun — a single bug can leak cross-family data.

**Decision:** All app requests use the user's JWT. RLS policies use the `fn_trackc_user_family_ids()` helper to verify family membership. System jobs (pg-boss workers) use a separate service account with table-scoped grants, not `service_role`.

**RLS pattern (every family-scoped table):**
```sql
CREATE POLICY "trackc_<table>_select" ON public."<Table>"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_<table>_insert" ON public."<Table>"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

CREATE POLICY "trackc_<table>_update" ON public."<Table>"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));
```

Special cases:
- `DecisionVote`: INSERT requires `userId = auth.uid()` (you can only cast your own vote).
- `SmartReminder`: SELECT and UPDATE require `targetUserId = auth.uid()` (you can only see/snooze your own reminders).
- `AURATimelineEvent`: only SELECT and INSERT policies (UPDATE/DELETE forbidden by trigger).
- `SearchIndex`, `FamilyAnalyticsSnapshot`, `FamilyBehaviorProfile`: SELECT-only (writes via pg-boss).

**Consequences:**
- Defense in depth: RLS is the security boundary, not the application.
- Cross-family reads impossible at the DB layer.
- Automated RLS verification tests should run in CI (Section 14.6).

**Tradeoff accepted:** Slightly more setup in exchange for hard security guarantees.
