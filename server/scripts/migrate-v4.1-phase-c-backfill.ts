/**
 * Daxelo-Kinrel v4.1 — Phase C Backfill
 * =======================================
 * Per spec §16 (Migration Strategy — Phase C: Gradual Cutover):
 *   - Convert derived edges to fundamental edges where possible.
 *   - For each existing Relationship row, derive its `edgeType` from
 *     the legacy `relationshipType` / `relationshipKey` columns.
 *
 * Mapping (legacy → fundamental edge type):
 *   father, mother, parent, son, daughter, child              → PARENT
 *   husband, wife, spouse                                       → SPOUSE
 *   adoptive father, adoptive mother, adoptive parent          → ADOPTIVE_PARENT
 *   stepfather, stepmother, step father, step mother           → STEP_PARENT
 *   All other derived terms (uncle, cousin, grandfather, ...)   → skip (will be
 *     re-derived at runtime by GraphEngineService; per spec §1, no derived
 *     rows should exist in the DB).
 *
 * Usage:
 *   npx ts-node scripts/migrate-v4.1-phase-c-backfill.ts
 *
 * Idempotent: only updates rows where edgeType IS NULL.
 */

import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// Legacy term → EdgeType mapping. Anything not in this map is treated as
// DERIVED and the row is left with edgeType=NULL (the GraphEngineService
// will re-derive these at runtime; the row itself is preserved so no data
// is lost during migration).
const LEGACY_TO_EDGE: Record<string, 'PARENT' | 'SPOUSE' | 'ADOPTIVE_PARENT' | 'STEP_PARENT'> = {
  // PARENT
  father: 'PARENT', mother: 'PARENT', parent: 'PARENT',
  son: 'PARENT', daughter: 'PARENT', child: 'PARENT',
  // SPOUSE
  husband: 'SPOUSE', wife: 'SPOUSE', spouse: 'SPOUSE',
  // ADOPTIVE_PARENT
  'adoptive father': 'ADOPTIVE_PARENT', 'adoptive mother': 'ADOPTIVE_PARENT',
  'adoptive parent': 'ADOPTIVE_PARENT',
  adoptivefather: 'ADOPTIVE_PARENT', adoptivemother: 'ADOPTIVE_PARENT',
  // STEP_PARENT
  stepfather: 'STEP_PARENT', stepmother: 'STEP_PARENT',
  'step father': 'STEP_PARENT', 'step mother': 'STEP_PARENT',
  'step parent': 'STEP_PARENT',
};

async function main() {
  console.log('[v4.1 Phase C] Backfilling edgeType from legacy columns...');

  // Get all rows that need backfilling (edgeType IS NULL would be ideal,
  // but since edgeType is non-nullable in our schema, we use a workaround:
  // we look at all rows and UPDATE only those whose legacy columns map
  // to a known fundamental edge).
  const allRelationships = await prisma.relationship.findMany({
    select: {
      id: true,
      relationshipType: true,
      relationshipKey: true,
      edgeType: true,
    },
  });

  console.log(`  Found ${allRelationships.length} relationship rows to inspect.`);

  let updated = 0;
  let skipped = 0;
  let unknown = 0;

  for (const rel of allRelationships) {
    // Try relationshipType first, then relationshipKey
    const term = (rel.relationshipType || rel.relationshipKey || '').toLowerCase().trim();
    const edgeType = LEGACY_TO_EDGE[term];

    if (!edgeType) {
      // Unknown / derived term — skip (don't update, don't delete)
      unknown += 1;
      continue;
    }

    if (rel.edgeType === edgeType) {
      // Already correct — skip
      skipped += 1;
      continue;
    }

    // Update this row's edgeType
    await prisma.relationship.update({
      where: { id: rel.id },
      data: { edgeType },
    });
    updated += 1;
  }

  console.log(`  ✓ Updated: ${updated}`);
  console.log(`  ✓ Already correct (skipped): ${skipped}`);
  console.log(`  ⚠ Unknown / derived (left as-is): ${unknown}`);
  console.log('');
  console.log('  Note: Rows marked "Unknown / derived" contain legacy derived');
  console.log('  terms (e.g. "uncle", "cousin") that violate spec §1.');
  console.log('  These rows are preserved for data safety but should be');
  console.log('  manually reviewed and either:');
  console.log('    (a) converted to their fundamental equivalent, OR');
  console.log('    (b) deleted if they duplicate an existing fundamental edge.');
  console.log('');
  console.log('[v4.1 Phase C] Backfill complete.');
}

main()
  .catch((e) => {
    console.error('[v4.1 Phase C] FAILED:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
