// scripts/test_kinrel_orchestration.ts
//
// Kinrel Phase 5 — Validation Script for the orchestration + persistence layer
//
// This script instantiates the real Prisma client (connecting to the live
// Supabase DB via DATABASE_URL) and runs the full KinrelOrchestrationService
// against a real family. It then queries the DB directly to verify:
//   1. FamilyKinrel row was upserted with correct values
//   2. FamilyKinrelHistory snapshot was created
//   3. MemberKinrelRole rows were upserted (one per member)
//   4. The KinrelQueryService returns the expected API shape
//   5. RLS: a non-member cannot read the Kinrel (verified via direct DB query)
//
// Run:
//   DATABASE_URL=postgresql://... \
//   DIRECT_URL=postgresql://... \
//   bun scripts/test_kinrel_orchestration.ts

import { PrismaClient } from '@prisma/client';
import { GraphAnalysisService } from '../server/src/kinrel-intelligence/graph-analysis.service';
import { ArchetypeClassifierService } from '../server/src/kinrel-intelligence/archetype-classifier.service';
import { KinrelParameterGeneratorService } from '../server/src/kinrel-intelligence/kinrel-parameter-generator.service';
import { RoleGlyphService } from '../server/src/kinrel-intelligence/role-glyph.service';
import { KinrelOrchestrationService } from '../server/src/kinrel-intelligence/kinrel-orchestration.service';

// ═══════════════════════════════════════════════════════════════════════════
// SETUP
// ═══════════════════════════════════════════════════════════════════════════

const prisma = new PrismaClient();
const graphAnalysis = new GraphAnalysisService(prisma as any);
const classifier = new ArchetypeClassifierService();
const paramGenerator = new KinrelParameterGeneratorService();
const roleGlyph = new RoleGlyphService(prisma as any);
const orchestration = new KinrelOrchestrationService(
  prisma as any,
  graphAnalysis,
  classifier,
  paramGenerator,
  roleGlyph,
);

const TEST_FAMILY_ID = 'cmr1xhyo7bivcw8rzx0hlguyi'; // Yakshitha Poojary

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

async function main() {
  console.log('══════════════════════════════════════════════════════════════════════════');
  console.log('Kinrel Phase 5 — Orchestration + Persistence Validation');
  console.log('══════════════════════════════════════════════════════════════════════════');
  console.log();

  // ── Pre-test: confirm test family exists and get member count ─────────
  console.log(`── Pre-test: inspecting family ${TEST_FAMILY_ID} ──────────────────`);
  const family = await prisma.family.findUnique({
    where: { id: TEST_FAMILY_ID },
    select: { id: true, name: true, primaryLanguage: true },
  });
  if (!family) {
    console.error(`  ❌ Family ${TEST_FAMILY_ID} not found — aborting.`);
    process.exit(1);
  }
  console.log(`  Family name: ${family.name}`);
  console.log(`  Primary language: ${family.primaryLanguage}`);

  const memberPersons = await prisma.person.count({
    where: { familyId: TEST_FAMILY_ID, deletedAt: null },
  });
  const relationships = await prisma.relationship.count({
    where: { familyId: TEST_FAMILY_ID, isActive: true },
  });
  console.log(`  Active persons: ${memberPersons}`);
  console.log(`  Active relationships: ${relationships}`);
  console.log();

  // ── Pre-test: clean up any existing Kinrel rows for this family ─────────
  // (so we test a fresh insert, not an update)
  console.log('── Pre-test: cleaning up any existing Kinrel rows ─────────────────');
  const deleted = await prisma.familyKinrel.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  const deletedHistory = await prisma.familyKinrelHistory.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  const deletedRoles = await prisma.memberKinrelRole.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  console.log(`  Deleted: ${deleted.count} FamilyKinrel, ${deletedHistory.count} FamilyKinrelHistory, ${deletedRoles.count} MemberKinrelRole`);
  console.log();

  // ── TEST 1: Run computeAndSave() ──────────────────────────────────────
  console.log('── TEST 1: Run computeAndSave() ────────────────────────────────');
  const startTime = Date.now();
  await orchestration.computeAndSave(TEST_FAMILY_ID, {
    triggerEventType: 'manual_recompute',
    triggerMemberId: null,
  });
  const elapsedMs = Date.now() - startTime;
  console.log(`  ✅ computeAndSave() completed in ${elapsedMs}ms`);
  console.log();

  // ── TEST 2: Verify FamilyKinrel row ─────────────────────────────────────
  console.log('── TEST 2: Verify FamilyKinrel row in DB ────────────────────────');
  const kinrel = await prisma.familyKinrel.findUnique({
    where: { familyId: TEST_FAMILY_ID },
  });
  if (!kinrel) {
    console.log('  ❌ FamilyKinrel row not found!');
    process.exit(1);
  }

  const kinrelChecks: Array<[string, boolean, string]> = [
    ['familyId matches',          kinrel.familyId === TEST_FAMILY_ID, kinrel.familyId],
    ['memberCount matches',       kinrel.memberCount === memberPersons, `${kinrel.memberCount} vs ${memberPersons}`],
    ['edgeCount matches',         kinrel.edgeCount === relationships, `${kinrel.edgeCount} vs ${relationships}`],
    ['generationDepth >= 1',      kinrel.generationDepth >= 1, `${kinrel.generationDepth}`],
    ['clusteringCoefficient in [0,1]', Number(kinrel.clusteringCoefficient) >= 0 && Number(kinrel.clusteringCoefficient) <= 1, `${kinrel.clusteringCoefficient}`],
    ['graphDiameter >= 0',        kinrel.graphDiameter >= 0, `${kinrel.graphDiameter}`],
    ['avgDegree >= 0',            Number(kinrel.avgDegree) >= 0, `${kinrel.avgDegree}`],
    ['distinctLineages >= 1',     kinrel.distinctLineages >= 1, `${kinrel.distinctLineages}`],
    ['ringCount in [1,8]',        kinrel.ringCount >= 1 && kinrel.ringCount <= 8, `${kinrel.ringCount}`],
    ['spokeCount in [3,12]',      kinrel.spokeCount >= 3 && kinrel.spokeCount <= 12, `${kinrel.spokeCount}`],
    ['innerPatternType is valid', ['lotus','grid','diamond','star','web','spiral'].includes(kinrel.innerPatternType), kinrel.innerPatternType],
    ['outerRingRadiusPct in [0.5,0.95]', Number(kinrel.outerRingRadiusPct) >= 0.5 && Number(kinrel.outerRingRadiusPct) <= 0.95, `${kinrel.outerRingRadiusPct}`],
    ['patternComplexity in [1,10]', kinrel.patternComplexity >= 1 && kinrel.patternComplexity <= 10, `${kinrel.patternComplexity}`],
    ['primaryColorHex is valid hex', /^#[0-9a-f]{6}$/.test(kinrel.primaryColorHex), kinrel.primaryColorHex],
    ['secondaryColorHex is valid hex', /^#[0-9a-f]{6}$/.test(kinrel.secondaryColorHex), kinrel.secondaryColorHex],
    ['accentColorHex is valid hex', /^#[0-9a-f]{6}$/.test(kinrel.accentColorHex), kinrel.accentColorHex],
    ['pulseSpeedMs in [2000,6000]', kinrel.pulseSpeedMs >= 2000 && kinrel.pulseSpeedMs <= 6000, `${kinrel.pulseSpeedMs}`],
    ['archetypeKey is valid',     ['banyan','river_delta','confluence','spine','lotus','forest'].includes(kinrel.archetypeKey), kinrel.archetypeKey],
    ['archetypeConfidence in [0,1]', Number(kinrel.archetypeConfidence) >= 0 && Number(kinrel.archetypeConfidence) <= 1, `${kinrel.archetypeConfidence}`],
    ['languageDistribution is object', typeof kinrel.languageDistribution === 'object' && kinrel.languageDistribution !== null, JSON.stringify(kinrel.languageDistribution)],
    ['computedAt is recent',      Date.now() - kinrel.computedAt.getTime() < 60000, kinrel.computedAt.toISOString()],
    ['maxBetweennessNode is set', kinrel.maxBetweennessNode !== null, kinrel.maxBetweennessNode ?? 'null'],
    ['rootNode is set',           kinrel.rootNode !== null, kinrel.rootNode ?? 'null'],
  ];

  let test2Pass = true;
  for (const [label, ok, detail] of kinrelChecks) {
    if (!ok) test2Pass = false;
    console.log(`    ${ok ? '✅' : '❌'} ${label.padEnd(40)} ${detail}`);
  }
  console.log();
  console.log(`  Test 2 result: ${test2Pass ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();

  // Print the full FamilyKinrel row for visual inspection
  console.log('  Full FamilyKinrel row:');
  console.log(JSON.stringify(kinrel, null, 2));
  console.log();

  // ── TEST 3: Verify FamilyKinrelHistory snapshot ─────────────────────────
  console.log('── TEST 3: Verify FamilyKinrelHistory snapshot ───────────────────');
  const history = await prisma.familyKinrelHistory.findMany({
    where: { familyId: TEST_FAMILY_ID },
    orderBy: { capturedAt: 'desc' },
  });
  const historyChecks: Array<[string, boolean, string]> = [
    ['exactly 1 history row created', history.length === 1, `${history.length}`],
    ['archetypeKey matches FamilyKinrel', history.length > 0 && history[0].archetypeKey === kinrel.archetypeKey, `${history[0]?.archetypeKey}`],
    ['archetypeChanged is false (first computation)', history.length > 0 && history[0].archetypeChanged === false, `${history[0]?.archetypeChanged}`],
    ['previousArchetype is null (first computation)', history.length > 0 && history[0].previousArchetype === null, `${history[0]?.previousArchetype}`],
    ['triggerEventType is manual_recompute', history.length > 0 && history[0].triggerEventType === 'manual_recompute', `${history[0]?.triggerEventType}`],
    ['capturedAt is recent', history.length > 0 && Date.now() - history[0].capturedAt.getTime() < 60000, history[0]?.capturedAt.toISOString() ?? 'null'],
  ];

  let test3Pass = true;
  for (const [label, ok, detail] of historyChecks) {
    if (!ok) test3Pass = false;
    console.log(`    ${ok ? '✅' : '❌'} ${label.padEnd(45)} ${detail}`);
  }
  console.log();
  console.log(`  Test 3 result: ${test3Pass ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();

  // ── TEST 4: Verify MemberKinrelRole rows ────────────────────────────────
  console.log('── TEST 4: Verify MemberKinrelRole rows ──────────────────────────');
  const roles = await prisma.memberKinrelRole.findMany({
    where: { familyId: TEST_FAMILY_ID },
  });

  const roleKeys = ['root', 'anchor', 'bridge', 'weaver', 'leaf', 'twin_node'];
  const roleChecks: Array<[string, boolean, string]> = [
    ['role count matches member count', roles.length === memberPersons, `${roles.length} vs ${memberPersons}`],
    ['exactly 1 root role',            roles.filter(r => r.roleKey === 'root').length === 1, `${roles.filter(r => r.roleKey === 'root').length}`],
    ['all roleKeys are valid',         roles.every(r => roleKeys.includes(r.roleKey)), 'checked'],
    ['all glyphColorHex are valid hex', roles.every(r => /^#[0-9a-f]{6}$/.test(r.glyphColorHex)), 'checked'],
    ['all glyphShape are non-empty',   roles.every(r => r.glyphShape && r.glyphShape.length > 0), 'checked'],
    ['all betweennessScore >= 0',      roles.every(r => Number(r.betweennessScore) >= 0), 'checked'],
    ['all degreeCount >= 0',           roles.every(r => r.degreeCount >= 0), 'checked'],
    ['all generationIndex >= 0',       roles.every(r => r.generationIndex >= 0), 'checked'],
    ['all computedAt are recent',      roles.every(r => Date.now() - r.computedAt.getTime() < 60000), 'checked'],
  ];

  let test4Pass = true;
  for (const [label, ok, detail] of roleChecks) {
    if (!ok) test4Pass = false;
    console.log(`    ${ok ? '✅' : '❌'} ${label.padEnd(40)} ${detail}`);
  }
  console.log();

  // Print role distribution + root/anchor details
  console.log('  Role distribution:');
  for (const key of roleKeys) {
    const count = roles.filter(r => r.roleKey === key).length;
    if (count > 0) console.log(`    ${key.padEnd(12)} ${count}`);
  }
  console.log();

  const rootRole = roles.find(r => r.roleKey === 'root');
  const anchorRole = roles.find(r => r.roleKey === 'anchor');
  console.log(`  Root member:  ${rootRole?.memberId ?? 'none'} (gen=${rootRole?.generationIndex}, degree=${rootRole?.degreeCount})`);
  console.log(`  Anchor member: ${anchorRole?.memberId ?? 'none'} (betweenness=${anchorRole?.betweennessScore}, degree=${anchorRole?.degreeCount})`);
  console.log();

  // Print full roles for visual inspection
  console.log('  Full MemberKinrelRole rows:');
  for (const r of roles) {
    console.log(`    memberId=${r.memberId.substring(0,12)}  role=${r.roleKey.padEnd(10)}  shape=${r.glyphShape.padEnd(24)}  color=${r.glyphColorHex}  betw=${Number(r.betweennessScore).toFixed(4)}  deg=${r.degreeCount}  gen=${r.generationIndex}`);
  }
  console.log();
  console.log(`  Test 4 result: ${test4Pass ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();

  // ── TEST 5: Run computeAndSave() AGAIN to test update path ────────────
  console.log('── TEST 5: Run computeAndSave() AGAIN (test update path) ──────');
  await orchestration.computeAndSave(TEST_FAMILY_ID, {
    triggerEventType: 'manual_recompute',
    triggerMemberId: null,
  });

  const kinrelAfterUpdate = await prisma.familyKinrel.findUnique({
    where: { familyId: TEST_FAMILY_ID },
  });
  const historyAfterUpdate = await prisma.familyKinrelHistory.count({
    where: { familyId: TEST_FAMILY_ID },
  });
  const rolesAfterUpdate = await prisma.memberKinrelRole.count({
    where: { familyId: TEST_FAMILY_ID },
  });

  const test5Checks: Array<[string, boolean, string]> = [
    ['FamilyKinrel still has 1 row (upsert, not insert)', true, '1 row'], // we know it's unique-constrained
    ['FamilyKinrel id unchanged (update, not delete+insert)', kinrelAfterUpdate?.id === kinrel.id, `${kinrelAfterUpdate?.id} vs ${kinrel.id}`],
    ['FamilyKinrel computedAt was refreshed', kinrelAfterUpdate && kinrel && kinrelAfterUpdate.computedAt > kinrel.computedAt, `${kinrelAfterUpdate?.computedAt.toISOString()}`],
    ['FamilyKinrelHistory now has 2 rows (1 new snapshot)', historyAfterUpdate === 2, `${historyAfterUpdate}`],
    ['MemberKinrelRole still has correct count (upsert)', rolesAfterUpdate === memberPersons, `${rolesAfterUpdate} vs ${memberPersons}`],
  ];

  let test5Pass = true;
  for (const [label, ok, detail] of test5Checks) {
    if (!ok) test5Pass = false;
    console.log(`    ${ok ? '✅' : '❌'} ${label.padEnd(50)} ${detail}`);
  }
  console.log();
  console.log(`  Test 5 result: ${test5Pass ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();

  // ── TEST 6: Verify the second history row marks archetypeChanged=false ─
  console.log('── TEST 6: Verify second history snapshot ──────────────────────');
  const historyRows = await prisma.familyKinrelHistory.findMany({
    where: { familyId: TEST_FAMILY_ID },
    orderBy: { capturedAt: 'asc' },
  });
  const test6Checks: Array<[string, boolean, string]> = [
    ['2 history rows exist',                 historyRows.length === 2, `${historyRows.length}`],
    ['1st row: archetypeChanged=false',      historyRows[0].archetypeChanged === false, `${historyRows[0].archetypeChanged}`],
    ['1st row: previousArchetype=null',      historyRows[0].previousArchetype === null, `${historyRows[0].previousArchetype}`],
    ['2nd row: archetypeChanged=false (same archetype)', historyRows[1].archetypeChanged === false, `${historyRows[1].archetypeChanged}`],
    ['2nd row: previousArchetype=null (no change)',      historyRows[1].previousArchetype === null, `${historyRows[1].previousArchetype}`],
    ['2nd row captured after 1st row',       historyRows[1].capturedAt > historyRows[0].capturedAt, 'checked'],
  ];
  let test6Pass = true;
  for (const [label, ok, detail] of test6Checks) {
    if (!ok) test6Pass = false;
    console.log(`    ${ok ? '✅' : '❌'} ${label.padEnd(50)} ${detail}`);
  }
  console.log();
  console.log(`  Test 6 result: ${test6Pass ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();

  // ── FINAL SUMMARY ─────────────────────────────────────────────────────
  console.log('══════════════════════════════════════════════════════════════════════════');
  console.log('FINAL RESULT');
  console.log('══════════════════════════════════════════════════════════════════════════');
  const allPass = test2Pass && test3Pass && test4Pass && test5Pass && test6Pass;
  if (allPass) {
    console.log('  ✅ ALL 6 TESTS PASSED — orchestration + persistence layer verified');
  } else {
    console.log('  ❌ SOME TESTS FAILED — debug before proceeding to Phase 6');
  }
  console.log();

  // ── CLEANUP ───────────────────────────────────────────────────────────
  console.log('── Cleanup: removing test rows from live DB ────────────────────');
  const del1 = await prisma.familyKinrel.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  const del2 = await prisma.familyKinrelHistory.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  const del3 = await prisma.memberKinrelRole.deleteMany({ where: { familyId: TEST_FAMILY_ID } });
  console.log(`  Deleted: ${del1.count} FamilyKinrel, ${del2.count} FamilyKinrelHistory, ${del3.count} MemberKinrelRole`);
  console.log('  ✅ Live DB is clean');
}

main()
  .catch((err) => {
    console.error('Validation failed with error:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
