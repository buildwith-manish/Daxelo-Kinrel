# Track C v2.0 — Migration Runbook

This runbook covers deploying the 20 Track C v2.0 migrations to a Supabase project. The migrations are idempotent and safe to run on a production-shaped snapshot.

## Pre-flight checks

1. **Backup the production database**:
   ```bash
   supabase db dump --data-only --schema=public > backup_pre_trackc_$(date +%Y%m%d).sql
   ```

2. **Verify the latest existing migration**:
   ```bash
   ls supabase/migrations/ | grep -v trackc | sort | tail -5
   ```
   The latest existing migration should be `20260710000001_add_thinking_of_you.sql`. All Track C migrations start with `20260711000001_*` and run after.

3. **Verify Supabase CLI is logged in**:
   ```bash
   supabase projects list
   ```

## Deploy order (do NOT reorder)

The migrations must be applied in lexical order. The filename timestamps enforce this.

```bash
# 1. Apply all migrations (idempotent — safe to re-run)
supabase db push

# Or, apply one at a time for finer control:
supabase migration up --file 20260711000001_trackc_create_constitution.sql
supabase migration up --file 20260711000002_trackc_create_family_decision.sql
supabase migration up --file 20260711000003_trackc_create_aura_timeline.sql
supabase migration up --file 20260711000004_trackc_create_timeline_triggers.sql
supabase migration up --file 20260711000005_trackc_create_ai_insight.sql
supabase migration up --file 20260711000006_trackc_create_learning_signal.sql
supabase migration up --file 20260711000007_trackc_create_family_behavior_profile.sql
supabase migration up --file 20260711000008_trackc_create_smart_reminder.sql
supabase migration up --file 20260711000009_trackc_create_decision_memory.sql
supabase migration up --file 20260711000010_trackc_create_meeting_artifact.sql
supabase migration up --file 20260711000011_trackc_create_search_index.sql
supabase migration up --file 20260711000012_trackc_create_search_tsvector.sql
supabase migration up --file 20260711000013_trackc_create_analytics_snapshot.sql

# 14-17 are partitioning migrations — see "Partitioning" section below
supabase migration up --file 20260711000014_trackc_partition_family_decision.sql
supabase migration up --file 20260711000015_trackc_partition_timeline.sql
supabase migration up --file 20260711000016_trackc_partition_ai_insight.sql
supabase migration up --file 20260711000017_trackc_partition_learning_signal.sql

supabase migration up --file 20260711000018_trackc_rls_all_tables.sql
supabase migration up --file 20260711000019_trackc_pg_boss_schema.sql
supabase migration up --file 20260711000020_trackc_seed_global_defaults.sql
```

4. **Verify migrations applied**:
   ```sql
   SELECT * FROM supabase_migrations.schema_migrations
   WHERE version LIKE '20260711%'
   ORDER BY version;
   ```
   Expect 20 rows.

5. **Verify Track C tables exist**:
   ```sql
   SELECT tablename FROM pg_tables
   WHERE schemaname = 'public' AND tablename IN (
     'FamilyConstitution','FamilyDecision','AURATimelineEvent','AIInsight',
     'LearningSignal','FamilyBehaviorProfile','SmartReminder','DecisionMemory',
     'DecisionImpact','MeetingArtifact','SearchIndex','FamilyAnalyticsSnapshot',
     'GlobalLearningDefaults','AICostBudget','SyncWatermark'
   );
   ```
   Expect 15 rows.

6. **Verify RLS enabled**:
   ```sql
   SELECT tablename, rowsecurity
   FROM pg_tables
   WHERE schemaname = 'public' AND tablename IN (
     'FamilyConstitution','FamilyDecision','AURATimelineEvent','AIInsight',
     'LearningSignal','FamilyBehaviorProfile','SmartReminder','DecisionMemory',
     'DecisionImpact','MeetingArtifact','SearchIndex','FamilyAnalyticsSnapshot'
   );
   ```
   All 12 should have `rowsecurity = true`.

7. **Verify partitioning**:
   ```sql
   SELECT c.relname, pt.partstrat
   FROM pg_partitioned_table pt
   JOIN pg_class c ON c.oid = pt.partrelid
   WHERE c.relname IN ('FamilyDecision','AURATimelineEvent','AIInsight','LearningSignal');
   ```
   Expect 4 rows with `partstrat = 'h'` (hash).

8. **Generate the Prisma client** (server-side):
   ```bash
   cd server
   prisma generate
   ```

## Partitioning notes (migrations 14-17)

The partitioning migrations use the rename-create-copy-drop pattern:
1. Drop inbound FKs that reference the table
2. Rename old table to `<TableName>_old`
3. Create new partitioned table with composite PK `(id, familyId)`
4. Create N hash partitions
5. Copy data from old to new
6. Drop old table
7. Recreate inbound FKs as **composite** (include `familyId`)

**Idempotency:** All four migrations check `pg_partitioned_table` first and no-op if the table is already partitioned.

**Rollback:** See `20260711000014_17_trackc_partitioning_rollback.sql`. The rollback swaps back to a non-partitioned table (destructive — only run during a maintenance window).

**On a fresh deployment:** All four tables will be empty when migrations 14-17 run, so the copy step is instant.

**On an existing deployment with data:** The copy step runs within the migration transaction. For tables with millions of rows, schedule a maintenance window.

## Post-deploy: server env vars

Add the following env vars to the Render service:

```
OPENAI_API_KEY=sk-...                    # Optional; MockLLMProvider used if absent
OPENAI_DEFAULT_MODEL=gpt-4o-mini         # Default model for routine insights
OPENAI_BASE_URL=https://api.openai.com/v1  # Optional; override for Azure/proxy
DATABASE_URL=postgresql://...            # PgBouncer URL (transaction mode)
DIRECT_URL=postgresql://...              # Direct URL for migrations + pg-boss
```

The server's `TrackcWorkers` service will auto-start pg-boss on boot. If pg-boss isn't installed or DATABASE_URL is missing, it logs a warning and continues without scheduled jobs.

## Post-deploy: verify pg-boss

```bash
# Verify the pgboss schema exists
psql $DIRECT_URL -c "\dn pgboss"

# Verify pg-boss created its tables
psql $DIRECT_URL -c "\dt pgboss.*"

# Verify scheduled jobs
psql $DIRECT_URL -c "SELECT name, data, createdon FROM pgboss.job WHERE name LIKE 'trackc-%' LIMIT 20;"
```

## Rollback procedure

To roll back all Track C v2.0 migrations (in reverse order):

```bash
# Apply rollbacks in reverse order
psql $DIRECT_URL -f supabase/migrations/20260711000018_20_trackc_rls_pgboss_seed_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000014_17_trackc_partitioning_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000011_12_trackc_search_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000013_trackc_create_analytics_snapshot_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000008_10_trackc_reminder_memory_artifact_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000006_07_trackc_learning_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000005_trackc_create_ai_insight_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000003_04_trackc_timeline_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000002_trackc_create_family_decision_rollback.sql
psql $DIRECT_URL -f supabase/migrations/20260711000001_trackc_create_constitution_rollback.sql
```

**WARNING:** The partitioning rollback is destructive if partitions contain data. Run only during a maintenance window after backing up.

## Common issues

### "function fn_trackc_monotonic_updated_at already exists"

This is expected — the function is shared across all Track C tables. The migrations use `CREATE OR REPLACE FUNCTION` so this is safe.

### "cannot drop constraint because other objects depend on it"

If you hit this during the partitioning migration, it means an FK wasn't dropped in step 1. Re-run the migration after manually dropping the offending FK:
```sql
ALTER TABLE public."<ChildTable>" DROP CONSTRAINT IF EXISTS "<ConstraintName>";
```

### "RLS policy recursion detected"

The `fn_trackc_user_family_ids()` function uses `SECURITY DEFINER` to avoid recursion. If you still see recursion, verify the function owner has access to `FamilyMember`:
```sql
ALTER FUNCTION public.fn_trackc_user_family_ids() OWNER TO postgres;
GRANT SELECT ON public."FamilyMember" TO postgres;
```

### "pg-boss: schema 'pgboss' does not exist"

Run migration 19 (`trackc_pg_boss_schema.sql`) first. If you ran `db push` and this migration was skipped, run it manually:
```bash
psql $DIRECT_URL -f supabase/migrations/20260711000019_trackc_pg_boss_schema.sql
```

### "SearchIndex tsvector column doesn't exist"

Migration 12 (`trackc_create_search_tsvector.sql`) adds the generated column. If you ran migrations 1-11 but skipped 12, run it manually:
```bash
psql $DIRECT_URL -f supabase/migrations/20260711000012_trackc_create_search_tsvector.sql
```

## Acceptance criteria checklist (Section 22)

- [x] All Phase C1–C5 migrations applied (C6 hardening requires production environment)
- [x] ADRs 1–8 reflected in code (`docs/trackc/ADRs.md`)
- [x] RLS enabled on every table in Section 5 (migration 18)
- [x] Timeline append-only invariant enforced by DB trigger (ADR-001)
- [x] Learning Engine confidence gating verified (unit test)
- [x] Documentation complete: API reference, ADRs, runbooks (this directory)
- [ ] WCAG 2.2 AA verified by external audit (requires Flutter UI + manual audit)
- [ ] Load test at 1M-family synthetic scale passes (requires production environment)
- [ ] Chaos test suite passes (circuit breaker test passes; LLM-down/replica-lag deferred)
- [ ] AI cache hit rate ≥ 60% over 7-day production window (requires production traffic)
- [ ] Security review passed (requires pen test)
