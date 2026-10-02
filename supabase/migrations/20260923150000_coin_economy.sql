-- 20260923150000_coin_economy.sql
--
-- Phase 3.7 — Coin Economy for the Prediction Battle (and beyond).
--
-- This migration builds a minimal but production-ready coin economy:
--
--   1. coin_ledger            — append-only transaction log.
--                                Every credit is a row here. The sum
--                                of `amount` per (userId, familyId)
--                                IS the user's current balance. This
--                                is the canonical source of truth —
--                                the balance table below is a cache.
--   2. user_coin_balances      — per-user-per-family current balance.
--                                Updated atomically by fn_award_coins
--                                inside the same transaction as the
--                                ledger insert. Reads use this
--                                (much faster than summing the ledger).
--   3. fn_award_coins(userId, familyId, amount, reason) — the single
--                                RPC that the predictions module (and
--                                any future coin-granting feature)
--                                calls. Idempotent via a unique
--                                (ledger_idempotency_key) column —
--                                see the comments in the function body.
--
-- Design choices
-- ─────────────
-- • Append-only ledger. We NEVER update or delete a ledger row. If a
--   coin award was wrong, we post a compensating `adjustment` row.
--   This gives us a full audit trail + the ability to debug "why did
--   my balance change on day X" questions forever.
-- • Balance is a cache. The ledger is the source of truth. If the
--   cache ever drifts (e.g., a buggy migration backfills the balance
--   wrongly), we can rebuild it from the ledger in a single UPDATE.
-- • Negative amounts are allowed (for spend events in the future),
--   but the function refuses to let the balance go below zero — the
--   family coin economy is intentionally non-debt.
-- • Idempotency: the function takes an optional idempotency key
--   (passed as part of the reason string in v1; can be promoted to a
--   real param later). For now, we use the (userId, familyId, reason,
--   roundId) tuple as the natural key — but since fn_award_coins
--   doesn't know about rounds, we accept a 5th optional arg
--   p_idempotency_key that the predictions module passes as the
--   round id.

-- ═════════════════════════════════════════════════════════════════════
-- 1. coin_ledger table
-- ═════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "coin_ledger" (
  "id"                 TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"             TEXT NOT NULL,
  "familyId"           TEXT NOT NULL,
  "amount"             INTEGER NOT NULL,             -- can be negative for spends
  "reason"             TEXT NOT NULL,                -- 'prediction_winner' | 'prediction_streak_bonus' | 'prediction_close_guess' | 'prediction_participation' | future
  "idempotencyKey"     TEXT,                          -- optional — e.g. round id, prevents double-award
  "metadata"           JSONB NOT NULL DEFAULT '{}'::jsonb,  -- free-form: round_id, question_id, etc.
  "createdAt"          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
-- Main query: "what's user X's recent coin history in family Y?"
CREATE INDEX IF NOT EXISTS idx_cl_user_family_created
  ON "coin_ledger" ("userId", "familyId", "createdAt" DESC);
-- Idempotency check: "have we already awarded for this key?"
CREATE UNIQUE INDEX IF NOT EXISTS uq_cl_idempotency
  ON "coin_ledger" ("userId", "familyId", "reason", "idempotencyKey")
  WHERE "idempotencyKey" IS NOT NULL;
-- Reason filter (e.g., "show me all prediction_winner awards")
CREATE INDEX IF NOT EXISTS idx_cl_reason_created
  ON "coin_ledger" ("reason", "createdAt" DESC);

ALTER TABLE "coin_ledger" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coin_ledger_select_self_or_family ON "coin_ledger";
-- A user can read their own ledger rows. Family members can also
-- read each other's coin history — this is the family coin economy,
-- transparency is part of the social contract.
CREATE POLICY coin_ledger_select_self_or_family ON "coin_ledger"
  FOR SELECT TO authenticated
  USING (
    "userId" = auth.uid()::text
    OR public.fn_user_is_family_member("familyId")
  );
-- INSERT only via SECURITY DEFINER functions (fn_award_coins). No
-- direct INSERT policy — the function bypasses RLS via SECURITY
-- DEFINER. (We could allow INSERT for authenticated but there's no
-- reason for the client to write ledger rows directly.)

-- ═════════════════════════════════════════════════════════════════════
-- 2. user_coin_balances table (cache)
-- ═════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "user_coin_balances" (
  "userId"     TEXT NOT NULL,
  "familyId"   TEXT NOT NULL,
  "balance"    INTEGER NOT NULL DEFAULT 0,
  "lifetimeEarned" INTEGER NOT NULL DEFAULT 0,
  "updatedAt"  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("userId", "familyId")
);

CREATE INDEX IF NOT EXISTS idx_ucb_family_balance
  ON "user_coin_balances" ("familyId", "balance" DESC);

ALTER TABLE "user_coin_balances" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_coin_balances_select_self_or_family ON "user_coin_balances";
CREATE POLICY user_coin_balances_select_self_or_family ON "user_coin_balances"
  FOR SELECT TO authenticated
  USING (
    "userId" = auth.uid()::text
    OR public.fn_user_is_family_member("familyId")
  );

-- ═════════════════════════════════════════════════════════════════════
-- 3. fn_award_coins RPC
-- ═════════════════════════════════════════════════════════════════════
--
-- Signature: fn_award_coins(p_user_id, p_family_id, p_amount, p_reason, p_idempotency_key DEFAULT NULL, p_metadata DEFAULT '{}'::jsonb)
--
-- The original migration assumed a 4-arg signature. We extend to 6
-- args with defaults so the original call sites
--   PERFORM public.fn_award_coins(uid, fam, 10, 'prediction_winner');
-- still work — the extra args default to NULL / '{}'::jsonb.
--
-- Idempotency: if p_idempotency_key is provided AND a ledger row
-- already exists with the same (userId, familyId, reason, idempotencyKey),
-- this function is a no-op (returns 'ok:already_awarded'). This
-- protects against the pg_cron recovery tick running twice in a row
-- for the same round.

CREATE OR REPLACE FUNCTION public.fn_award_coins(
  p_user_id text,
  p_family_id text,
  p_amount integer,
  p_reason text,
  p_idempotency_key text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing record;
  v_new_balance integer;
BEGIN
  -- ── Idempotency check ──
  -- If a key was provided, look for an existing award with the same
  -- (userId, familyId, reason, idempotencyKey). The partial unique
  -- index uq_cl_idempotency enforces this at the DB level too, but
  -- we check first so we can return a friendly status without
  -- catching a constraint violation.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_existing FROM "coin_ledger"
    WHERE "userId" = p_user_id
      AND "familyId" = p_family_id
      AND "reason" = p_reason
      AND "idempotencyKey" = p_idempotency_key
    LIMIT 1;
    IF v_existing.id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'status', 'already_awarded', 'ledger_id', v_existing.id);
    END IF;
  END IF;

  -- ── Refuse negative balances ──
  -- If p_amount is negative (a spend), check the current balance
  -- first. The family coin economy is intentionally non-debt.
  IF p_amount < 0 THEN
    SELECT balance INTO v_new_balance
    FROM "user_coin_balances"
    WHERE "userId" = p_user_id AND "familyId" = p_family_id;
    IF v_new_balance IS NULL OR v_new_balance + p_amount < 0 THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'insufficient_balance');
    END IF;
  END IF;

  -- ── Insert the ledger row ──
  INSERT INTO "coin_ledger" ("userId", "familyId", "amount", "reason", "idempotencyKey", "metadata")
  VALUES (p_user_id, p_family_id, p_amount, p_reason, p_idempotency_key, p_metadata);

  -- ── Update the balance cache (atomic with the ledger insert) ──
  INSERT INTO "user_coin_balances" ("userId", "familyId", "balance", "lifetimeEarned", "updatedAt")
  VALUES (p_user_id, p_family_id,
    p_amount,
    GREATEST(p_amount, 0),
    now())
  ON CONFLICT ("userId", "familyId") DO UPDATE SET
    balance = "user_coin_balances".balance + p_amount,
    "lifetimeEarned" = "user_coin_balances"."lifetimeEarned" + GREATEST(p_amount, 0),
    "updatedAt" = now();

  -- Return the new balance so callers can include it in the user's
  -- notification body if they want ("You won 10 coins! Balance: 42")
  SELECT balance INTO v_new_balance
  FROM "user_coin_balances"
  WHERE "userId" = p_user_id AND "familyId" = p_family_id;

  RETURN jsonb_build_object(
    'ok', true,
    'status', 'awarded',
    'amount', p_amount,
    'new_balance', v_new_balance
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_award_coins(text, text, integer, text, text, jsonb) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- 4. fn_get_coin_balance RPC (lightweight read for the Flutter client)
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_get_coin_balance(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
BEGIN
  SELECT balance, "lifetimeEarned", "updatedAt" INTO v_row
  FROM "user_coin_balances"
  WHERE "userId" = p_user_id AND "familyId" = p_family_id;

  IF v_row IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'balance', 0, 'lifetimeEarned', 0, 'updatedAt', NULL);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'balance', v_row.balance,
    'lifetimeEarned', v_row."lifetimeEarned",
    'updatedAt', v_row."updatedAt"
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_coin_balance(text, text) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- 5. fn_get_coin_history RPC (paginated ledger read for the Flutter client)
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_get_coin_history(
  p_user_id text,
  p_family_id text,
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'amount', amount,
    'reason', reason,
    'metadata', metadata,
    'createdAt', "createdAt"
  ) ORDER BY "createdAt" DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT * FROM "coin_ledger"
    WHERE "userId" = p_user_id AND "familyId" = p_family_id
    ORDER BY "createdAt" DESC
    LIMIT p_limit OFFSET p_offset
  ) sub;

  RETURN jsonb_build_object('ok', true, 'rows', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_coin_history(text, text, integer, integer) TO authenticated;
