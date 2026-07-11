-- =============================================================================
-- Family Map — Last-Known Member Location table
-- =============================================================================
-- BACKGROUND:
--   The Family Map feature splits location data into two transports:
--     1. Supabase Realtime Broadcast (ephemeral, every few seconds) —
--        live pin movement, NOT persisted.
--     2. This table (MemberLocation) — last-known position only,
--        written on a 30-60s / >50m-moved throttle, read on app
--        load / reconnect to seed pin positions before live
--        broadcasts arrive.
--
--   Do NOT add this table to supabase_realtime publication — it is
--   last-known only, read on load, not tailed continuously. High-
--   frequency live movement goes through Broadcast channels
--   (family-map:{familyId}) instead.
--
-- RLS:
--   The policy binds the auth identity to the actual claimed Person
--   profile, not just to itself. The naive check
--   `userId = auth.uid()::text` only proves the row's userId matches
--   the caller — it does NOT prove the caller is authorized to
--   publish location FOR that personId. Without the extra check, an
--   authenticated user could write their own userId alongside someone
--   else's personId.
--
--   The full WITH CHECK verifies ALL of:
--     a) userId = auth.uid()::text  (caller is who they say they are)
--     b) personId is a Person whose linkedUserId = auth.uid()::text
--        (the caller actually claimed this Person node — reuses the
--        existing "claim your profile" flow via Person.linkedUserId)
--     c) that Person's familyId matches the row's declared familyId
--        (the Person belongs to the declared family)
--
--   SELECT policy: caller must be a member of the same family
--   (via FamilyMember table).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."MemberLocation" (
    id            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"    TEXT NOT NULL,
    "personId"    TEXT NOT NULL,
    "userId"      TEXT NOT NULL,
    lat           DOUBLE PRECISION NOT NULL,
    lng           DOUBLE PRECISION NOT NULL,
    "isSharing"   BOOLEAN NOT NULL DEFAULT false,
    "updatedAt"   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE ("personId")
);

ALTER TABLE public."MemberLocation" ENABLE ROW LEVEL SECURITY;

-- ── SELECT: caller must be a member of the same family ───────────────
-- A user can see the last-known locations of all members in families
-- they belong to. This is the same membership check used elsewhere
-- (FamilyMember.familyId + userId).
CREATE POLICY "MemberLocation_select_family_members"
  ON public."MemberLocation"
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "MemberLocation"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );

-- ── INSERT: caller must own the Person node they're publishing for ──
-- Three-way check: userId matches caller AND personId is claimed by
-- caller AND that Person belongs to the declared family.
CREATE POLICY "MemberLocation_insert_owner_only"
  ON public."MemberLocation"
  FOR INSERT
  TO authenticated
  WITH CHECK (
    "userId" = auth.uid()::text
    AND EXISTS (
      SELECT 1 FROM public."Person" p
      WHERE p.id = "MemberLocation"."personId"
        AND p."linkedUserId" = auth.uid()::text
        AND p."familyId" = "MemberLocation"."familyId"
    )
  );

-- ── UPDATE: same three-way check + only own row ─────────────────────
-- A user can only UPDATE their own MemberLocation row (identified by
-- personId, which has a UNIQUE constraint — one row per person).
CREATE POLICY "MemberLocation_update_owner_only"
  ON public."MemberLocation"
  FOR UPDATE
  TO authenticated
  USING (
    "userId" = auth.uid()::text
    AND EXISTS (
      SELECT 1 FROM public."Person" p
      WHERE p.id = "MemberLocation"."personId"
        AND p."linkedUserId" = auth.uid()::text
        AND p."familyId" = "MemberLocation"."familyId"
    )
  )
  WITH CHECK (
    "userId" = auth.uid()::text
    AND EXISTS (
      SELECT 1 FROM public."Person" p
      WHERE p.id = "MemberLocation"."personId"
        AND p."linkedUserId" = auth.uid()::text
        AND p."familyId" = "MemberLocation"."familyId"
    )
  );

-- ── DELETE: only the owner can delete their location row ────────────
-- Used when sharing is turned off permanently (right to be forgotten).
CREATE POLICY "MemberLocation_delete_owner_only"
  ON public."MemberLocation"
  FOR DELETE
  TO authenticated
  USING (
    "userId" = auth.uid()::text
  );

-- ── Grants ───────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public."MemberLocation" TO authenticated;

-- ── Indexes ──────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS "MemberLocation_familyId_idx"
  ON public."MemberLocation"("familyId");

CREATE INDEX IF NOT EXISTS "MemberLocation_userId_idx"
  ON public."MemberLocation"("userId");

-- ── Updated_at trigger ───────────────────────────────────────────────
-- Auto-update updatedAt on every row change.
CREATE OR REPLACE FUNCTION public."set_member_location_updated_at"()
RETURNS TRIGGER AS $$
BEGIN
  NEW."updatedAt" = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "MemberLocation_set_updated_at"
  BEFORE UPDATE ON public."MemberLocation"
  FOR EACH ROW
  EXECUTE FUNCTION public."set_member_location_updated_at"();
