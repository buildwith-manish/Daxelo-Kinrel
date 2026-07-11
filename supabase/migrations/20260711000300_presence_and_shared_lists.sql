-- =============================================================================
-- Shared List / Errand Board + Presence Signal
-- =============================================================================

-- ── SharedList table ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."SharedList" (
    id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    familyId    TEXT NOT NULL,
    title       TEXT NOT NULL,
    emoji       TEXT DEFAULT '📋',
    createdBy   TEXT NOT NULL,
    createdAt   TIMESTAMPTZ DEFAULT now(),
    updatedAt   TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public."SharedList" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "SharedList_select" ON public."SharedList" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "SharedList"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "SharedList_insert" ON public."SharedList" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "SharedList"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "SharedList_update" ON public."SharedList" FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "SharedList"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "SharedList_delete" ON public."SharedList" FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "SharedList"."familyId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public."SharedList" TO authenticated;
CREATE INDEX IF NOT EXISTS "SharedList_familyId_idx" ON public."SharedList"("familyId");

-- ── SharedListItem table ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."SharedListItem" (
    id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    listId      TEXT NOT NULL REFERENCES public."SharedList"(id) ON DELETE CASCADE,
    text        TEXT NOT NULL,
    isDone      BOOLEAN DEFAULT false,
    doneBy      TEXT,
    createdAt   TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public."SharedListItem" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "SharedListItem_select" ON public."SharedListItem" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."SharedList" sl
             JOIN public."FamilyMember" fm ON fm."familyId" = sl."familyId"
             WHERE sl.id = "SharedListItem"."listId" AND fm."userId" = auth.uid())
);
CREATE POLICY "SharedListItem_insert" ON public."SharedListItem" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."SharedList" sl
             JOIN public."FamilyMember" fm ON fm."familyId" = sl."familyId"
             WHERE sl.id = "SharedListItem"."listId" AND fm."userId" = auth.uid())
);
CREATE POLICY "SharedListItem_update" ON public."SharedListItem" FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."SharedList" sl
             JOIN public."FamilyMember" fm ON fm."familyId" = sl."familyId"
             WHERE sl.id = "SharedListItem"."listId" AND fm."userId" = auth.uid())
);
CREATE POLICY "SharedListItem_delete" ON public."SharedListItem" FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."SharedList" sl
             JOIN public."FamilyMember" fm ON fm."familyId" = sl."familyId"
             WHERE sl.id = "SharedListItem"."listId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public."SharedListItem" TO authenticated;
CREATE INDEX IF NOT EXISTS "SharedListItem_listId_idx" ON public."SharedListItem"("listId");

-- ── Presence columns on FamilyMember ────────────────────────────────────
ALTER TABLE public."FamilyMember"
    ADD COLUMN IF NOT EXISTS "presenceStatus" TEXT DEFAULT 'away',
    ADD COLUMN IF NOT EXISTS "presenceUpdatedAt" TIMESTAMPTZ DEFAULT now();
