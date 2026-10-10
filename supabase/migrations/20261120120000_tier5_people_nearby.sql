-- =============================================================================
-- Daxelo Kinrel — Tier 5 Feature 5.3: People Nearby (Telegram-style)
-- =============================================================================
-- Lets a user discover other Kinrel users nearby (with distance). The
-- user pings their location (foreground, opt-in) + can opt out via a
-- privacy toggle.
--
-- Schema:
--   • UserLastLocation — userId, lat, lng, accuracyM, updatedAt.
--     TTL 24h — a nightly cron deletes rows older than 24h (stale
--     locations are removed so a user who uninstalled the app or closed
--     the discovery screen doesn't show up forever).
--   • User.nearbyDiscoveryEnabled boolean DEFAULT false — the user must
--     explicitly opt in to be discoverable. Default OFF (privacy first).
--
-- Server:
--   • POST /nearby/ping (lat, lng, accuracyM) — upserts the caller's row.
--   • GET /nearby/users?lat=&lng=&radiusM= — returns users within
--     radiusM of the caller's last location, sorted by distance ASC.
--   • POST /nearby/opt-out — sets nearbyDiscoveryEnabled=false.
--
-- Distance is computed via the Haversine formula in the RPC.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "UserLastLocation" (
  "userId"    text PRIMARY KEY,
  "lat"       double precision NOT NULL,
  "lng"       double precision NOT NULL,
  "accuracyM" real,
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "UserLastLocation_updated_idx" ON "UserLastLocation"("updatedAt" DESC);

ALTER TABLE "UserLastLocation" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "UserLastLocation upsert own" ON "UserLastLocation";
CREATE POLICY "UserLastLocation upsert own" ON "UserLastLocation"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserLastLocation update own" ON "UserLastLocation";
CREATE POLICY "UserLastLocation update own" ON "UserLastLocation"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserLastLocation select own" ON "UserLastLocation";
CREATE POLICY "UserLastLocation select own" ON "UserLastLocation"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
-- No DELETE policy — only the cron RPC deletes stale rows.

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "nearbyDiscoveryEnabled" boolean NOT NULL DEFAULT false;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_ping_nearby — caller upserts their current location.
--   p_lat, p_lng, p_accuracy_m
-- The RPC silently no-ops when nearbyDiscoveryEnabled=false (so a user
-- who toggled off doesn't accidentally re-publish by reusing the app's
-- location permission).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_ping_nearby(
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m real DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_enabled boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'invalid_location');
  END IF;
  IF p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_coords');
  END IF;

  -- Check the caller's opt-in flag.
  SELECT "nearbyDiscoveryEnabled" INTO v_enabled FROM "User" WHERE id = v_user_id;
  IF v_enabled IS NULL OR v_enabled = false THEN
    RETURN json_build_object('success', false, 'error', 'not_opted_in',
      'message', 'Enable "Show me on People Nearby" first.');
  END IF;

  INSERT INTO "UserLastLocation" ("userId", "lat", "lng", "accuracyM", "updatedAt")
  VALUES (v_user_id, p_lat, p_lng, p_accuracy_m, now())
  ON CONFLICT ("userId")
  DO UPDATE SET
    "lat" = p_lat,
    "lng" = p_lng,
    "accuracyM" = p_accuracy_m,
    "updatedAt" = now();

  RETURN json_build_object('success', true, 'userId', v_user_id, 'updatedAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
END;
$$;

GRANT EXECUTE ON FUNCTION fn_ping_nearby(double precision, double precision, real) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_nearby_users — returns users within radiusM of the given point.
--   p_lat, p_lng, p_radius_m (default 1000m, max 100km)
--   p_limit (default 50)
-- Filters:
--   • Caller excluded.
--   • Only users with nearbyDiscoveryEnabled=true.
--   • Only locations updated within the last 24h.
--   • Respects the user's lastSeenVisibility setting — if 'nobody',
--     the precise distance is suppressed and we return distanceBucket
--     ('<50m' | '<500m' | '<1km' | '<5km' | '>5km') instead.
-- Distance via Haversine formula.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_nearby_users(
  p_lat double precision,
  p_lng double precision,
  p_radius_m integer DEFAULT 1000,
  p_limit int DEFAULT 50
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_radius integer := LEAST(GREATEST(p_radius_m, 50), 100000);  -- clamp 50m..100km
  v_limit integer := LEAST(GREATEST(p_limit, 1), 100);
  v_requester_visibility text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Reciprocity: if the requester has lastSeenVisibility='nobody',
  -- they get bucketed distances instead of exact (matches the
  -- last-seen-privacy reciprocity rule from Tier 3 Feature 3.5).
  SELECT "lastSeenVisibility" INTO v_requester_visibility
    FROM "User" WHERE id = v_user_id;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'userId', u.id,
      'name', u.name,
      'username', u.username,
      'avatarUrl', u."avatarUrl",
      'distanceM', CASE
        WHEN v_requester_visibility = 'nobody' THEN NULL
        ELSE ROUND(
          2 * 6371000 * ASIN(SQRT(
            POWER(SIN(RADIANS(p_lat - loc."lat") / 2), 2) +
            COS(RADIANS(p_lat)) * COS(RADIANS(loc."lat")) *
            POWER(SIN(RADIANS(p_lng - loc."lng") / 2), 2)
          ))
        )::int
      END,
      'distanceBucket', CASE
        WHEN 2 * 6371000 * ASIN(SQRT(
            POWER(SIN(RADIANS(p_lat - loc."lat") / 2), 2) +
            COS(RADIANS(p_lat)) * COS(RADIANS(loc."lat")) *
            POWER(SIN(RADIANS(p_lng - loc."lng") / 2), 2)
          )) < 50 THEN '<50m'
        WHEN 2 * 6371000 * ASIN(SQRT(
            POWER(SIN(RADIANS(p_lat - loc."lat") / 2), 2) +
            COS(RADIANS(p_lat)) * COS(RADIANS(loc."lat")) *
            POWER(SIN(RADIANS(p_lng - loc."lng") / 2), 2)
          )) < 500 THEN '<500m'
        WHEN 2 * 6371000 * ASIN(SQRT(
            POWER(SIN(RADIANS(p_lat - loc."lat") / 2), 2) +
            COS(RADIANS(p_lat)) * COS(RADIANS(loc."lat")) *
            POWER(SIN(RADIANS(p_lng - loc."lng") / 2), 2)
          )) < 1000 THEN '<1km'
        WHEN 2 * 6371000 * ASIN(SQRT(
            POWER(SIN(RADIANS(p_lat - loc."lat") / 2), 2) +
            COS(RADIANS(p_lat)) * COS(RADIANS(loc."lat")) *
            POWER(SIN(RADIANS(p_lng - loc."lng") / 2), 2)
          )) < 5000 THEN '<5km'
        ELSE '>5km'
      END,
      'updatedAt', to_char(loc."updatedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ) ORDER BY
      2 * 6371000 * ASIN(SQRT(
        POWER(SIN(RADIANS(p_lat - loc."lat") / 2), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(loc."lat")) *
        POWER(SIN(RADIANS(p_lng - loc."lng") / 2), 2)
      )) ASC
    )
    FROM "UserLastLocation" loc
    JOIN "User" u ON u.id = loc."userId"
    WHERE u.id <> v_user_id
      AND u."nearbyDiscoveryEnabled" = true
      AND loc."updatedAt" > now() - interval '24 hours'
      AND 2 * 6371000 * ASIN(SQRT(
        POWER(SIN(RADIANS(p_lat - loc."lat") / 2), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(loc."lat")) *
        POWER(SIN(RADIANS(p_lng - loc."lng") / 2), 2)
      )) <= v_radius
    LIMIT v_limit
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_nearby_users(double precision, double precision, integer, int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_nearby_discovery — opt in/out. When opting out, also delete the
-- caller's location row.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_nearby_discovery(p_enabled boolean)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  UPDATE "User" SET "nearbyDiscoveryEnabled" = p_enabled, "updatedAt" = now()
    WHERE id = v_user_id;

  IF NOT p_enabled THEN
    DELETE FROM "UserLastLocation" WHERE "userId" = v_user_id;
  END IF;

  RETURN json_build_object('success', true, 'userId', v_user_id, 'nearbyDiscoveryEnabled', p_enabled);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_nearby_discovery(boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_cleanup_stale_nearby_locations — nightly cron deletes rows older
-- than 24h (so users who closed the discovery screen or uninstalled
-- don't show up forever).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_cleanup_stale_nearby_locations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  DELETE FROM "UserLastLocation"
    WHERE "updatedAt" < now() - interval '24 hours';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Nearby location cleanup: deleted % stale rows', v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cleanup_stale_nearby_locations() TO authenticated;

DO $$
DECLARE
  v_job_name text := 'cleanup-stale-nearby-locations';
  v_existing bigint;
BEGIN
  SELECT jobid INTO v_existing FROM cron.job WHERE jobname = v_job_name;
  IF v_existing IS NULL THEN
    PERFORM cron.schedule(
      v_job_name,
      '0 3 * * *',  -- nightly at 03:00 UTC
      'SELECT fn_cleanup_stale_nearby_locations();'
    );
    RAISE NOTICE 'Scheduled cron job %', v_job_name;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cron schedule skipped: %', SQLERRM;
END $$;

-- Verification
SELECT 'UserLastLocation' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'UserLastLocation') AS exists;
SELECT 'User.nearbyDiscoveryEnabled' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'User' AND column_name = 'nearbyDiscoveryEnabled'
       ) AS exists;
SELECT 'fn_ping_nearby' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_ping_nearby') AS exists;
SELECT 'fn_get_nearby_users' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_nearby_users') AS exists;
SELECT 'fn_set_nearby_discovery' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_nearby_discovery') AS exists;
SELECT 'fn_cleanup_stale_nearby_locations' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cleanup_stale_nearby_locations') AS exists;
SELECT 'cron job nearby' AS obj,
       EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'cleanup-stale-nearby-locations') AS exists;
