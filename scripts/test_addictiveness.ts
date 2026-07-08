// scripts/test_addictiveness.ts
//
// Addictiveness features validation (A-6 Festival + A-1 Blessing Chain + A-2 Time Capsule)
//
// Tests:
//   1. Seed the Festival table from festival-data.ts
//   2. Verify upcoming festivals are returned
//   3. Create a blessing scheduled for today (triggerDate = today)
//   4. Run deliverDueBlessings() → verify status flips to 'delivered'
//   5. Verify recurring blessing creates a new row for next year
//   6. Create a time capsule with revealAt in the past
//   7. Run revealDueCapsules() → verify status flips to 'revealed'
//   8. Clean up all test data

import { PrismaClient } from '@prisma/client';

const TEST_FAMILY_ID = 'cmr1xhyo7bivcw8rzx0hlguyi';
const TEST_USER_ID = '6c8ec41f-7163-45a5-8a12-7ac01da3dc77';
const TEST_MARKER = `addict-test-${Date.now()}`;

// Predictions
const PREDICTIONS = {
  expectedFestivalSeedCount: 13, // 13 festivals in festival-data.ts (diwali, holi, raksha_bandhan, ganesh_chaturthi, navratri, dussehra, eid_al_fitr, christmas, pongal, onam, janmashtami, republic_day, independence_day)
  expectedUpcomingFestivalsMin: 1, // at least 1 festival in the next 365 days
  expectedBlessingStatusAfterDelivery: 'delivered',
  expectedRecurringBlessingCreated: true,
  expectedCapsuleStatusAfterReveal: 'revealed',
};

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
  console.log('  Addictiveness Features Validation (A-6 + A-1 + A-2)');
  console.log('  Test family:', TEST_FAMILY_ID);
  console.log('  Test marker:', TEST_MARKER);
  console.log('═══════════════════════════════════════════════════════════════════════\n');

  // STEP 0: Cleanup
  console.log('▶ STEP 0: Cleanup...');
  const cleanupSqls = [
    `DELETE FROM "BlessingChain" WHERE "familyId"='${TEST_FAMILY_ID}' AND ("textContent" LIKE '%${TEST_MARKER}%' OR "festivalKey" = 'test-${TEST_MARKER}');`,
    `DELETE FROM "TimeCapsule" WHERE "familyId"='${TEST_FAMILY_ID}' AND "title" LIKE '%${TEST_MARKER}%';`,
    `DELETE FROM "Person" WHERE "familyId"='${TEST_FAMILY_ID}' AND "name" LIKE 'AddictTest%';`,
  ];
  for (const sql of cleanupSqls) {
    try { await runSql(sql); } catch (err) { console.warn('  cleanup warn:', err); }
  }
  console.log('  Cleanup done.');

  const dbUrl = process.env.DATABASE_URL || '';
  if (!dbUrl.startsWith('postgresql')) {
    console.log('\n⚠ DATABASE_URL not set — cannot run full validation.');
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
    // Instantiate services
    console.log('\n▶ Instantiating services...');
    const { FestivalService } = await import('../server/src/addictiveness/festival.service.ts');
    const { BlessingChainService } = await import('../server/src/addictiveness/blessing-chain.service.ts');
    const { TimeCapsuleService } = await import('../server/src/addictiveness/time-capsule.service.ts');

    const prismaService = prisma as any;
    const festivalService = new (FestivalService as any)(prismaService);
    const blessingChainService = new (BlessingChainService as any)(prismaService);
    const timeCapsuleService = new (TimeCapsuleService as any)(prismaService);

    // STEP 1: Seed festivals
    console.log('\n▶ STEP 1: Seeding festivals...');
    const seedResult = await festivalService.seedFestivals();
    console.log(`  Seeded ${seedResult.count} festivals (${seedResult.skipped} skipped)`);
    check('Festival seed count matches prediction', seedResult.count === PREDICTIONS.expectedFestivalSeedCount, `actual=${seedResult.count}`);

    // STEP 2: Get upcoming festivals
    console.log('\n▶ STEP 2: Getting upcoming festivals (next 365 days)...');
    const upcoming = await festivalService.getUpcomingFestivals(365);
    console.log(`  Found ${upcoming.length} upcoming festivals`);
    check('At least 1 upcoming festival', upcoming.length >= PREDICTIONS.expectedUpcomingFestivalsMin, `actual=${upcoming.length}`);
    if (upcoming.length > 0) {
      console.log(`  Next festival: ${upcoming[0].festivalKey} in ${upcoming[0].daysUntil} days`);
    }

    // STEP 3: Create a test elder Person + blessing scheduled for today
    console.log('\n▶ STEP 3: Creating test elder + blessing (scheduled for today)...');
    const elderInsertRes = await runSql(`
      INSERT INTO "Person" (id, "familyId", name, "isDeceased", "privacyLevel", "generationIndex", "isAnchor", "createdAt", "updatedAt")
      VALUES ('addict-test-elder-${TEST_MARKER}', '${TEST_FAMILY_ID}', 'AddictTestElder_${TEST_MARKER}', false, 'family', 0, false, NOW(), NOW())
      RETURNING id;
    `);
    const elderId = elderInsertRes[0].id;

    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    const blessing = await blessingChainService.createBlessing({
      familyId: TEST_FAMILY_ID,
      elderPersonId: elderId,
      recipientUserId: TEST_USER_ID,
      mediaType: 'text',
      textContent: `May you always find happiness. ${TEST_MARKER}`,
      triggerType: 'birthday',
      triggerDate: today,
      isRecurring: true,
      language: 'en',
    }, TEST_USER_ID);
    console.log(`  Created blessing ${blessing.id} (status=${blessing.status})`);
    check('Blessing status is pending', blessing.status === 'pending');

    // STEP 4: Run deliverDueBlessings()
    console.log('\n▶ STEP 4: Running deliverDueBlessings()...');
    const delivered = await blessingChainService.deliverDueBlessings();
    const myDelivered = delivered.filter((d) => d.blessingId === blessing.id);
    console.log(`  Delivered ${delivered.length} blessings total; my blessing delivered: ${myDelivered.length > 0}`);
    check('Blessing was delivered', myDelivered.length > 0);

    // Verify status flipped in DB
    const blessingAfter = await prismaService.blessingChain.findUnique({
      where: { id: blessing.id },
      select: { id: true, status: true, deliveredAt: true },
    });
    check('Blessing status is now delivered', blessingAfter.status === PREDICTIONS.expectedBlessingStatusAfterDelivery, `actual=${blessingAfter.status}`);

    // STEP 5: Verify recurring blessing created a new row for next year
    console.log('\n▶ STEP 5: Verifying recurring blessing created next year...');
    const recurringBlessings = await prismaService.blessingChain.findMany({
      where: {
        familyId: TEST_FAMILY_ID,
        elderPersonId: elderId,
        status: 'pending',
        isRecurring: true,
      },
    });
    const nextYearBlessing = recurringBlessings.find((b: any) => b.triggerDate.getUTCFullYear() === today.getUTCFullYear() + 1);
    check('Recurring blessing created for next year', !!nextYearBlessing, `found ${recurringBlessings.length} pending recurring blessings`);

    // STEP 6: Create a time capsule with revealAt in the FUTURE (service rejects past dates),
    // then backdate it via SQL to simulate time passing.
    console.log('\n▶ STEP 6: Creating time capsule (future reveal, then backdate via SQL)...');
    const futureDate = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000); // 1 year from now
    const capsule = await timeCapsuleService.createCapsule({
      familyId: TEST_FAMILY_ID,
      recipientUserId: TEST_USER_ID,
      mediaType: 'text',
      textContent: `A message from the past. ${TEST_MARKER}`,
      title: `AddictTest Capsule ${TEST_MARKER}`,
      revealAt: futureDate,
      revealReason: 'Test reveal',
    }, TEST_USER_ID);
    console.log(`  Created capsule ${capsule.id} (status=${capsule.status})`);
    check('Capsule status is locked', capsule.status === 'locked');

    // Backdate the revealAt to 1 minute ago (simulating time having passed)
    const pastIso = new Date(Date.now() - 60 * 1000).toISOString();
    await runSql(`
      UPDATE "TimeCapsule"
      SET "revealAt" = '${pastIso}'
      WHERE id = '${capsule.id}';
    `);
    console.log(`  Backdated capsule revealAt to ${pastIso}`);

    // STEP 7: Run revealDueCapsules()
    console.log('\n▶ STEP 7: Running revealDueCapsules()...');
    const revealed = await timeCapsuleService.revealDueCapsules();
    const myRevealed = revealed.filter((r) => r.capsuleId === capsule.id);
    console.log(`  Revealed ${revealed.length} capsules total; my capsule revealed: ${myRevealed.length > 0}`);
    check('Capsule was revealed', myRevealed.length > 0);

    // Verify status flipped
    const capsuleAfter = await prismaService.timeCapsule.findUnique({
      where: { id: capsule.id },
      select: { id: true, status: true, revealedAt: true },
    });
    check('Capsule status is now revealed', capsuleAfter.status === PREDICTIONS.expectedCapsuleStatusAfterReveal, `actual=${capsuleAfter.status}`);

    console.log(`\n  Total: ${pass} passed, ${fail} failed`);

  } catch (err) {
    console.error('💥 Test crashed:', err);
    fail++;
  } finally {
    await prisma.$disconnect();
  }

  // STEP 8: Final cleanup
  console.log('\n▶ STEP 8: Final cleanup...');
  const finalCleanup = [
    `DELETE FROM "BlessingChain" WHERE "familyId"='${TEST_FAMILY_ID}' AND ("textContent" LIKE '%${TEST_MARKER}%' OR "festivalKey" = 'test-${TEST_MARKER}');`,
    `DELETE FROM "TimeCapsule" WHERE "familyId"='${TEST_FAMILY_ID}' AND "title" LIKE '%${TEST_MARKER}%';`,
    `DELETE FROM "Person" WHERE "familyId"='${TEST_FAMILY_ID}' AND "name" LIKE 'AddictTest%';`,
  ];
  for (const sql of finalCleanup) {
    try { await runSql(sql); } catch (err) { console.warn('  cleanup warn:', err); }
  }
  console.log('  Cleanup done.');

  console.log('\n═══════════════════════════════════════════════════════════════════════');
  console.log('  Addictiveness Validation complete.');
  console.log('═══════════════════════════════════════════════════════════════════════\n');

  if (fail > 0) process.exit(1);
}

main().catch((err) => {
  console.error('💥 Script crashed:', err);
  process.exit(2);
});
