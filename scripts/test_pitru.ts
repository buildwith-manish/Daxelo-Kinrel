// scripts/test_pitru.ts
//
// PITRU Phase 1 Validation Script
//
// Tests:
//   1. Insert a test AncestralMemory (1 year ago today, status=ready, isRevealed=true)
//   2. Verify GET /pitru/memories returns it
//   3. Test tagPerson (tag the test elder Person in the memory)
//   4. Test setConsent (grant ai_persona consent)
//   5. Generate a brief via BriefGeneratorService
//   6. Verify the brief now contains a memory_orbit item (previously was [])
//   7. Clean up all test rows
//
// Usage:
//   cd server
//   DATABASE_URL='postgresql://...' \
//   SUPABASE_ACCESS_TOKEN='sbp_...' \
//   SUPABASE_PROJECT_REF='promxswvsnvilplmrtsj' \
//   bun run ../scripts/test_pitru.ts

import { PrismaClient } from '@prisma/client';

const TEST_FAMILY_ID = 'cmr1xhyo7bivcw8rzx0hlguyi';
const TEST_USER_ID = '6c8ec41f-7163-45a5-8a12-7ac01da3dc77';
const TEST_MARKER = `pitru-test-${Date.now()}`;

// ─────────────────────────────────────────────────────────────────────────────
// Predictions
// ─────────────────────────────────────────────────────────────────────────────
// We insert:
//   1. A test Person "PitruTestElder_*" (elder, not deceased)
//   2. An AncestralMemory with createdAt = 1 year ago today, status='ready',
//      isRevealed=true, elderPersonId=test Person, mediaType='audio',
//      durationSec=120, topic='wedding', aiSummary='Story about her wedding day.'
//
// Predictions:
//   - PitruService.createMemory() succeeds, returns a memory with status='pending'
//     (we'll then PATCH it to 'ready' via updateAiResults)
//   - PitruService.listMemories() returns 1 memory
//   - tagPerson() creates a MemoryTag with tagType='mentions'
//   - setConsent('ai_persona', true) creates a MemoryConsent row
//   - BriefGeneratorService.generateBriefForUser() now produces a brief with
//     a memory_orbit item (was previously [] because no memories existed)
//   - The memory_orbit item should have:
//       itemType: 'memory_orbit'
//       priority: 70
//       actionType: 'listen_memory'
//       title containing "PitruTestElder"
//       relevanceScore = 0.65 (because test user has no linkedPerson → closeness=0.5,
//                              but we use Math.max(0.65, closeness.total) = 0.65)

const PREDICTIONS = {
  expectedMemoryStatus: 'pending',
  expectedMemoryStatusAfterAi: 'ready',
  expectedListItemCount: 1,
  expectedTagType: 'mentions',
  expectedConsentGiven: true,
  expectedBriefHasMemoryOrbit: true,
  expectedMemoryOrbitPriority: 70,
  expectedMemoryOrbitActionType: 'listen_memory',
  expectedMemoryOrbitRelevance: 0.65,
};

// ─────────────────────────────────────────────────────────────────────────────
// Supabase Management API (for raw SQL when needed)
// ────────────────────────────────────────────────────────────────────────────
const SUPABASE_TOKEN = process.env.SUPABASE_ACCESS_TOKEN;
const SUPABASE_REF = process.env.SUPABASE_PROJECT_REF || 'promxswvsnvilplmrtsj';

async function runSql(sql: string): Promise<any> {
  if (SUPABASE_TOKEN) {
    const res = await fetch(
      `https://api.supabase.com/v1/projects/${SUPABASE_REF}/database/query`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${SUPABASE_TOKEN}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ query: sql }),
      },
    );
    const text = await res.text();
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }
  throw new Error('No SQL backend available');
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log('═══════════════════════════════════════════════════════════════════════');
  console.log('  PITRU Phase 1 Validation Script');
  console.log('  Test family:', TEST_FAMILY_ID);
  console.log('  Test user  :', TEST_USER_ID);
  console.log('  Test marker:', TEST_MARKER);
  console.log('═══════════════════════════════════════════════════════════════════════\n');

  // STEP 0: Upfront cleanup
  console.log('▶ STEP 0: Upfront cleanup...');
  const cleanupSqls = [
    `DELETE FROM "MemoryTag" WHERE "memoryId" IN (SELECT id FROM "AncestralMemory" WHERE "familyId"='${TEST_FAMILY_ID}' AND "title" LIKE 'PitruTest%');`,
    `DELETE FROM "MemoryConsent" WHERE "familyId"='${TEST_FAMILY_ID}' AND "consentNotes" LIKE '%${TEST_MARKER}%';`,
    `DELETE FROM "AncestralMemory" WHERE "familyId"='${TEST_FAMILY_ID}' AND "title" LIKE 'PitruTest%';`,
    `DELETE FROM "Person" WHERE "familyId"='${TEST_FAMILY_ID}' AND "name" LIKE 'PitruTest%';`,
    // Also clean any Pulse test data from previous runs
    `DELETE FROM "BriefInteraction" WHERE "userId"='${TEST_USER_ID}';`,
    `DELETE FROM "BriefItem" WHERE "userId"='${TEST_USER_ID}';`,
    `DELETE FROM "DailyBrief" WHERE "userId"='${TEST_USER_ID}';`,
    `DELETE FROM "FamilyKarma" WHERE "userId"='${TEST_USER_ID}';`,
  ];
  for (const sql of cleanupSqls) {
    try { await runSql(sql); } catch (err) { console.warn('  cleanup warn:', err); }
  }
  console.log('  Cleanup done.');

  // STEP 1: Insert test elder Person
  console.log('\n▶ STEP 1: Inserting test elder Person...');
  const elderInsertRes = await runSql(`
    INSERT INTO "Person" (id, "familyId", name, "isDeceased", "privacyLevel", "generationIndex", "isAnchor", "createdAt", "updatedAt")
    VALUES ('pitru-test-elder-${TEST_MARKER}', '${TEST_FAMILY_ID}', 'PitruTestElder_${TEST_MARKER}', false, 'family', 0, false, NOW(), NOW())
    RETURNING id, name;
  `);
  console.log('  Inserted elder Person:', JSON.stringify(elderInsertRes));

  const dbUrl = process.env.DATABASE_URL || '';
  const isPlaceholder = dbUrl.includes('PLACEHOLDER') || !dbUrl.startsWith('postgresql');
  if (isPlaceholder) {
    console.log('\n⚠ DATABASE_URL not set — cannot run PitruService directly.');
    console.log('  Set DATABASE_URL with the real Supabase DB password to enable validation.');
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
    // STEP 2: Instantiate services
    console.log('\n▶ STEP 2: Instantiating PitruService + BriefGeneratorService...');
    const { EventEmitter2 } = await import('@nestjs/event-emitter');
    const eventEmitter = new EventEmitter2();
    const { PitruService } = await import('../server/src/pitru/pitru.service.ts');
    const { BriefGeneratorService } = await import('../server/src/pulse/brief-generator.service.ts');
    const { BirthdayCollector } = await import('../server/src/pulse/collectors/birthday.collector.ts');
    const { InactivityCollector } = await import('../server/src/pulse/collectors/inactivity.collector.ts');
    const { FeedHighlightCollector } = await import('../server/src/pulse/collectors/feed-highlight.collector.ts');
    const { OnThisDayCollector } = await import('../server/src/pulse/collectors/on-this-day.collector.ts');
    const { WeatherCollector } = await import('../server/src/pulse/collectors/weather.collector.ts');
    const { MemoryOrbitCollector } = await import('../server/src/pulse/collectors/memory-orbit.collector.ts');
    const { PersonalizationService } = await import('../server/src/pulse/personalization.service.ts');

    const prismaService = prisma as any;
    const personalization = new (PersonalizationService as any)(prismaService);
    const pitru = new (PitruService as any)(prismaService);
    const generator = new (BriefGeneratorService as any)(prismaService, eventEmitter, personalization);
    const collectors = [
      new (BirthdayCollector as any)(prismaService),
      new (InactivityCollector as any)(prismaService),
      new (FeedHighlightCollector as any)(prismaService),
      new (OnThisDayCollector as any)(prismaService),
      new (WeatherCollector as any)(prismaService),
      new (MemoryOrbitCollector as any)(prismaService),
    ];
    generator.setCollectors(collectors);

    // STEP 3: Create a memory
    console.log('\n▶ STEP 3: Creating a test memory...');
    // Use a createdAt 1 year ago (we'll insert directly via SQL after createMemory
    // to backdate it — PitruService.createMemory sets createdAt=NOW() by default,
    // but we need it to be 1 year ago for the anniversary logic to fire).
    const createdMemory = await pitru.createMemory({
      familyId: TEST_FAMILY_ID,
      recorderId: TEST_USER_ID,
      elderPersonId: `pitru-test-elder-${TEST_MARKER}`,
      mediaType: 'audio',
      mediaUrl: 'https://example.com/test-memory.mp3',
      durationSec: 120,
      title: `PitruTest wedding story ${TEST_MARKER}`,
      topic: 'wedding',
      language: 'en',
      description: 'Test memory for Pitru validation',
    });
    console.log('  Created memory:', createdMemory.id, 'status=', createdMemory.status);
    check('Memory status is pending (just created)', createdMemory.status === PREDICTIONS.expectedMemoryStatus);

    // Backdate the memory to 1 year ago today (so the anniversary logic fires)
    const oneYearAgo = new Date();
    oneYearAgo.setUTCFullYear(oneYearAgo.getUTCFullYear() - 1);
    await runSql(`
      UPDATE "AncestralMemory"
      SET "createdAt" = '${oneYearAgo.toISOString()}'
      WHERE id = '${createdMemory.id}';
    `);
    console.log('  Backdated memory to 1 year ago:', oneYearAgo.toISOString());

    // STEP 4: Update AI results (simulate the AI pipeline finishing)
    console.log('\n▶ STEP 4: Updating AI results (simulate pipeline)...');
    const updatedMemory = await pitru.updateAiResults(createdMemory.id, {
      transcript: 'This is a test transcript of the wedding story.',
      transcriptLanguage: 'en',
      translation: 'This is a test transcript of the wedding story.',
      aiSummary: 'Story about her wedding day.',
      aiTags: ['wedding', '1962', 'monsoon'],
      status: 'ready',
    });
    console.log('  Updated memory status:', updatedMemory.status);
    check('Memory status is ready after AI update', updatedMemory.status === PREDICTIONS.expectedMemoryStatusAfterAi);

    // STEP 5: List memories
    console.log('\n▶ STEP 5: Listing memories...');
    const memories = await pitru.listMemories(TEST_USER_ID, TEST_FAMILY_ID, {});
    console.log(`  Listed ${memories.length} memories (expecting ≥1)`);
    check('listMemories returns at least 1 memory', memories.length >= PREDICTIONS.expectedListItemCount, `actual=${memories.length}`);
    const testMemory = memories.find((m: any) => m.id === createdMemory.id);
    check('Created memory is in the list', !!testMemory);

    // STEP 6: Tag a person
    console.log('\n▶ STEP 6: Tagging a person in the memory...');
    // Tag the test elder as 'mentions' (they're already tagged as 'about' by createMemory)
    const tag = await pitru.tagPerson(
      createdMemory.id,
      `pitru-test-elder-${TEST_MARKER}`,
      TEST_USER_ID,
      'mentions',
    );
    console.log('  Created tag:', JSON.stringify(tag));
    check('Tag type is mentions', tag.tagType === PREDICTIONS.expectedTagType, `actual=${tag.tagType}`);

    // STEP 7: Set consent
    console.log('\n▶ STEP 7: Setting ai_persona consent...');
    const consent = await pitru.setConsent(
      `pitru-test-elder-${TEST_MARKER}`,
      'ai_persona',
      true,
      TEST_USER_ID,
      `Test consent for ${TEST_MARKER}`,
    );
    console.log('  Consent:', JSON.stringify(consent));
    check('Consent given is true', consent.consentGiven === PREDICTIONS.expectedConsentGiven);

    // STEP 8: Generate a brief + verify memory_orbit item appears
    console.log('\n▶ STEP 8: Generating brief + checking for memory_orbit item...');
    const briefResult = await generator.generateBriefForUser(TEST_USER_ID);
    console.log(`  Brief has ${briefResult.items.length} items`);
    console.log(`  Item types: ${briefResult.items.map((i: any) => i.itemType).join(', ')}`);

    const memoryOrbitItem = briefResult.items.find((i: any) => i.itemType === 'memory_orbit');
    check('Brief contains a memory_orbit item', !!memoryOrbitItem, `items=${briefResult.items.map((i: any) => i.itemType).join(',')}`);

    if (memoryOrbitItem) {
      check('memory_orbit priority is 70', memoryOrbitItem.priority === PREDICTIONS.expectedMemoryOrbitPriority, `actual=${memoryOrbitItem.priority}`);
      check('memory_orbit actionType is listen_memory', memoryOrbitItem.actionType === PREDICTIONS.expectedMemoryOrbitActionType, `actual=${memoryOrbitItem.actionType}`);
      check('memory_orbit title contains elder name', memoryOrbitItem.title.includes('PitruTestElder'), `actual="${memoryOrbitItem.title}"`);
      const relScore = typeof memoryOrbitItem.relevanceScore === 'number'
        ? memoryOrbitItem.relevanceScore
        : Number(memoryOrbitItem.relevanceScore);
      check('memory_orbit relevanceScore ≈ 0.65', Math.abs(relScore - PREDICTIONS.expectedMemoryOrbitRelevance) < 0.02, `actual=${relScore}`);
      check('memory_orbit has memoryId in actionData', !!memoryOrbitItem.actionData?.memoryId);
      check('memory_orbit has elderDeceased=false in actionData', memoryOrbitItem.actionData?.elderDeceased === false);
    }

    console.log(`\n  Total: ${pass} passed, ${fail} failed`);

  } catch (err) {
    console.error('💥 Test crashed:', err);
    fail++;
  } finally {
    await prisma.$disconnect();
  }

  // STEP 9: Clean up ALL test rows
  console.log('\n▶ STEP 9: Cleaning up test rows...');
  const finalCleanup = [
    `DELETE FROM "MemoryTag" WHERE "memoryId" IN (SELECT id FROM "AncestralMemory" WHERE "familyId"='${TEST_FAMILY_ID}' AND "title" LIKE 'PitruTest%');`,
    `DELETE FROM "MemoryConsent" WHERE "familyId"='${TEST_FAMILY_ID}' AND "consentNotes" LIKE '%${TEST_MARKER}%';`,
    `DELETE FROM "AncestralMemory" WHERE "familyId"='${TEST_FAMILY_ID}' AND "title" LIKE 'PitruTest%';`,
    `DELETE FROM "Person" WHERE "familyId"='${TEST_FAMILY_ID}' AND "name" LIKE 'PitruTest%';`,
    `DELETE FROM "BriefInteraction" WHERE "userId"='${TEST_USER_ID}';`,
    `DELETE FROM "BriefItem" WHERE "userId"='${TEST_USER_ID}';`,
    `DELETE FROM "DailyBrief" WHERE "userId"='${TEST_USER_ID}';`,
    `DELETE FROM "FamilyKarma" WHERE "userId"='${TEST_USER_ID}';`,
  ];
  for (const sql of finalCleanup) {
    try { await runSql(sql); } catch (err) { console.warn('  cleanup warn:', err); }
  }
  console.log('  Cleanup done.');

  console.log('\n═══════════════════════════════════════════════════════════════════════');
  console.log('  PITRU Validation complete.');
  console.log('═══════════════════════════════════════════════════════════════════════\n');

  if (fail > 0) process.exit(1);
}

main().catch((err) => {
  console.error('💥 Script crashed:', err);
  process.exit(2);
});
