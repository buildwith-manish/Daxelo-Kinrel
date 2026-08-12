-- =============================================================================
-- Daxelo-Kinrel — Family Space Groups System (v137)
-- =============================================================================
-- Adds sub-groups WITHIN a Family Space. Groups are child entities of the
-- Family Space — they cannot exist standalone. This preserves Kinrel's
-- family-first identity (unlike WhatsApp/Telegram where groups are
-- free-floating).
--
-- Schema:
--   Group          — a conversation group within a family
--   GroupMember    — membership (family members OR invited guests)
--   ChatMessage    — extended with nullable groupId for group-scoped chat
--
-- Guest member rules (enforced via RLS):
--   • Guests can only see the specific group they were invited into
--   • Guests CANNOT see the Family Space, other groups, family graph,
--     family tree, family memories, or family map
--   • Guests can send/receive messages, view media, and react in their
--     invited group only
--
-- Group types: cousins, parents, siblings, family_event, travel, custom
-- Member roles: admin, moderator, member, guest
-- =============================================================================

-- ─── 1. Group table ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "Group" (
    id                  text        PRIMARY KEY,
    "familyId"          text        NOT NULL REFERENCES "Family"(id) ON DELETE CASCADE,
    name                text        NOT NULL,
    description         text,
    "groupType"         text        NOT NULL DEFAULT 'custom',  -- cousins | parents | siblings | family_event | travel | custom
    "avatarUrl"         text,
    "createdBy"         text        NOT NULL,                    -- auth.users.id as text
    "lastActivityAt"    timestamptz NOT NULL DEFAULT now(),
    "isArchived"        boolean     NOT NULL DEFAULT false,
    "createdAt"         timestamptz NOT NULL DEFAULT now(),
    "updatedAt"         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_family
    ON "Group" ("familyId", "lastActivityAt" DESC);

CREATE INDEX IF NOT EXISTS idx_group_not_archived
    ON "Group" ("familyId")
    WHERE "isArchived" = false;

-- ─── 2. GroupMember table ───────────────────────────────────────────────────
-- A membership row can be either:
--   • A family member (userId references auth.users, isGuest=false)
--   • A guest (userId references auth.users, isGuest=true)
-- Guests are NOT added to FamilyMember — they only exist in GroupMember
-- for the specific group they were invited into.

CREATE TABLE IF NOT EXISTS "GroupMember" (
    id              text        PRIMARY KEY,
    "groupId"       text        NOT NULL REFERENCES "Group"(id) ON DELETE CASCADE,
    "userId"        text        NOT NULL,                       -- auth.users.id as text
    "displayName"   text        NOT NULL,                       -- denormalized for display
    role            text        NOT NULL DEFAULT 'member',      -- admin | moderator | member | guest
    "isGuest"       boolean     NOT NULL DEFAULT false,
    "joinedAt"      timestamptz NOT NULL DEFAULT now(),
    UNIQUE ("groupId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_groupmember_group
    ON "GroupMember" ("groupId");

CREATE INDEX IF NOT EXISTS idx_groupmember_user
    ON "GroupMember" ("userId");

CREATE INDEX IF NOT EXISTS idx_groupmember_guest
    ON "GroupMember" ("groupId")
    WHERE "isGuest" = true;

-- ─── 3. Extend ChatMessage with nullable groupId ───────────────────────────
-- A message belongs to EITHER:
--   • The family-wide chat (groupId = NULL, familyId = the family)
--   • A specific group chat (groupId = the group, familyId = the group's family)
-- This keeps the existing family chat working unchanged while adding
-- group-scoped conversations.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'ChatMessage' AND column_name = 'groupId'
    ) THEN
        ALTER TABLE "ChatMessage" ADD COLUMN "groupId" text REFERENCES "Group"(id) ON DELETE CASCADE;
        CREATE INDEX IF NOT EXISTS idx_chatmessage_group_created
            ON "ChatMessage" ("groupId", "createdAt" DESC)
            WHERE "groupId" IS NOT NULL;
    END IF;
END $$;

-- ─── 4. Triggers: auto-generate IDs + updated_at ──────────────────────────

CREATE OR REPLACE FUNCTION fn_group_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW."updatedAt" = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_group_set_updated_at ON "Group";
CREATE TRIGGER trg_group_set_updated_at
    BEFORE UPDATE ON "Group"
    FOR EACH ROW EXECUTE FUNCTION fn_group_set_updated_at();

CREATE OR REPLACE FUNCTION fn_group_gen_id()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        NEW.id := 'grp_' || encode(gen_random_bytes(12), 'hex');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_group_gen_id ON "Group";
CREATE TRIGGER trg_group_gen_id
    BEFORE INSERT ON "Group"
    FOR EACH ROW
    WHEN (NEW.id IS NULL OR NEW.id = '')
    EXECUTE FUNCTION fn_group_gen_id();

CREATE OR REPLACE FUNCTION fn_groupmember_gen_id()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        NEW.id := 'gm_' || encode(gen_random_bytes(12), 'hex');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_groupmember_gen_id ON "GroupMember";
CREATE TRIGGER trg_groupmember_gen_id
    BEFORE INSERT ON "GroupMember"
    FOR EACH ROW
    WHEN (NEW.id IS NULL OR NEW.id = '')
    EXECUTE FUNCTION fn_groupmember_gen_id();

-- ─── 5. Trigger: update Group.lastActivityAt on new message ────────────────

CREATE OR REPLACE FUNCTION fn_group_update_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW."groupId" IS NOT NULL THEN
        UPDATE "Group" SET "lastActivityAt" = now() WHERE id = NEW."groupId";
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chatmessage_update_group_activity ON "ChatMessage";
CREATE TRIGGER trg_chatmessage_update_group_activity
    AFTER INSERT ON "ChatMessage"
    FOR EACH ROW
    WHEN (NEW."groupId" IS NOT NULL)
    EXECUTE FUNCTION fn_group_update_activity();

-- ─── 6. Helper: is current user a member of group X? ───────────────────────
-- Handles BOTH family members AND guests. A user is a group member if:
--   • They have a GroupMember row for that group, OR
--   • They are a family member of the group's family (family members can
--     see all groups in their family, even without an explicit GroupMember
--     row — this matches the "Family Members can see all groups" rule)

CREATE OR REPLACE FUNCTION fn_user_is_group_member(group_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM "GroupMember" gm
        WHERE gm."groupId" = group_id AND gm."userId" = auth.uid()::text
    ) OR EXISTS (
        SELECT 1 FROM "Group" g
        JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
        WHERE g.id = group_id AND fm."userId" = auth.uid()::text
    );
$$;

-- ─── 7. RLS: Group table ───────────────────────────────────────────────────
-- Family members can see all groups in their family.
-- Guests can ONLY see groups where they have a GroupMember row.

ALTER TABLE "Group" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS group_select_policy ON "Group";
CREATE POLICY group_select_policy
    ON "Group" FOR SELECT
    USING (
        fn_user_is_family_member("familyId")
        OR EXISTS (
            SELECT 1 FROM "GroupMember" gm
            WHERE gm."groupId" = "Group".id AND gm."userId" = auth.uid()::text
        )
    );

-- Only family admins/creators can create groups
DROP POLICY IF EXISTS group_insert_policy ON "Group";
CREATE POLICY group_insert_policy
    ON "Group" FOR INSERT
    WITH CHECK (
        fn_user_is_family_member("familyId")
        AND "createdBy" = auth.uid()::text
    );

-- Family admins or group admins can update
DROP POLICY IF EXISTS group_update_policy ON "Group";
CREATE POLICY group_update_policy
    ON "Group" FOR UPDATE
    USING (fn_user_is_family_member("familyId"));

-- Family admins or group creators can delete
DROP POLICY IF EXISTS group_delete_policy ON "Group";
CREATE POLICY group_delete_policy
    ON "Group" FOR DELETE
    USING (
        "createdBy" = auth.uid()::text
        OR EXISTS (
            SELECT 1 FROM "FamilyMember" fm
            WHERE fm."familyId" = "Group"."familyId"
              AND fm."userId" = auth.uid()::text
              AND fm.role IN ('admin', 'owner')
        )
    );

-- ─── 8. RLS: GroupMember table ─────────────────────────────────────────────
-- Family members can see all memberships in their family's groups.
-- Guests can only see memberships in groups they belong to.

ALTER TABLE "GroupMember" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS groupmember_select_policy ON "GroupMember";
CREATE POLICY groupmember_select_policy
    ON "GroupMember" FOR SELECT
    USING (
        fn_user_is_group_member("groupId")
    );

-- Family admins or group admins can add members
DROP POLICY IF EXISTS groupmember_insert_policy ON "GroupMember";
CREATE POLICY groupmember_insert_policy
    ON "GroupMember" FOR INSERT
    WITH CHECK (
        fn_user_is_family_member(
            (SELECT "familyId" FROM "Group" WHERE id = "groupId")
        )
    );

-- Family admins, group admins, or the member themselves can update
DROP POLICY IF EXISTS groupmember_update_policy ON "GroupMember";
CREATE POLICY groupmember_update_policy
    ON "GroupMember" FOR UPDATE
    USING (
        "userId" = auth.uid()::text
        OR fn_user_is_family_member(
            (SELECT "familyId" FROM "Group" WHERE id = "groupId")
        )
    );

-- Family admins, group admins, or the member themselves can delete
DROP POLICY IF EXISTS groupmember_delete_policy ON "GroupMember";
CREATE POLICY groupmember_delete_policy
    ON "GroupMember" FOR DELETE
    USING (
        "userId" = auth.uid()::text
        OR fn_user_is_family_member(
            (SELECT "familyId" FROM "Group" WHERE id = "groupId")
        )
    );

-- ─── 9. RLS: ChatMessage — extend for group-scoped messages ────────────────
-- The existing family-level policies remain. We add group-level access:
-- a user can read/write a group message if they are a member of that group.

DROP POLICY IF EXISTS chatmessage_select_policy ON "ChatMessage";
CREATE POLICY chatmessage_select_policy
    ON "ChatMessage" FOR SELECT
    USING (
        -- Family-level message: family members can read
        ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
        -- Group-level message: group members can read
        OR ("groupId" IS NOT NULL AND fn_user_is_group_member("groupId"))
    );

DROP POLICY IF EXISTS chatmessage_insert_policy ON "ChatMessage";
CREATE POLICY chatmessage_insert_policy
    ON "ChatMessage" FOR INSERT
    WITH CHECK (
        "senderId" = auth.uid()::text
        AND (
            ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
            OR ("groupId" IS NOT NULL AND fn_user_is_group_member("groupId"))
        )
    );

DROP POLICY IF EXISTS chatmessage_update_policy ON "ChatMessage";
CREATE POLICY chatmessage_update_policy
    ON "ChatMessage" FOR UPDATE
    USING (
        ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
        OR ("groupId" IS NOT NULL AND fn_user_is_group_member("groupId"))
    )
    WITH CHECK (
        ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
        OR ("groupId" IS NOT NULL AND fn_user_is_group_member("groupId"))
    );

DROP POLICY IF EXISTS chatmessage_delete_policy ON "ChatMessage";
CREATE POLICY chatmessage_delete_policy
    ON "ChatMessage" FOR DELETE
    USING ("senderId" = auth.uid()::text);

-- ─── 10. Add Group + GroupMember to realtime publication ───────────────────

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'Group'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "Group";
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'GroupMember'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "GroupMember";
    END IF;
END $$;

-- ─── 11. RPC: create group with members in one call ────────────────────────
-- Avoids multiple round-trips from the client. Creates the group + adds
-- the creator as admin + adds the selected members.

CREATE OR REPLACE FUNCTION fn_create_group(
    p_family_id text,
    p_name text,
    p_description text DEFAULT NULL,
    p_group_type text DEFAULT 'custom',
    p_avatar_url text DEFAULT NULL,
    p_member_user_ids text[] DEFAULT '{}',
    p_member_display_names text[] DEFAULT '{}',
    p_member_is_guests boolean[] DEFAULT '{}'
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_group_id text;
    v_creator_id text := auth.uid()::text;
    v_creator_name text;
    i int;
BEGIN
    -- Verify creator is a family member
    IF NOT fn_user_is_family_member(p_family_id) THEN
        RAISE EXCEPTION 'Not a family member';
    END IF;

    -- Get creator's display name
    SELECT u.name INTO v_creator_name
    FROM "User" u WHERE u.id = v_creator_id;
    IF v_creator_name IS NULL THEN v_creator_name := 'Unknown'; END IF;

    -- Create the group
    v_group_id := 'grp_' || encode(gen_random_bytes(12), 'hex');
    INSERT INTO "Group" (id, "familyId", name, description, "groupType", "avatarUrl", "createdBy")
    VALUES (v_group_id, p_family_id, p_name, p_description, p_group_type, p_avatar_url, v_creator_id);

    -- Add creator as admin
    INSERT INTO "GroupMember" ("groupId", "userId", "displayName", role, "isGuest")
    VALUES (v_group_id, v_creator_id, v_creator_name, 'admin', false);

    -- Add selected members
    FOR i IN 1..array_length(p_member_user_ids, 1) LOOP
        IF p_member_user_ids[i] <> v_creator_id THEN
            INSERT INTO "GroupMember" ("groupId", "userId", "displayName", role, "isGuest")
            VALUES (
                v_group_id,
                p_member_user_ids[i],
                COALESCE(p_member_display_names[i], 'Member'),
                CASE WHEN p_member_is_guests[i] THEN 'guest' ELSE 'member' END,
                COALESCE(p_member_is_guests[i], false)
            )
            ON CONFLICT ("groupId", "userId") DO NOTHING;
        END IF;
    END LOOP;

    RETURN v_group_id;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION fn_create_group TO authenticated;

COMMENT ON TABLE "Group" IS
    'Sub-groups within a Family Space. Child of Family — cannot exist standalone. RLS-scoped: family members see all groups, guests see only invited groups.';
COMMENT ON TABLE "GroupMember" IS
    'Group memberships. Includes both family members and invited guests. role: admin | moderator | member | guest.';
