-- ============================================================
-- Migration: sparq_enhancement_mood_intensity_chain_echo
-- Version:  20260612020432
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

-- AlterEnum: Add VIP_CIRCLE to SparqAudience
ALTER TYPE "SparqAudience" ADD VALUE 'VIP_CIRCLE';

-- CreateEnum: SparqMood
CREATE TYPE "SparqMood" AS ENUM ('happy', 'hype', 'love', 'sad', 'celebrate', 'angry');

-- CreateEnum: SparqIntensity
CREATE TYPE "SparqIntensity" AS ENUM ('calm', 'warm', 'fire');
