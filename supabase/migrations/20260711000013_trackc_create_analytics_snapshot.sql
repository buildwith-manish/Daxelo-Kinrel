-- =============================================================================
-- Track C v2.0 — AURA Analytics
-- Migration 13: FamilyAnalyticsSnapshot
-- =============================================================================
-- Implements Section 5.9 of the FINAL v2.0 spec.
-- Weekly/monthly/quarterly snapshots, private (no cross-family comparison).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."FamilyAnalyticsSnapshot" (
  "id"            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"      TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "periodStart"   TIMESTAMPTZ NOT NULL,
  "periodEnd"     TIMESTAMPTZ NOT NULL,
  "granularity"   TEXT NOT NULL CHECK ("granularity" IN ('weekly','monthly','quarterly')),
  "metrics"       JSONB NOT NULL DEFAULT '{}'::JSONB,
  "anomalies"     JSONB,
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "FamilyAnalyticsSnapshot_unique_period" UNIQUE ("familyId", "granularity", "periodStart"),
  CONSTRAINT "FamilyAnalyticsSnapshot_period_order" CHECK ("periodEnd" > "periodStart")
);

CREATE INDEX IF NOT EXISTS "FamilyAnalyticsSnapshot_familyId_periodEnd_idx" ON public."FamilyAnalyticsSnapshot"("familyId", "periodEnd");
CREATE INDEX IF NOT EXISTS "FamilyAnalyticsSnapshot_granularity_idx"         ON public."FamilyAnalyticsSnapshot"("familyId", "granularity", "periodStart");

GRANT SELECT ON public."FamilyAnalyticsSnapshot" TO anon, authenticated;
COMMENT ON TABLE public."FamilyAnalyticsSnapshot" IS 'Track C v2.0: AURA Analytics private family-scoped snapshot. 2-year retention.';
