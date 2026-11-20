-- ============================================================
-- Migration: create_familypostcomment
-- Task 4a — dedicated comment rows for FamilyPost (timeline).
--
-- Until now timeline.service.ts keeps comments inside the
-- "FamilyPost"."reactions" JSON string ({ ..., comments: [CommentData] }).
-- This adds a real table so task 4b can swap getComments / addComment /
-- deleteComment over to it. Column names/types mirror the service's
-- CommentData: { id, authorId, authorName, body, parentId, createdAt }.
--
-- Named "FamilyPostComment" because "Comment" already exists and belongs
-- to "CommunityPost".
--
-- Notes
--   * "authorId" is a "User" id (the service resolves the name from the
--     User table), NOT a Person id (that is "FamilyPost"."authorId").
--   * "authorName" is a snapshot, exactly like the JSON workaround.
--   * Deleting a post, a user, or a parent comment cascades (replies go
--     with their parent, matching the service's deleteComment).
--   * Constraint / index names are the ones Prisma generates, so
--     `prisma migrate diff` should show no drift for this table.
--   * The "reactions" JSON is NOT modified. The backfill below only
--     COPIES existing JSON comments; 4b decides when to stop writing
--     the JSON.
--   * No function is created, so SECURITY DEFINER / search_path do not
--     apply here.
--
-- NOT applied to any database from the sandbox — review/test against a
-- staging Supabase project before trusting it in prod (especially the
-- RLS policies and the JSON backfill).
-- ============================================================

-- ── 1. Table ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "FamilyPostComment" (
  "id"           TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyPostId" TEXT NOT NULL,
  "authorId"     TEXT NOT NULL,
  "authorName"   TEXT NOT NULL,
  "body"         TEXT NOT NULL,
  "parentId"     TEXT,
  "createdAt"    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2. Foreign keys (idempotent) ─────────────────────────────
DO $$ BEGIN
  ALTER TABLE "FamilyPostComment"
    ADD CONSTRAINT "FamilyPostComment_familyPostId_fkey"
    FOREIGN KEY ("familyPostId") REFERENCES "FamilyPost"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FamilyPostComment"
    ADD CONSTRAINT "FamilyPostComment_authorId_fkey"
    FOREIGN KEY ("authorId") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FamilyPostComment"
    ADD CONSTRAINT "FamilyPostComment_parentId_fkey"
    FOREIGN KEY ("parentId") REFERENCES "FamilyPostComment"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 3. Indexes ───────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS "FamilyPostComment_familyPostId_createdAt_idx"
  ON "FamilyPostComment" ("familyPostId", "createdAt");
CREATE INDEX IF NOT EXISTS "FamilyPostComment_authorId_idx"
  ON "FamilyPostComment" ("authorId");
CREATE INDEX IF NOT EXISTS "FamilyPostComment_parentId_idx"
  ON "FamilyPostComment" ("parentId");

-- ── 4. Row level security ────────────────────────────────────
-- Prisma (server) connects with a role that bypasses RLS; these policies
-- only govern direct PostgREST / realtime access with a user JWT.
-- No UPDATE policy: comments are immutable (the service has no edit).
ALTER TABLE "FamilyPostComment" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Family members can read post comments" ON "FamilyPostComment";
CREATE POLICY "Family members can read post comments"
  ON "FamilyPostComment" FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM "FamilyPost" p
      JOIN "FamilyMember" m ON m."familyId" = p."familyId"
      WHERE p."id" = "FamilyPostComment"."familyPostId"
        AND m."userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "Family members can comment as themselves" ON "FamilyPostComment";
CREATE POLICY "Family members can comment as themselves"
  ON "FamilyPostComment" FOR INSERT
  WITH CHECK (
    "authorId" = auth.uid()::text
    AND EXISTS (
      SELECT 1
      FROM "FamilyPost" p
      JOIN "FamilyMember" m ON m."familyId" = p."familyId"
      WHERE p."id" = "FamilyPostComment"."familyPostId"
        AND m."userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "Authors and admins can delete post comments" ON "FamilyPostComment";
CREATE POLICY "Authors and admins can delete post comments"
  ON "FamilyPostComment" FOR DELETE
  USING (
    "authorId" = auth.uid()::text
    OR EXISTS (
      SELECT 1
      FROM "FamilyPost" p
      JOIN "FamilyMember" m ON m."familyId" = p."familyId"
      WHERE p."id" = "FamilyPostComment"."familyPostId"
        AND m."userId" = auth.uid()::text
        AND m."role" IN ('owner', 'admin')
    )
  );

-- ── 5. Backfill: copy comments from the reactions JSON ───────
-- Idempotent (ON CONFLICT DO NOTHING on the preserved comment id, so ids
-- used as pagination cursors / parentId keep working). A post whose JSON
-- is malformed is skipped, never aborts the migration. A comment whose
-- author no longer exists in "User" is skipped (FK would reject it).
-- Replies are linked in a second pass so parent order does not matter.
DO $$
DECLARE
  post_rec        record;
  c               jsonb;
  n               integer;
  posts_seen      integer := 0;
  posts_bad       integer := 0;
  comments_in     integer := 0;
  comments_skip   integer := 0;
  post_in         integer;
  post_skip       integer;
BEGIN
  FOR post_rec IN
    SELECT "id", "reactions" FROM "FamilyPost"
    WHERE "reactions" LIKE '%"comments"%'
  LOOP
    posts_seen := posts_seen + 1;
    post_in := 0;
    post_skip := 0;
    BEGIN
      -- pass 1: rows without parent
      FOR c IN
        SELECT jsonb_array_elements(post_rec."reactions"::jsonb -> 'comments')
      LOOP
        INSERT INTO "FamilyPostComment"
          ("id", "familyPostId", "authorId", "authorName", "body", "createdAt")
        SELECT
          c ->> 'id',
          post_rec."id",
          c ->> 'authorId',
          COALESCE(NULLIF(c ->> 'authorName', ''), 'Unknown'),
          c ->> 'body',
          COALESCE((c ->> 'createdAt')::timestamptz, now())
        WHERE c ->> 'id' IS NOT NULL
          AND c ->> 'body' IS NOT NULL
          AND EXISTS (SELECT 1 FROM "User" u WHERE u."id" = c ->> 'authorId')
        ON CONFLICT ("id") DO NOTHING;
        GET DIAGNOSTICS n = ROW_COUNT;
        IF n = 1 THEN post_in := post_in + 1;
        ELSE post_skip := post_skip + 1;
        END IF;
      END LOOP;

      -- pass 2: link replies to parents on the same post
      FOR c IN
        SELECT jsonb_array_elements(post_rec."reactions"::jsonb -> 'comments')
      LOOP
        IF c ->> 'parentId' IS NOT NULL THEN
          UPDATE "FamilyPostComment" r
             SET "parentId" = c ->> 'parentId'
           WHERE r."id" = c ->> 'id'
             AND r."parentId" IS NULL
             AND EXISTS (
               SELECT 1 FROM "FamilyPostComment" p
               WHERE p."id" = c ->> 'parentId'
                 AND p."familyPostId" = post_rec."id"
             );
        END IF;
      END LOOP;

      -- only count a post's rows once its whole block succeeded
      comments_in := comments_in + post_in;
      comments_skip := comments_skip + post_skip;
    EXCEPTION WHEN OTHERS THEN
      posts_bad := posts_bad + 1;
      RAISE NOTICE 'create_familypostcomment: skipped FamilyPost % (%): %',
        post_rec."id", SQLSTATE, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE 'create_familypostcomment backfill: % post(s) with JSON comments, % comment row(s) inserted, % skipped (no id/body, unknown author, or already present), % post(s) skipped as malformed',
    posts_seen, comments_in, comments_skip, posts_bad;
END
$$;

-- ── Rollback (manual) ────────────────────────────────────────
-- DROP TABLE IF EXISTS "FamilyPostComment";
-- (policies, indexes and FKs go with the table; "FamilyPost"."reactions"
--  still holds the original JSON comments because nothing here changes it.)
