-- Truth Streak feature — Supabase migration
-- Creates 4 tables for the daily family question game.

-- ─────────────────────────────────────────────────────────────────
-- truth_streak_questions — shared question bank (not per-family)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "truth_streak_questions" (
    id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    question    TEXT NOT NULL,
    category    TEXT NOT NULL DEFAULT 'general',
    "isActive"  BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed initial questions
INSERT INTO "truth_streak_questions" (question, category) VALUES
    ('What is your favourite family memory from childhood?', 'childhood'),
    ('Who in the family makes the best food, and what do they cook?', 'food'),
    ('What tradition do you want to pass down to the next generation?', 'traditions'),
    ('What is the funniest thing that happened at a family gathering?', 'funny'),
    ('Which elder do you admire most, and why?', 'elders'),
    ('What is a skill or talent that runs in your family?', 'talents'),
    ('What is your earliest memory of a festival celebration?', 'festivals'),
    ('If you could have dinner with one ancestor, who would it be?', 'ancestors'),
    ('What is a lesson your parents taught you that you still follow?', 'lessons'),
    ('What is the most adventurous thing a family member has done?', 'adventures'),
    ('What family recipe should be preserved for future generations?', 'food'),
    ('What is a story about your family that always gets told?', 'stories'),
    ('What is something you are grateful for about your family?', 'gratitude'),
    ('What is a challenge your family overcame together?', 'challenges'),
    ('What is your favourite way to spend time with family?', 'bonding')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- truth_streak_daily_assignments — one question per family per day
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "truth_streak_daily_assignments" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"      TEXT NOT NULL,
    "questionId"    TEXT NOT NULL REFERENCES "truth_streak_questions"(id) ON DELETE CASCADE,
    "assignedDate"  DATE NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("familyId", "assignedDate")
);

CREATE INDEX IF NOT EXISTS idx_ts_assignment_family_date
    ON "truth_streak_daily_assignments"("familyId", "assignedDate");

-- ─────────────────────────────────────────────────────────────────
-- truth_streak_answers — one answer per user per assignment
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "truth_streak_answers" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "assignmentId"  TEXT NOT NULL REFERENCES "truth_streak_daily_assignments"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "userAvatarUrl" TEXT,
    answer          TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("assignmentId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_ts_answer_assignment
    ON "truth_streak_answers"("assignmentId");

-- ─────────────────────────────────────────────────────────────────
-- truth_streak_user_stats — streak tracking per user per family
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "truth_streak_user_stats" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "userId"            TEXT NOT NULL,
    "familyId"          TEXT NOT NULL,
    "currentStreak"     INTEGER NOT NULL DEFAULT 0,
    "longestStreak"     INTEGER NOT NULL DEFAULT 0,
    "lastAnsweredDate"  DATE,
    "updatedAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("userId", "familyId")
);

-- ─────────────────────────────────────────────────────────────────
-- RLS Policies — follow the existing family-scoped pattern
-- ─────────────────────────────────────────────────────────────────

-- Enable RLS on all 4 tables
ALTER TABLE "truth_streak_questions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "truth_streak_daily_assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "truth_streak_answers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "truth_streak_user_stats" ENABLE ROW LEVEL SECURITY;

-- Questions: any authenticated user can read (shared bank)
CREATE POLICY "ts_questions_select" ON "truth_streak_questions"
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- Assignments: family members can read their own family's assignments
CREATE POLICY "ts_assignments_select" ON "truth_streak_daily_assignments"
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM "FamilyMember" fm
            WHERE fm."familyId" = "truth_streak_daily_assignments"."familyId"
              AND fm."userId" = auth.uid()::text
        )
    );

CREATE POLICY "ts_assignments_insert" ON "truth_streak_daily_assignments"
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM "FamilyMember" fm
            WHERE fm."familyId" = "truth_streak_daily_assignments"."familyId"
              AND fm."userId" = auth.uid()::text
        )
    );

-- Answers: family members can read all answers for their family's assignments
CREATE POLICY "ts_answers_select" ON "truth_streak_answers"
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM "truth_streak_daily_assignments" a
            JOIN "FamilyMember" fm ON fm."familyId" = a."familyId"
            WHERE a.id = "truth_streak_answers"."assignmentId"
              AND fm."userId" = auth.uid()::text
        )
    );

-- Answers: users can only insert their own answers
CREATE POLICY "ts_answers_insert" ON "truth_streak_answers"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);

-- Stats: users can read and write only their own stats
CREATE POLICY "ts_stats_select" ON "truth_streak_user_stats"
    FOR SELECT USING ("userId" = auth.uid()::text);

CREATE POLICY "ts_stats_insert" ON "truth_streak_user_stats"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "ts_stats_update" ON "truth_streak_user_stats"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- Add to realtime publication for live answer reveals
ALTER PUBLICATION supabase_realtime ADD TABLE "truth_streak_answers";
ALTER PUBLICATION supabase_realtime ADD TABLE "truth_streak_daily_assignments";
