-- Hot Seat + Relation Riddles games — Supabase migration

-- ════════════════════════════════════════════════════════════════════
-- HOT SEAT — one member in the spotlight each day
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "hot_seat_daily" (
    id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"  TEXT NOT NULL,
    "userId"    TEXT NOT NULL,
    "userName"  TEXT NOT NULL DEFAULT 'Member',
    "assignedDate" DATE NOT NULL,
    "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("familyId", "assignedDate")
);

CREATE INDEX IF NOT EXISTS idx_hs_daily_family_date
    ON "hot_seat_daily"("familyId", "assignedDate");

CREATE TABLE IF NOT EXISTS "hot_seat_questions" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "assignmentId"  TEXT NOT NULL REFERENCES "hot_seat_daily"(id) ON DELETE CASCADE,
    "askerId"       TEXT NOT NULL,
    "askerName"     TEXT NOT NULL DEFAULT 'Member',
    question        TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hs_questions_assignment
    ON "hot_seat_questions"("assignmentId");

CREATE TABLE IF NOT EXISTS "hot_seat_answers" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "questionId"    TEXT NOT NULL REFERENCES "hot_seat_questions"(id) ON DELETE CASCADE,
    answer          TEXT NOT NULL,
    "answeredAt"    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("questionId")
);

-- RLS for Hot Seat
ALTER TABLE "hot_seat_daily" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "hot_seat_questions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "hot_seat_answers" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hs_daily_select" ON "hot_seat_daily"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "hot_seat_daily"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "hs_daily_insert" ON "hot_seat_daily"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "hot_seat_daily"."familyId" AND fm."userId" = auth.uid()::text)
    );

CREATE POLICY "hs_questions_select" ON "hot_seat_questions"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "hot_seat_daily" d JOIN "FamilyMember" fm ON fm."familyId" = d."familyId" WHERE d.id = "hot_seat_questions"."assignmentId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "hs_questions_insert" ON "hot_seat_questions"
    FOR INSERT WITH CHECK ("askerId" = auth.uid()::text);

CREATE POLICY "hs_answers_select" ON "hot_seat_answers"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "hot_seat_questions" q JOIN "hot_seat_daily" d ON d.id = q."assignmentId" JOIN "FamilyMember" fm ON fm."familyId" = d."familyId" WHERE q.id = "hot_seat_answers"."questionId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "hs_answers_insert" ON "hot_seat_answers"
    FOR INSERT WITH CHECK (TRUE);

ALTER PUBLICATION supabase_realtime ADD TABLE "hot_seat_questions";
ALTER PUBLICATION supabase_realtime ADD TABLE "hot_seat_answers";

-- ════════════════════════════════════════════════════════════════════
-- RELATION RIDDLES — daily kinship quiz
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "relation_riddle_daily" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"      TEXT NOT NULL,
    "personAId"     TEXT NOT NULL,
    "personBId"     TEXT NOT NULL,
    "personAName"   TEXT NOT NULL DEFAULT 'Member',
    "personBName"   TEXT NOT NULL DEFAULT 'Member',
    "correctAnswer" TEXT NOT NULL,
    "option1"       TEXT NOT NULL,
    "option2"       TEXT NOT NULL,
    "option3"       TEXT NOT NULL,
    "assignedDate"  DATE NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("familyId", "assignedDate")
);

CREATE INDEX IF NOT EXISTS idx_rr_daily_family_date
    ON "relation_riddle_daily"("familyId", "assignedDate");

CREATE TABLE IF NOT EXISTS "relation_riddle_attempts" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "riddleId"      TEXT NOT NULL REFERENCES "relation_riddle_daily"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "selectedAnswer" TEXT NOT NULL,
    "wasCorrect"    BOOLEAN NOT NULL,
    "attemptedAt"   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("riddleId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_rr_attempts_riddle
    ON "relation_riddle_attempts"("riddleId");

-- RLS for Relation Riddles
ALTER TABLE "relation_riddle_daily" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "relation_riddle_attempts" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rr_daily_select" ON "relation_riddle_daily"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "relation_riddle_daily"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "rr_daily_insert" ON "relation_riddle_daily"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "relation_riddle_daily"."familyId" AND fm."userId" = auth.uid()::text)
    );

CREATE POLICY "rr_attempts_select" ON "relation_riddle_attempts"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "relation_riddle_daily" d JOIN "FamilyMember" fm ON fm."familyId" = d."familyId" WHERE d.id = "relation_riddle_attempts"."riddleId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "rr_attempts_insert" ON "relation_riddle_attempts"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "relation_riddle_attempts";
