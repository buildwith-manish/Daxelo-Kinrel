-- 20260713140000_add_date_of_death.sql
--
-- P7.3: Family Journey Replay — adds dateOfDeath column to Person.
-- Allows the journey replay to filter the graph by who was alive
-- at a specific year (e.g., "who was alive in 1985?").

ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "dateOfDeath" TIMESTAMPTZ;
