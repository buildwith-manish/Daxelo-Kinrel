-- ============================================================
-- Migration: drop_dead_kinship_tables
-- Version:  20260701091000
--
-- DROPPED:
--   1. RelationshipTypeMetadata (1,100 rows, UNUSED — app uses
--      kinship_category_map.dart const with 5,363 entries instead)
--   2. RelationshipPathCache (0 rows, UNUSED — app does BFS
--      client-side)
--
-- KEPT:
--   - Relationship (user data — stores relationshipKey per edge)
--   - RelationshipInverse (81 rows, USED by fill_inverse_label trigger)
-- ============================================================

DROP TABLE IF EXISTS public."RelationshipTypeMetadata" CASCADE;
DROP TABLE IF EXISTS public."RelationshipPathCache" CASCADE;
