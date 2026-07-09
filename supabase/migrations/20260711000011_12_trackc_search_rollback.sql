-- Rollback for 11 + 12 (SearchIndex + tsvector)
DROP INDEX IF EXISTS public."search_index_tsvector_gin";
ALTER TABLE public."SearchIndex" DROP COLUMN IF EXISTS search_tsvector;
DROP TRIGGER IF EXISTS trg_trackc_search_index_updated_at ON public."SearchIndex";
DROP TABLE IF EXISTS public."SearchIndex";
