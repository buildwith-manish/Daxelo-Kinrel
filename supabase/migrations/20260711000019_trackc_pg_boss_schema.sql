-- =============================================================================
-- Track C v2.0 — pg-boss schema
-- =============================================================================
-- Implements ADR-006: pg-boss for all background work.
-- Idempotent, queued, survives restarts, retries with backoff, deduplicates.
--
-- NOTE: Supabase restricts role management. We cannot CREATE ROLE pgboss.
-- Instead, pg-boss will use the existing postgres/authenticated role via
-- the DATABASE_URL connection string. The pg-boss Node library creates its
-- own tables on first connect.
-- =============================================================================

-- Create pgboss schema (owned by postgres, the default Supabase role)
CREATE SCHEMA IF NOT EXISTS pgboss;

-- Grant privileges — pg-boss needs full access to its schema
GRANT USAGE ON SCHEMA pgboss TO authenticated, anon, service_role;
GRANT ALL ON SCHEMA pgboss TO service_role;

COMMENT ON SCHEMA pgboss IS 'Track C v2.0: pg-boss queue schema. ADR-006. pg-boss Node library creates its tables here on first connect using the DATABASE_URL connection.';
