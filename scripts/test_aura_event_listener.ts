// scripts/test_aura_event_listener.ts
//
// AURA Phase 6 — Validation Script for AuraEventListener
//
// This script must be run from the server/ directory (where node_modules is):
//   cd server
//   DATABASE_URL="postgresql://...?pgbouncer=true&prepare=false" \
//   bun ../scripts/test_aura_event_listener.ts
//
// Tests:
//   1. Single event triggers recompute after 2s debounce
//   2. 5 rapid events → 1 recompute (debounce works)
//   3. All 6 event types trigger recompute with correct triggerEventType
//   4. Module cleanup clears pending timers
//
// NOTE: This script creates a real NestJS app context and connects to the
// live DB. It cleans up all test rows at the end.

import { NestFactory } from '@nestjs/core';
import { EventEmitter2, EventEmitterModule } from '@nestjs/event-emitter';
import { Module } from '@nestjs/common';
import { PrismaModule } from '../server/src/prisma/prisma.module';
import { AuraModule } from '../server/src/aura/aura.module';
import { AuraEventListener } from '../server/src/aura/aura-event.listener';
import { PrismaService } from '../server/src/prisma/prisma.service';

const TEST_FAMILY_ID = 'cmr1xhyo7bivcw8rzx0hlguyi';

@Module({
  imports: [PrismaModule, EventEmitterModule.forRoot(), AuraModule],
})
class TestAppModule {}

async function main() {
  console.log('AURA Phase 6 — Event Listener Validation\n');
  const app = await NestFactory.createApplicationContext(TestAppModule, {
    logger: ['error', 'warn', 'log'],
  });
  const eventEmitter = app.get(EventEmitter2);
  const listener = app.get(AuraEventListener);
  const prisma = app.get(PrismaService);

  // Clean up
  await prisma.familyAura.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  await prisma.familyAuraHistory.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  await prisma.memberAuraRole.deleteMany({ where: { familyId: TEST_FAMILY_ID } });

  // Get real Person ID
  const realPerson = await prisma.person.findFirst({
    where: { familyId: TEST_FAMILY_ID, deletedAt: null },
    select: { id: true, name: true },
  });
  if (!realPerson) { console.error('No persons found'); process.exit(1); }
  console.log(`Using Person: ${realPerson.id} (${realPerson.name})\n`);

  // TEST 1: Single event
  console.log('TEST 1: Single member.added → recompute after 2s');
  eventEmitter.emit('family.member.added', { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
  console.log(`  Pending immediately: ${listener.isPending(TEST_FAMILY_ID)}`);
  await sleep(1000);
  console.log(`  Pending at 1s: ${listener.isPending(TEST_FAMILY_ID)}`);
  await sleep(1500);
  console.log(`  Pending at 2.5s: ${listener.isPending(TEST_FAMILY_ID)}`);
  await sleep(2000);
  const aura1 = await prisma.familyAura.findUnique({ where: { familyId: TEST_FAMILY_ID } });
  const hist1 = await prisma.familyAuraHistory.findFirst({ where: { familyId: TEST_FAMILY_ID }, orderBy: { capturedAt: 'desc' } });
  console.log(`  FamilyAura exists: ${aura1 !== null}, triggerEventType: ${hist1?.triggerEventType}`);
  console.log(`  Result: ${aura1 && hist1?.triggerEventType === 'member_added' ? '✅ PASSED' : '❌ FAILED'}\n`);

  // TEST 2: Debounce
  console.log('TEST 2: 5 rapid events → 1 recompute');
  const before = await prisma.familyAuraHistory.count({ where: { familyId: TEST_FAMILY_ID } });
  eventEmitter.emit('family.member.added', { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
  await sleep(150);
  eventEmitter.emit('family.relationship.created', { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
  await sleep(150);
  eventEmitter.emit('family.member.updated', { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
  await sleep(150);
  eventEmitter.emit('family.relationship.deleted', { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
  await sleep(150);
  eventEmitter.emit('family.member.added', { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
  await sleep(4000);
  const after = await prisma.familyAuraHistory.count({ where: { familyId: TEST_FAMILY_ID } });
  console.log(`  New rows: ${after - before} (expected 1)`);
  console.log(`  Result: ${after - before === 1 ? '✅ PASSED' : '❌ FAILED'}\n`);

  // TEST 3: All event types
  console.log('TEST 3: All event types');
  const eventTypes = [
    ['family.relationship.created', 'relationship_created'],
    ['family.relationship.updated', 'relationship_updated'],
    ['family.relationship.deleted', 'relationship_deleted'],
    ['family.member.removed', 'member_removed'],
    ['family.member.updated', 'member_updated'],
  ];
  let test3Pass = true;
  for (const [event, expected] of eventTypes) {
    eventEmitter.emit(event, { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
    await sleep(4500);
    const latest = await prisma.familyAuraHistory.findFirst({ where: { familyId: TEST_FAMILY_ID }, orderBy: { capturedAt: 'desc' } });
    const ok = latest?.triggerEventType === expected;
    if (!ok) test3Pass = false;
    console.log(`  ${ok ? '✅' : '❌'} ${event} → ${latest?.triggerEventType}`);
  }
  console.log(`  Result: ${test3Pass ? '✅ PASSED' : '❌ FAILED'}\n`);

  // TEST 4: Cleanup
  console.log('TEST 4: Module cleanup');
  eventEmitter.emit('family.member.added', { familyId: TEST_FAMILY_ID, memberId: realPerson.id });
  const beforeCleanup = listener.isPending(TEST_FAMILY_ID);
  await app.close();
  console.log(`  Pending before: ${beforeCleanup}, after: ${listener.pendingCount}`);
  console.log(`  Result: ${beforeCleanup && listener.pendingCount === 0 ? '✅ PASSED' : '❌ FAILED'}\n`);

  // Cleanup DB
  const cleanupPrisma = new (prisma.constructor as any)({ datasources: { db: { url: process.env.DATABASE_URL } } });
  await cleanupPrisma.familyAura.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  await cleanupPrisma.familyAuraHistory.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  await cleanupPrisma.memberAuraRole.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  await cleanupPrisma.$disconnect();
  console.log('✅ Live DB cleaned up');
  process.exit(0);
}

function sleep(ms: number): Promise<void> { return new Promise(r => setTimeout(r, ms)); }
main().catch(e => { console.error(e); process.exit(1); });
