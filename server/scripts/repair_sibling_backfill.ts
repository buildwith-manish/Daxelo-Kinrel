// scripts/repair_sibling_backfill.ts
//
// v5.129 §5: One-time repair pass for existing broken sibling data.
//
// Finds all active brother/sister relationships where neither sibling has
// a recorded parent, and applies the same backfill logic as the live
// create() path:
//   - If one sibling has parents → link the other under them.
//   - If neither has parents → create a placeholder parent + link both.
//   - If both have different parents → flag for review.
//
// Usage:
//   DATABASE_URL="postgresql://..." npx ts-node scripts/repair_sibling_backfill.ts
//
// Or via bun:
//   DATABASE_URL="postgresql://..." bun run scripts/repair_sibling_backfill.ts
//
// Run once against existing data. After this, all future sibling additions
// are handled by the live create() path in relationships.service.ts.

import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('=== Sibling Backfill Repair Script (v5.129 §5) ===\n');

  // Find all active brother/sister relationships.
  const siblingEdges = await prisma.relationship.findMany({
    where: {
      relationshipKey: { in: ['brother', 'sister'] },
      isActive: true,
      fromPerson: { deletedAt: null },
      toPerson: { deletedAt: null },
    },
    include: {
      fromPerson: true,
      toPerson: true,
    },
  });

  console.log(`Found ${siblingEdges.length} active sibling edges.\n`);

  let backfilled = 0;
  let placeholderCreated = 0;
  let flagged = 0;
  let skipped = 0;

  for (const edge of siblingEdges) {
    const fromParents = await findParentsOf(edge.fromPersonId);
    const toParents = await findParentsOf(edge.toPersonId);

    const fromHas = fromParents.length > 0;
    const toHas = toParents.length > 0;

    if (fromHas && toHas) {
      // Both have parents → check if shared
      const sharedCount = toParents.filter(p =>
        fromParents.some(fp => fp.id === p.id)
      ).length;
      if (sharedCount === 0) {
        // Different parents → flag for review
        try {
          await prisma.relationshipReviewFlag.create({
            data: {
              familyId: edge.familyId,
              sourceRelationshipId: edge.id,
              parentAPersonId: fromParents[0].id,
              parentBPersonId: toParents[0].id,
              reason: 'sibling_parent_mismatch',
              status: 'pending',
            },
          });
          flagged++;
          console.log(`  FLAGGED edge ${edge.id}: both have different parents`);
        } catch (err: any) {
          // Unique constraint = already flagged
          skipped++;
        }
      } else {
        skipped++;
      }
    } else if (fromHas && !toHas) {
      // Link toPerson under fromPerson's parents
      for (const parent of fromParents) {
        await createParentChildEdgePair(parent, edge.toPerson, edge.familyId);
      }
      backfilled++;
      console.log(`  BACKFILLED edge ${edge.id}: linked ${edge.toPersonId} under ${fromParents.length} parents`);
    } else if (toHas && !fromHas) {
      // Link fromPerson under toPerson's parents
      for (const parent of toParents) {
        await createParentChildEdgePair(parent, edge.fromPerson, edge.familyId);
      }
      backfilled++;
      console.log(`  BACKFILLED edge ${edge.id}: linked ${edge.fromPersonId} under ${toParents.length} parents`);
    } else {
      // Neither has parents → create placeholder
      const minGen = Math.min(
        edge.fromPerson.generationIndex,
        edge.toPerson.generationIndex,
      );
      const placeholder = await prisma.person.create({
        data: {
          familyId: edge.familyId,
          name: 'Unknown parent',
          isPlaceholder: true,
          gender: null,
          generationIndex: minGen - 1,
        },
      });
      await createParentChildEdgePair(
        { id: placeholder.id, relationshipKey: 'father' },
        edge.fromPerson,
        edge.familyId,
      );
      await createParentChildEdgePair(
        { id: placeholder.id, relationshipKey: 'father' },
        edge.toPerson,
        edge.familyId,
      );
      placeholderCreated++;
      backfilled++;
      console.log(`  PLACEHOLDER edge ${edge.id}: created placeholder ${placeholder.id}`);
    }
  }

  console.log(`\n=== Summary ===`);
  console.log(`  Total sibling edges: ${siblingEdges.length}`);
  console.log(`  Backfilled (real parent): ${backfilled - placeholderCreated}`);
  console.log(`  Placeholder created: ${placeholderCreated}`);
  console.log(`  Flagged for review: ${flagged}`);
  console.log(`  Skipped (already OK or already flagged): ${skipped}`);
  console.log(`\nDone.`);
}

async function findParentsOf(personId: string): Promise<Array<{ id: string; relationshipKey: string }>> {
  const forward = await prisma.relationship.findMany({
    where: { fromPersonId: personId, relationshipKey: { in: ['father', 'mother'] }, isActive: true },
    select: { toPersonId: true, relationshipKey: true },
  });
  const inverse = await prisma.relationship.findMany({
    where: { toPersonId: personId, relationshipKey: { in: ['son', 'daughter'] }, isActive: true },
    select: { fromPersonId: true, relationshipKey: true },
  });
  const map = new Map<string, { id: string; relationshipKey: string }>();
  for (const e of forward) {
    if (!map.has(e.toPersonId)) map.set(e.toPersonId, { id: e.toPersonId, relationshipKey: e.relationshipKey });
  }
  for (const e of inverse) {
    if (!map.has(e.fromPersonId)) map.set(e.fromPersonId, { id: e.fromPersonId, relationshipKey: 'father' });
  }
  return Array.from(map.values());
}

async function createParentChildEdgePair(
  parent: { id: string; relationshipKey: string },
  child: { id: string; gender: string | null },
  familyId: string,
) {
  const forwardKey = parent.relationshipKey;
  const inverseKey = child.gender === 'female'
    ? 'daughter'
    : 'son';

  const existingFwd = await prisma.relationship.findFirst({
    where: { familyId, fromPersonId: child.id, toPersonId: parent.id, relationshipKey: forwardKey },
  });
  if (!existingFwd) {
    await prisma.relationship.create({
      data: { familyId, fromPersonId: child.id, toPersonId: parent.id, relationshipKey: forwardKey, direction: 'from', isActive: true, isInferred: true },
    });
  }

  const existingInv = await prisma.relationship.findFirst({
    where: { familyId, fromPersonId: parent.id, toPersonId: child.id, relationshipKey: inverseKey },
  });
  if (!existingInv) {
    await prisma.relationship.create({
      data: { familyId, fromPersonId: parent.id, toPersonId: child.id, relationshipKey: inverseKey, direction: 'from', isActive: true, isInferred: true },
    });
  }
}

main()
  .catch((e) => {
    console.error('Repair script failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
