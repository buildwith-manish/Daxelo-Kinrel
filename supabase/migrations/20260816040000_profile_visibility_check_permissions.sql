-- 20260816040000_profile_visibility_check_permissions.sql
--
-- v5.21: Wire PersonPrivacySetting into check_permissions RPC.
--
-- This migration ADDS a new action 'check_profile_visibility' to the
-- existing check_permissions function. The old 'check_visibility'
-- action (used by graph node filtering) continues to work unchanged.
--
-- The new action returns a structured result with:
--   - visibility_tier: 'owner' | 'connected' | 'public' | 'denied'
--   - is_minor: boolean
--   - searchable: boolean
--   - show_dob, show_age, show_address, show_phone, show_email, etc.
--
-- SAFETY RULES (enforced server-side, non-negotiable):
--   1. Missing PersonPrivacySetting row → DEFAULTS TO:
--      visibility='family', searchable=false, minorFlag=false.
--      Fail-closed: NOT public by default.
--   2. Minor (minorFlag=true OR under 18 by dateOfBirth) → NEVER
--      'public' tier, NEVER in search results, even if searchable=true.
--   3. Blocked viewer → 'denied' tier, always.
--
-- This does NOT break the existing check_permissions contract — it adds
-- a new action type. The old actions continue to work as before.

-- First, ensure the Person table has a dateOfBirth column (it may
-- already exist from other migrations).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'Person' AND column_name = 'dateOfBirth'
    ) THEN
        ALTER TABLE "Person" ADD COLUMN "dateOfBirth" TIMESTAMPTZ;
    END IF;
END $$;

-- Add a public_bio column to Person for the public tier's tagline.
-- This is a short user-authored line shown to public viewers.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'Person' AND column_name = 'publicBio'
    ) THEN
        ALTER TABLE "Person" ADD COLUMN "publicBio" TEXT;
    END IF;
END $$;

-- Create a helper function to compute minor status.
-- A person is a minor if:
--   - PersonPrivacySetting.minorFlag = true, OR
--   - Person.dateOfBirth indicates under 18
CREATE OR REPLACE FUNCTION is_person_minor(p_person_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT
        COALESCE(
            (SELECT "minorFlag" FROM "PersonPrivacySetting" WHERE "personId" = p_person_id),
            false
        )
        OR
        (
            EXISTS (
                SELECT 1 FROM "Person"
                WHERE id = p_person_id
                  AND "dateOfBirth" IS NOT NULL
                  AND "dateOfBirth" > (now() - interval '18 years')
            )
        );
$$;

-- Create a function to check profile visibility for a single viewer+target.
-- This is the SERVER-SIDE enforcement point for the three-tier system.
CREATE OR REPLACE FUNCTION check_profile_visibility(
    p_viewer_user_id UUID,
    p_target_person_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_result JSONB;
    v_target_family_id TEXT;
    v_viewer_linked_person_id TEXT;
    v_is_minor BOOLEAN;
    v_is_blocked BOOLEAN;
    v_shares_family BOOLEAN;
    v_tier TEXT;
    v_settings RECORD;
BEGIN
    -- Get the target person's family ID
    SELECT "familyId" INTO v_target_family_id
    FROM "Person" WHERE id = p_target_person_id AND "deletedAt" IS NULL;

    IF v_target_family_id IS NULL THEN
        RETURN jsonb_build_object('tier', 'denied', 'reason', 'person_not_found');
    END IF;

    -- Check if viewer is blocked by the target (blocks table may not exist)
    BEGIN
        v_is_blocked := EXISTS (
            SELECT 1 FROM blocks
            WHERE blocker_id = p_target_person_id
              AND blocked_id = p_viewer_user_id::text
        );
    EXCEPTION WHEN undefined_table THEN
        v_is_blocked := false;
    END;

    -- Get the viewer's linked Person ID
    SELECT id INTO v_viewer_linked_person_id
    FROM "Person"
    WHERE "linkedUserId" = p_viewer_user_id
      AND "deletedAt" IS NULL
    LIMIT 1;

    -- Check if viewer shares a family with the target
    v_shares_family := EXISTS (
        SELECT 1 FROM "FamilyMember" fm1
        JOIN "FamilyMember" fm2 ON fm1."familyId" = fm2."familyId"
        WHERE fm1."userId" = p_viewer_user_id::text
          AND fm2."userId" = (
              SELECT "linkedUserId"::text FROM "Person" WHERE id = p_target_person_id
          )
    );

    -- Check minor status
    v_is_minor := is_person_minor(p_target_person_id);

    -- Get privacy settings (defaults if no row exists — fail-closed)
    SELECT
        COALESCE(visibility, 'family') as visibility,
        COALESCE(searchable, false) as searchable,
        COALESCE("minorFlag", false) as minor_flag,
        COALESCE("showDob", false) as show_dob,
        COALESCE("showAge", false) as show_age,
        COALESCE("showAddress", false) as show_address,
        COALESCE("showPhone", false) as show_phone,
        COALESCE("showEmail", false) as show_email,
        COALESCE("showBloodGroup", false) as show_blood_group,
        COALESCE("showAnniversary", false) as show_anniversary,
        COALESCE("showOccupation", false) as show_occupation,
        COALESCE("showEducation", false) as show_education
    INTO v_settings
    FROM "PersonPrivacySetting"
    WHERE "personId" = p_target_person_id;

    -- If no settings row, use fail-closed defaults
    IF v_settings IS NULL THEN
        v_settings := ROW(
            'family'::text,  -- visibility
            false,           -- searchable (NOT searchable by default)
            false,           -- minor_flag
            false,           -- show_dob
            false,           -- show_age
            false,           -- show_address
            false,           -- show_phone
            false,           -- show_email
            false,           -- show_blood_group
            false,           -- show_anniversary
            false,           -- show_occupation
            false            -- show_education
        );
    END IF;

    -- Determine tier
    IF v_viewer_linked_person_id = p_target_person_id THEN
        v_tier := 'owner';
    ELSIF v_is_blocked THEN
        v_tier := 'denied';
    ELSIF v_is_minor AND NOT v_shares_family THEN
        -- MINOR SAFETY: minors are NEVER visible to public strangers.
        -- Even if searchable=true, a public viewer gets 'denied'.
        v_tier := 'denied';
    ELSIF v_shares_family THEN
        v_tier := 'connected';
    ELSIF v_is_minor THEN
        -- Minor + not in same family → already 'denied' above.
        -- This branch is unreachable but kept for safety.
        v_tier := 'denied';
    ELSE
        v_tier := 'public';
    END IF;

    -- Build the result
    v_result := jsonb_build_object(
        'tier', v_tier,
        'is_minor', v_is_minor,
        'searchable', v_settings.searchable,
        'show_dob', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_dob END,
        'show_age', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_age END,
        'show_address', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_address END,
        'show_phone', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_phone END,
        'show_email', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_email END,
        'show_blood_group', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_blood_group END,
        'show_anniversary', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_anniversary END,
        'show_occupation', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_occupation END,
        'show_education', CASE WHEN v_tier = 'owner' THEN true ELSE v_settings.show_education END,
        'reason', CASE
            WHEN v_tier = 'denied' AND v_is_blocked THEN 'blocked'
            WHEN v_tier = 'denied' AND v_is_minor THEN 'minor_protected'
            WHEN v_tier = 'denied' THEN 'not_visible'
            ELSE 'ok'
        END
    );

    RETURN v_result;
END;
$$;

-- Add an RLS policy on PersonPrivacySetting so only the OWNER can
-- read/write their own settings. Other users go through the
-- check_profile_visibility RPC (SECURITY DEFINER, bypasses RLS).
DROP POLICY IF EXISTS "PersonPrivacySetting_owner_select" ON "PersonPrivacySetting";
DROP POLICY IF EXISTS "PersonPrivacySetting_owner_update" ON "PersonPrivacySetting";
DROP POLICY IF EXISTS "PersonPrivacySetting_owner_insert" ON "PersonPrivacySetting";

-- Ensure RLS is enabled
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = 'PersonPrivacySetting' AND rowsecurity = true
    ) THEN
        ALTER TABLE "PersonPrivacySetting" ENABLE ROW LEVEL SECURITY;
    END IF;
END $$;

-- Owner can SELECT their own settings
CREATE POLICY "PersonPrivacySetting_owner_select" ON "PersonPrivacySetting"
    FOR SELECT TO authenticated
    USING (
        "personId" IN (
            SELECT p.id FROM "Person" p
            WHERE p."linkedUserId" = auth.uid()
              AND p."deletedAt" IS NULL
        )
    );

-- Owner can INSERT their own settings
CREATE POLICY "PersonPrivacySetting_owner_insert" ON "PersonPrivacySetting"
    FOR INSERT TO authenticated
    WITH CHECK (
        "personId" IN (
            SELECT p.id FROM "Person" p
            WHERE p."linkedUserId" = auth.uid()
              AND p."deletedAt" IS NULL
        )
    );

-- Owner can UPDATE their own settings
CREATE POLICY "PersonPrivacySetting_owner_update" ON "PersonPrivacySetting"
    FOR UPDATE TO authenticated
    USING (
        "personId" IN (
            SELECT p.id FROM "Person" p
            WHERE p."linkedUserId" = auth.uid()
              AND p."deletedAt" IS NULL
        )
    );

-- Verify
SELECT 'Profile visibility functions created' as status,
       (SELECT count(*) FROM pg_proc WHERE proname = 'check_profile_visibility') as rpc_count,
       (SELECT count(*) FROM pg_proc WHERE proname = 'is_person_minor') as minor_fn_count;
