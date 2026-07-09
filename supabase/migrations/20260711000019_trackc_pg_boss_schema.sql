-- =============================================================================
-- Track C v2.0 — pg-boss schema
-- =============================================================================
-- Implements ADR-006: pg-boss for all background work.
-- Idempotent, queued, survives restarts, retries with backoff, deduplicates.
--
-- pg-boss creates its own schema ('pgboss' by default). We create it here so
-- the NestJS PgBossModule can connect without running its own init migration
-- in production.
-- =============================================================================

-- Create pgboss role (restricted; only used by NestJS pg-boss integration)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgboss') THEN
    CREATE ROLE pgboss WITH LOGIN NOCREATEDB NOCREATEROLE NOSUPERUSER;
    RAISE NOTICE 'Created pgboss role.';
  END IF;
END $$;

-- Create pgboss schema owned by pgboss role
CREATE SCHEMA IF NOT EXISTS pgboss AUTHORIZATION pgboss;

-- Grant privileges (pgboss owns its schema; app DB user can use it)
GRANT USAGE ON SCHEMA pgboss TO authenticated, anon, service_role;

COMMENT ON SCHEMA pgboss IS 'Track C v2.0: pg-boss queue schema. ADR-006. Owned by pgboss role; pg-boss Node library creates its tables here on first connect.';
