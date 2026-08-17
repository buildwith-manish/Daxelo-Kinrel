-- ============================================================
-- Migration: graph_layout_state_edge_waypoints
-- Version:  20260817000000
-- Purpose:  Add the `edgeWaypoints` JSONB column to GraphLayoutState
--           for personal (per-viewer) persisted relationship-line
--           curve bow overrides. This is the storage layer for
--           v5.22 PART 2 — dragging a relationship line's midpoint
--           dot to visually bow the curve around obstacles WITHOUT
--           ever changing who the line connects.
--
-- Storage contract:
--   `edgeWaypoints` is keyed by relationshipId and stores a
--   RELATIVE offset {dx, dy} from the true bezier t=0.5 midpoint
--   (NOT an absolute canvas coordinate — absolute coordinates
--   would break if the overall layout shifts; a relative offset
--   stays meaningful as long as the two endpoints haven't moved).
--
-- Personal-only scoping:
--   GraphLayoutState is already keyed per (familyId, userId) with
--   a UNIQUE constraint, and the existing RLS policies
--   (20260608182557_fix_rls_tables_with_missing_policies.sql)
--   restrict every row to its owning auth.uid(). No new RLS needed
--   here — the column inherits the same row-level protection as
--   nodePositions.
-- ============================================================

-- ── STEP 1: Add the edgeWaypoints JSONB column ──────────────────
-- Default empty JSON object so existing rows + new rows work
-- without a backfill (read coalesces to {}).
ALTER TABLE "GraphLayoutState"
  ADD COLUMN IF NOT EXISTS "edgeWaypoints" JSONB NOT NULL DEFAULT '{}'::jsonb;

-- ── STEP 2: Updated_at trigger refresh (no-op if already present)
-- The base table already has an `updatedAt` column and existing
-- production_sync_2025_03_04.sql handles timestamp maintenance at
-- the application layer. No trigger changes needed for this column.

-- ── STEP 3: Comment ───────────────────────────────────────────
COMMENT ON COLUMN "GraphLayoutState"."edgeWaypoints" IS
  'Per-relationship RELATIVE midpoint offset, keyed by relationshipId. '
  'Format: {"<relationshipId>": {"dx": <double>, "dy": <double>}}. '
  'The offset is FROM the true bezier t=0.5 midpoint (computed by '
  'edge_router.computeMidpoint). A relative offset is stored (not '
  'absolute) so the override stays meaningful if the endpoints move. '
  'Personal-only — same (familyId, userId) scope + RLS as nodePositions.';
