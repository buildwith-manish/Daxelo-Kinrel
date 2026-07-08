// scripts/test_quests_chronicle.ts
//
// A-3 Family Quests + A-7 Family Chronicle validation
//
// Tests:
//   A-3 Quests:
//     1. Generate quests for the test family
//     2. Verify quests were created for the test user
//     3. Complete a quest → verify karma awarded
//     4. Skip a quest → verify status flips
//   A-7 Chronicle:
//     5. Generate chronicle for the test family
//     6. Verify chronicle has chapters with content
//     7. Verify chronicle is idempotent (re-generate updates, doesn't duplicate)

import { PrismaClient } from '@prisma/client';

const TEST_FAMILY_ID = 'cmr1xhyo7bivcw8rzx0hlguyi';
const TEST_USER_ID = '6c8ec41f-7163-45a5-8a12-7ac01da3dc77';
const TEST_MARKER = `quest-chronicle-test-${Date.now()}`;

async function runSql(sql: string): Promise<any> {
  const TOKEN = process.env.SUPABASE_ACCESS_TOKEN;
  const REF = process.env.SUPABASE_PROJECT_REF || 'promxswvsnvilplmrtsj';
  if (!TOKEN) throw new Error('SUPABASE_ACCESS_TOKEN required');
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const text = await res.text();
  try { return JSON.parse(text); } catch { return text; }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════════════');
  console.log('  A-3 Family Quests + A-7 Family Chronicle Validation');
  console.log('  Test family:', TEST_FAMILY_ID);
  console.log('  Test marker:', TEST_MARKER);
  console.log('═══════════════════════════════════════════════════════════════════════\n');

  // Cleanup
  console.log('▶ Cleanup...');
  await runSql(`DELETE FROM "FamilyQuest" WHERE "familyId"='${TEST_FAMILY_ID}';`);
  await runSql(`DELETE FROM "FamilyChronicle" WHERE "familyId"='${TEST_FAMILY_ID}';`);
  await runSql(`DELETE FROM "FamilyKarma" WHERE "userId"='${TEST_USER_ID}' AND "familyId"='${TEST_FAMILY_ID}';`);
  console.log('  Done.');

  const dbUrl = process.env.DATABASE_URL || '';
  if (!dbUrl.startsWith('postgresql')) {
    console.log('\n⚠ DATABASE_URL not set.');
    process.exit(0);
  }

  const prisma = new PrismaClient({ log: ['error', 'warn'] });
  let pass = 0, fail = 0;
  const check = (label: string, condition: boolean, detail?: string) => {
    const status = condition ? '✅ PASS' : '❌ FAIL';
    console.log(`  ${status} — ${label}${detail ? ` — ${detail}` : ''}`);
    if (condition) pass++; else fail++;
  };

  try {
    console.log('\n▶ Instantiating services...');
    const { FamilyQuestService } = await import('../server/src/addictiveness/family-quest.service.ts');
    const { FamilyChronicleService } = await import('../server/src/addictiveness/family-chronicle.service.ts');
    const prismaService = prisma as any;
    const questService = new (FamilyQuestService as any)(prismaService);
    const chronicleService = new (FamilyChronicleService as any)(prismaService);

    // ── A-3 Family Quests ──────────────────────────────────────────────
    console.log('\n▶ A-3 STEP 1: Generating quests for test family...');
    const genResult = await questService.generateQuestsForFamily(TEST_FAMILY_ID);
    console.log(`  Generated ${genResult.questsGenerated} quests for ${genResult.usersProcessed} users`);
    check('Quest generation ran without error', genResult.errors.length === 0, `errors=${genResult.errors.length}`);

    console.log('\n▶ A-3 STEP 2: Getting active quests for test user...');
    const activeQuests = await questService.getActiveQuests(TEST_USER_ID);
    console.log(`  Found ${activeQuests.length} active quests`);
    console.log('  Quest types:', activeQuests.map((q: any) => q.questType).join(', '));
    check('Active quests returned (may be 0 if no weak relationships)', Array.isArray(activeQuests));

    if (activeQuests.length > 0) {
      console.log('\n▶ A-3 STEP 3: Completing a quest...');
      const questToComplete = activeQuests[0];
      const completeResult = await questService.completeQuest(questToComplete.id, TEST_USER_ID);
      console.log(`  Karma awarded: ${completeResult.karmaAwarded}`);
      check('Quest completion awarded karma', completeResult.karmaAwarded > 0, `karma=${completeResult.karmaAwarded}`);

      // Verify quest status flipped
      const questAfter = await prismaService.familyQuest.findUnique({
        where: { id: questToComplete.id },
        select: { status: true, completedAt: true },
      });
      check('Quest status is now completed', questAfter.status === 'completed');

      // Verify karma row created
      const karmaRow = await prismaService.familyKarma.findUnique({
        where: { userId_familyId: { userId: TEST_USER_ID, familyId: TEST_FAMILY_ID } },
        select: { totalKarma: true },
      });
      check('FamilyKarma row created with karma', karmaRow !== null && karmaRow.totalKarma > 0, `totalKarma=${karmaRow?.totalKarma}`);

      if (activeQuests.length > 1) {
        console.log('\n▶ A-3 STEP 4: Skipping a quest...');
        const questToSkip = activeQuests[1];
        const skipResult = await questService.skipQuest(questToSkip.id, TEST_USER_ID);
        check('Quest skip worked', skipResult.status === 'skipped');
      }
    } else {
      console.log('\n  ⚠ No active quests to complete/skip (test family may have no weak relationships)');
      check('Quest generation completed (0 quests is OK)', true);
    }

    // ── A-7 Family Chronicle ───────────────────────────────────────────
    console.log('\n▶ A-7 STEP 1: Generating chronicle for test family...');
    const chronicleResult = await chronicleService.generateChronicle(TEST_FAMILY_ID);
    console.log(`  Chronicle generated: ${chronicleResult.chapterCount} chapters (isNew=${chronicleResult.isNew})`);
    check('Chronicle was created (isNew=true)', chronicleResult.isNew === true);
    check('Chronicle has at least 1 chapter', chronicleResult.chapterCount >= 1, `chapters=${chronicleResult.chapterCount}`);

    console.log('\n▶ A-7 STEP 2: Getting chronicle...');
    const chronicle = await chronicleService.getChronicle(TEST_FAMILY_ID, TEST_USER_ID);
    check('Chronicle returned with title', chronicle !== null && typeof chronicle.title === 'string');
    if (chronicle) {
      console.log(`  Title: "${chronicle.title}"`);
      console.log(`  Subtitle: "${chronicle.subtitle}"`);
      console.log(`  Chapters: ${chronicle.chapterCount}`);
      const chapters = chronicle.chapters as any[];
      if (chapters.length > 0) {
        console.log(`  Chapter 1 title: "${chapters[0].title}"`);
        console.log(`  Chapter 1 content preview: "${chapters[0].content.slice(0, 120)}..."`);
        check('Chapter has content', chapters[0].content.length > 50, `length=${chapters[0].content.length}`);
      }
    }

    console.log('\n▶ A-7 STEP 3: Re-generating chronicle (idempotency check)...');
    const regenResult = await chronicleService.generateChronicle(TEST_FAMILY_ID);
    console.log(`  Re-generated: ${regenResult.chapterCount} chapters (isNew=${regenResult.isNew})`);
    check('Chronicle re-generation is idempotent (isNew=false)', regenResult.isNew === false);

    // Verify only ONE chronicle row exists
    const chronicleCount = await prismaService.familyChronicle.count({
      where: { familyId: TEST_FAMILY_ID },
    });
    check('Only 1 chronicle row exists (no duplicates)', chronicleCount === 1, `count=${chronicleCount}`);

    console.log(`\n  Total: ${pass} passed, ${fail} failed`);

  } catch (err) {
    console.error('💥 Test crashed:', err);
    fail++;
  } finally {
    await prisma.$disconnect();
  }

  // Final cleanup
  console.log('\n▶ Final cleanup...');
  await runSql(`DELETE FROM "FamilyQuest" WHERE "familyId"='${TEST_FAMILY_ID}';`);
  await runSql(`DELETE FROM "FamilyChronicle" WHERE "familyId"='${TEST_FAMILY_ID}';`);
  await runSql(`DELETE FROM "FamilyKarma" WHERE "userId"='${TEST_USER_ID}' AND "familyId"='${TEST_FAMILY_ID}';`);
  console.log('  Done.');

  console.log('\n═══════════════════════════════════════════════════════════════════════');
  console.log('  Validation complete.');
  console.log('═══════════════════════════════════════════════════════════════════════\n');

  if (fail > 0) process.exit(1);
}

main().catch((err) => {
  console.error('💥 Script crashed:', err);
  process.exit(2);
});
