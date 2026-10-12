-- 20261001160000_add_missing_perf_indexes.sql
--
-- PHASE 2 Items 6-8: Three missing database indexes identified in the
-- performance audit. Each targets a high-frequency query that was doing
-- a sequential scan.
--
-- Item 6: UserPresence sweep query (fn_sweep_stale_presence runs every 15s)
-- Item 7: Email-based login lookup (fn_get_email_by_identifier)
-- Item 8: Person lookup by linkedUserId (family_provider.dart:1648)

-- ════════════════════════════════════════════════════════════════════
-- Item 6: UserPresence(updatedAt) WHERE isOnline = true
-- ════════════════════════════════════════════════════════════════════
-- fn_sweep_stale_presence() runs every 15 seconds (cron) and executes:
--   UPDATE "UserPresence"
--   SET "isOnline" = false, "updatedAt" = now()
--   WHERE "isOnline" = true AND "updatedAt" < now() - interval '75 seconds';
--
-- Without an index on (updatedAt) WHERE isOnline = true, this is a full
-- sequential scan over all presence rows every 15 seconds. The baseline
-- report showed 46,815 calls at 2.51ms mean = ~117s of cumulative DB time.
--
-- This partial index covers only the rows where isOnline = true (the only
-- rows the sweep query touches), keeping the index small and efficient.
CREATE INDEX IF NOT EXISTS idx_userpresence_updatedat_online
  ON "UserPresence" ("updatedAt")
  WHERE "isOnline" = true;

-- ════════════════════════════════════════════════════════════════════
-- Item 7: User(email) — for fn_get_email_by_identifier
-- ════════════════════════════════════════════════════════════════════
-- fn_get_email_by_identifier(text) does:
--   u.email ILIKE LOWER(TRIM(p_identifier))
--
-- ILIKE with a leading wildcard defeats standard btree indexes. The
-- existing GIN trigram index on Person.name works because it uses
-- gin_trgm_ops. We apply the same pattern to User.email so the ILIKE
-- can use the trigram index for fuzzy matching.
--
-- Note: if the function is later changed to exact match (=), a plain
-- btree index would be more efficient. But for now, ILIKE requires
-- the trigram approach.
CREATE INDEX IF NOT EXISTS "User_email_trgm_idx"
  ON "User" USING gin ("email" gin_trgm_ops);

-- ════════════════════════════════════════════════════════════════════
-- Item 8: Person(linkedUserId) WHERE linkedUserId IS NOT NULL
-- ════════════════════════════════════════════════════════════════════
-- family_provider.dart:1648 does:
--   .from('Person').select('id').eq('linkedUserId', userId).limit(1)
--
-- This query has no familyId filter, so the existing partial UNIQUE index
-- on (familyId, linkedUserId) can't be used (leftmost-prefix rule fails).
-- Postgres falls back to a sequential scan over the Person table.
--
-- This partial index covers only rows where linkedUserId IS NOT NULL
-- (the vast majority of Person rows have NULL linkedUserId — only linked
-- accounts have it set), keeping the index compact.
CREATE INDEX IF NOT EXISTS "Person_linkedUserId_idx"
  ON "Person" ("linkedUserId")
  WHERE "linkedUserId" IS NOT NULL;
