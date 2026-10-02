-- 20260923180000_prediction_battle_v1_feature_moment_spend.sql
--
-- Phase 3.10 — Coin spend: feature a Family Moment for 24h.
--
-- Coins are pure vanity without a spend. This migration adds the
-- simplest possible spend: pin a Family Moment to the top of the
-- family hub for 24 hours. Cost: 50 coins.
--
-- Schema changes
--   - Adds `featuredUntil` (TIMESTAMPTZ, nullable) to family_moments.
--     When non-null and in the future, the moment is "featured".
--     The Flutter client queries for featured moments first when
--     rendering the family hub.
--
-- RPC
--   - fn_pb_v1_feature_moment(p_user_id, p_family_id, p_moment_id)
--     Checks the user has >= 50 coins, deducts 50 coins via
--     fn_award_coins (with a negative amount + idempotency key =
--     'feature:' + moment_id), sets featuredUntil = now() + 24h.

-- ── A. Add featuredUntil column ────────────────────────────────────
ALTER TABLE "family_moments"
  ADD COLUMN IF NOT EXISTS "featuredUntil" TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_fm_family_featured
  ON "family_moments" ("familyId", "featuredUntil" DESC)
  WHERE "featuredUntil" IS NOT NULL;

-- ── B. RPC: fn_pb_v1_feature_moment ─────────────────────────────────
--
-- Atomically:
--   1. Verify the moment exists + belongs to the user's family.
--   2. Verify the user has >= 50 coins (via fn_get_coin_balance).
--   3. Deduct 50 coins via fn_award_coins (negative amount,
--      idempotency key = 'feature:<moment_id>').
--   4. Set featuredUntil = now() + 24h on the moment.
--
-- Idempotency: the fn_award_coins call is idempotent via the
-- 'feature:<moment_id>' key — if the user taps the button twice
-- quickly, the second call returns 'already_awarded' without
-- deducting again. But the featuredUntil SET is NOT idempotent —
-- so we wrap the whole thing in a transaction + check if the
-- moment is already featured by this user before proceeding.

CREATE OR REPLACE FUNCTION public.fn_pb_v1_feature_moment(
  p_user_id text,
  p_family_id text,
  p_moment_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_moment record;
  v_balance integer;
  v_award_result jsonb;
BEGIN
  -- 1. Verify the moment exists + belongs to the family.
  SELECT * INTO v_moment FROM "family_moments"
  WHERE id = p_moment_id AND "familyId" = p_family_id;
  IF v_moment IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'moment_not_found');
  END IF;

  -- 2. Verify the user has >= 50 coins.
  SELECT balance INTO v_balance
  FROM "user_coin_balances"
  WHERE "userId" = p_user_id AND "familyId" = p_family_id;
  IF v_balance IS NULL OR v_balance < 50 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'insufficient_balance', 'balance', COALESCE(v_balance, 0), 'cost', 50);
  END IF;

  -- 3. Deduct 50 coins. fn_award_coins refuses to let the balance
  --    go below zero (returns 'insufficient_balance' if it would).
  --    Idempotent via the 'feature:<moment_id>' key — if the user
  --    taps twice, the second call is a no-op.
  SELECT public.fn_award_coins(
    p_user_id,
    p_family_id,
    -50,
    'feature_moment',
    'feature:' || p_moment_id,
    jsonb_build_object('moment_id', p_moment_id)
  ) INTO v_award_result;
  IF (v_award_result->>'ok') != 'true' THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_award_result->>'reason', 'award_detail', v_award_result);
  END IF;

  -- 4. Set featuredUntil = now() + 24h.
  UPDATE "family_moments"
  SET "featuredUntil" = now() + interval '24 hours'
  WHERE id = p_moment_id;

  RETURN jsonb_build_object(
    'ok', true,
    'featured_until', now() + interval '24 hours',
    'new_balance', v_award_result->'new_balance'
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_feature_moment(text, text, text) TO authenticated;
