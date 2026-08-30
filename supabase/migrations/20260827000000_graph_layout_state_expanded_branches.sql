-- ============================================================
-- Migration: graph_layout_state_expanded_branches
-- Version:  20260827000000
-- Purpose:  Add the `expandedBranches` JSONB column to GraphLayoutState
--           for per-user persisted BRANCH EXPANSION choices (v5.123
--           Step 5). When a user manually expands a collapsed family
--           branch (tapping a "+N" chip), that choice is stored keyed
--           by (userId, familyId, branchRootId) and re-applied on the
--           next graph load — even when the default density-collapse
--           budget rule would have collapsed the branch again.
--
-- Why a new column (and why the existing columns do NOT fit):
--   • collapsedNodes — a JSONB ARRAY of node IDs. An array of strings
--     can only represent ONE polarity (the set of collapsed nodes).
--     Expansion persistence needs an OVERRIDE of the default rule:
--     "absent" must mean "apply the default", so both an explicit
--     expanded=true AND an explicit collapsed=false must be
--     expressable. An ID array cannot distinguish the two.
--   • filters — view-filter toggles, wrong semantics.
--   • nodePositions / edgeWaypoints — personal layout geometry.
--
-- Storage contract:
--   `expandedBranches` is keyed by branchRootId and stores a BOOLEAN:
--     true  = the user expanded this branch (loads already-expanded)
--     false = the user re-collapsed this branch (default rule applies,
--             recorded so the last explicit choice is known)
--
-- Personal-only scoping (same as edgeWaypoints, 20260817000000):
--   GraphLayoutState is already keyed per (familyId, userId) with a
--   UNIQUE constraint, and the existing RLS policies restrict every
--   row to its owning auth.uid(). No new RLS needed — the column
--   inherits the same row-level protection.
-- ============================================================

-- ── STEP 1: Add the expandedBranches JSONB column ───────────────
ALTER TABLE "GraphLayoutState"
  ADD COLUMN IF NOT EXISTS "expandedBranches" JSONB NOT NULL DEFAULT '{}'::jsonb;

-- ── STEP 2: Comment ───────────────────────────────────────────
COMMENT ON COLUMN "GraphLayoutState"."expandedBranches" IS
  'Per-branch expansion choice, keyed by branchRootId. '
  'Format: {"<branchRootId>": true|false}. true = the user expanded '
  'this branch (loads already-expanded, overriding the density-'
  'collapse budget rule); false = the user re-collapsed it. '
  'Personal-only — same (familyId, userId) scope + RLS as '
  'nodePositions and edgeWaypoints.';
