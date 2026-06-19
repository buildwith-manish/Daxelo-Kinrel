-- ============================================================
-- Migration: sparq_enhancement_columns_and_echo_table
-- Version:  20260612020447
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

-- AlterTable: Add new columns to Sparq
ALTER TABLE "Sparq" ADD COLUMN "mood" "SparqMood" NOT NULL DEFAULT 'happy';
ALTER TABLE "Sparq" ADD COLUMN "intensity" "SparqIntensity" NOT NULL DEFAULT 'warm';
ALTER TABLE "Sparq" ADD COLUMN "allowChain" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Sparq" ADD COLUMN "allowReplies" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "Sparq" ADD COLUMN "isTimeCapsule" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Sparq" ADD COLUMN "revealAt" TIMESTAMP(3);
ALTER TABLE "Sparq" ADD COLUMN "isRevealed" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Sparq" ADD COLUMN "parentSparqId" TEXT;
ALTER TABLE "Sparq" ADD COLUMN "chainOrder" INTEGER;
ALTER TABLE "Sparq" ADD COLUMN "echoCount" INTEGER NOT NULL DEFAULT 0;

-- CreateTable: SparqEcho
CREATE TABLE "SparqEcho" (
    "id" TEXT NOT NULL DEFAULT (gen_random_uuid())::text,
    "sparqId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SparqEcho_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SparqEcho_sparqId_userId_key" ON "SparqEcho"("sparqId", "userId");
CREATE INDEX "SparqEcho_sparqId_idx" ON "SparqEcho"("sparqId");
CREATE INDEX "SparqEcho_userId_idx" ON "SparqEcho"("userId");

-- AddForeignKey: SparqEcho -> Sparq
ALTER TABLE "SparqEcho" ADD CONSTRAINT "SparqEcho_sparqId_fkey" FOREIGN KEY ("sparqId") REFERENCES "Sparq"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: SparqEcho -> User
ALTER TABLE "SparqEcho" ADD CONSTRAINT "SparqEcho_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: Sparq self-relation for chains
ALTER TABLE "Sparq" ADD CONSTRAINT "Sparq_parentSparqId_fkey" FOREIGN KEY ("parentSparqId") REFERENCES "Sparq"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateIndex for chain and time capsule queries
CREATE INDEX "Sparq_parentSparqId_idx" ON "Sparq"("parentSparqId");
CREATE INDEX "Sparq_isTimeCapsule_isRevealed_idx" ON "Sparq"("isTimeCapsule", "isRevealed");
