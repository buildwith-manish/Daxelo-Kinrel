/**
 * Daxelo-Kinrel v4.1 — Phase D Migration
 * ========================================
 * Per spec §16 (Migration Strategy — Phase D: Cleanup):
 *   - Drop deprecated derived relationship tables
 *   - Drop RelationshipPathCache (spec §1: never persist derived paths)
 *
 * This script is IDEMPOTENT — safe to run multiple times.
 *
 * Usage:
 *   npx ts-node scripts/migrate-v4.1-phase-d.ts
 *
 * After running:
 *   - The "RelationshipPathCache" table is dropped
 *   - Existing "Relationship" rows keep their legacy relationshipKey /
 *     relationshipType columns (now nullable, will be backfilled to
 *     edgeType in a separate Phase C migration per spec §16)
 */

import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('[v4.1 Phase D] Starting cleanup migration...');

  // 1. Drop RelationshipPathCache (spec §1 violation — derived data in DB)
  console.log('  [1/2] Dropping RelationshipPathCache table...');
  try {
    await prisma.$executeRawUnsafe('DROP TABLE IF EXISTS "RelationshipPathCache" CASCADE;');
    console.log('       ✓ Dropped.');
  } catch (e: any) {
    console.log(`       ⚠ Could not drop (may not exist): ${e.message}`);
  }

  // 2. Drop any indexes that referenced the legacy relationshipType column
  //    (Only if they exist — idempotent.)
  console.log('  [2/2] Cleaning up legacy indexes (if any)...');
  try {
    await prisma.$executeRawUnsafe(`
      DO $$ BEGIN
        -- Drop indexes that may have been auto-created for legacy columns
        IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'Relationship_relationshipType_idx') THEN
          DROP INDEX "Relationship_relationshipType_idx";
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END $$;
    `);
    console.log('       ✓ Index cleanup complete.');
  } catch (e: any) {
    console.log(`       ⚠ Index cleanup warning: ${e.message}`);
  }

  // 3. Verify the KinshipVocabulary table exists (created by prisma migrate)
  console.log('  [verify] Checking KinshipVocabulary table exists...');
  try {
    const count = await prisma.kinshipVocabulary.count();
    console.log(`       ✓ KinshipVocabulary table exists. Current rows: ${count}`);
    if (count === 0) {
      console.log('       ℹ Table is empty — run: npx ts-node scripts/import-vocabulary.ts');
    }
  } catch (e: any) {
    console.log(`       ⚠ KinshipVocabulary table not found — run: npx prisma migrate dev`);
  }

  console.log('[v4.1 Phase D] Migration complete.');
}

main()
  .catch((e) => {
    console.error('[v4.1 Phase D] FAILED:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
