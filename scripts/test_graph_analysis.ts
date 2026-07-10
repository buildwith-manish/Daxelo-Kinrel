// scripts/test_graph_analysis.ts
//
// Kinrel Phase 2 — Validation Script
//
// Tests the pure graph computation in server/src/kinrel-intelligence/graph-metrics.ts against:
//   1. A hand-checkable synthetic test graph (7 members, 9 edges, 3 generations)
//   2. A real family from the live Supabase DB
//
// Run:  bun scripts/test_graph_analysis.ts

import { computeGraphMetrics, GraphNode, GraphEdge, GraphMetrics } from '../server/src/kinrel-intelligence/graph-metrics';

// ═══════════════════════════════════════════════════════════════════════════
// PART 1: SYNTHETIC TEST GRAPH
// ═══════════════════════════════════════════════════════════════════════════
//
// 7 members, 9 edges, 3 generations:
//
//   Gen 0:    A ──spouse── B
//             │           │
//             ├──father──┐│──mother──┐
//             │          ││          │
//   Gen 1:    G          C ◄─────────┘          D          E
//          (child of   (child of A&B)    (child of A&B)  (child of A&B)
//           A only)      │
//                        ├──appa──┐
//                        │        │
//   Gen 2:               F ◄──────┘
//                     (child of C)
//
// Edges:
//   1. A→B  spouse  (en)
//   2. A→G  father  (en)
//   3. A→C  father  (en)
//   4. B→C  amma    (ta)  ← Tamil for "mother"
//   5. A→D  pita    (hi)  ← Hindi for "father"
//   6. B→D  mother  (en)
//   7. A→E  father  (en)
//   8. B→E  mother  (en)
//   9. C→F  appa    (ta)  ← Tamil for "father"

const A = 'test-a';
const B = 'test-b';
const C = 'test-c';
const D = 'test-d';
const E = 'test-e';
const F = 'test-f';
const G = 'test-g';

const testNodes: GraphNode[] = [
  { id: A },
  { id: B },
  { id: C },
  { id: D },
  { id: E },
  { id: F },
  { id: G },
];

const testEdges: GraphEdge[] = [
  { fromId: A, toId: B, relationshipType: 'spouse', direction: 'from' },
  { fromId: A, toId: G, relationshipType: 'father', direction: 'from' },
  { fromId: A, toId: C, relationshipType: 'father', direction: 'from' },
  { fromId: B, toId: C, relationshipType: 'amma',   direction: 'from' },
  { fromId: A, toId: D, relationshipType: 'pita',   direction: 'from' },
  { fromId: B, toId: D, relationshipType: 'mother', direction: 'from' },
  { fromId: A, toId: E, relationshipType: 'father', direction: 'from' },
  { fromId: B, toId: E, relationshipType: 'mother', direction: 'from' },
  { fromId: C, toId: F, relationshipType: 'appa',   direction: 'from' },
];

// ── PREDICTIONS (hand-computed) ──────────────────────────────────────────

interface Prediction {
  memberCount: number;
  edgeCount: number;
  generationDepth: number;
  avgDegree: number;
  graphDiameter: number;
  clusteringCoefficient: number;
  maxBetweennessNode: string;
  rootNode: string;
  distinctLineages: number;
  languageDistribution: Record<string, number>;
  betweennessMap: Record<string, number>;
  degreeMap: Record<string, number>;
  generationMap: Record<string, number>;
}

const predicted: Prediction = {
  memberCount: 7,
  edgeCount: 9,
  generationDepth: 3,
  avgDegree: 18 / 7,            // ≈ 2.571
  graphDiameter: 3,
  clusteringCoefficient: 3.1333 / 5,  // ≈ 0.627
  maxBetweennessNode: A,
  rootNode: A,
  distinctLineages: 1,
  languageDistribution: { en: 6/9, ta: 2/9, hi: 1/9 },
  betweennessMap: {
    [A]: 7.5 / 15,   // 0.500
    [B]: 2.5 / 15,   // 0.167
    [C]: 5.0 / 15,   // 0.333
    [D]: 0,
    [E]: 0,
    [F]: 0,
    [G]: 0,
  },
  degreeMap: {
    [A]: 5, [B]: 4, [C]: 3, [D]: 2, [E]: 2, [F]: 1, [G]: 1,
  },
  generationMap: {
    [A]: 0, [B]: 0, [C]: 1, [D]: 1, [E]: 1, [F]: 2, [G]: 1,
  },
};

// ── COMPARISON HELPER ────────────────────────────────────────────────────

const EPSILON = 0.005; // 0.5% tolerance for floating-point comparisons

function approxEqual(a: number, b: number, eps = EPSILON): boolean {
  return Math.abs(a - b) < eps;
}

function compareMaps(
  label: string,
  actual: Record<string, number>,
  predicted: Record<string, number>,
): { pass: boolean; details: string[] } {
  const details: string[] = [];
  let allPass = true;
  const allKeys = new Set([...Object.keys(actual), ...Object.keys(predicted)]);
  for (const key of allKeys) {
    const a = actual[key] ?? 0;
    const p = predicted[key] ?? 0;
    const ok = approxEqual(a, p);
    if (!ok) allPass = false;
    details.push(`    ${key}: actual=${a.toFixed(4)}  predicted=${p.toFixed(4)}  ${ok ? '✅' : '❌ MISMATCH'}`);
  }
  return { pass: allPass, details };
}

// ── RUN SYNTHETIC TEST ───────────────────────────────────────────────────

console.log('══════════════════════════════════════════════════════════════════════════');
console.log('PART 1: SYNTHETIC TEST GRAPH (7 members, 9 edges, 3 generations)');
console.log('══════════════════════════════════════════════════════════════════════════');
console.log();

const actual = computeGraphMetrics(testNodes, testEdges, 'en');

console.log('── ACTUAL OUTPUT ──────────────────────────────────────────────────');
console.log(JSON.stringify(actual, null, 2));
console.log();

console.log('── PREDICTED vs ACTUAL COMPARISON ─────────────────────────────────');
console.log();

let allTestsPass = true;

// Scalar metrics
const scalarChecks: Array<[string, number, number]> = [
  ['memberCount',           predicted.memberCount,           actual.memberCount],
  ['edgeCount',             predicted.edgeCount,             actual.edgeCount],
  ['generationDepth',       predicted.generationDepth,       actual.generationDepth],
  ['avgDegree',             predicted.avgDegree,             actual.avgDegree],
  ['graphDiameter',         predicted.graphDiameter,         actual.graphDiameter],
  ['clusteringCoefficient', predicted.clusteringCoefficient, actual.clusteringCoefficient],
  ['distinctLineages',      predicted.distinctLineages,      actual.distinctLineages],
];

console.log('  Scalar metrics:');
for (const [label, pred, act] of scalarChecks) {
  const ok = approxEqual(pred, act);
  if (!ok) allTestsPass = false;
  console.log(`    ${label.padEnd(25)} predicted=${pred.toFixed(4).padStart(8)}  actual=${act.toFixed(4).padStart(8)}  ${ok ? '✅' : '❌ MISMATCH'}`);
}
console.log();

// String metrics
console.log('  Node identifiers:');
const idChecks: Array<[string, string | null, string | null]> = [
  ['maxBetweennessNode',    predicted.maxBetweennessNode,    actual.maxBetweennessNodeId],
  ['rootNode',              predicted.rootNode,              actual.rootNodeId],
];
for (const [label, pred, act] of idChecks) {
  const ok = pred === act;
  if (!ok) allTestsPass = false;
  console.log(`    ${label.padEnd(25)} predicted=${pred ?? 'null'}  actual=${act ?? 'null'}  ${ok ? '✅' : '❌ MISMATCH'}`);
}
console.log();

// Map metrics
console.log('  betweennessMap:');
const bwCheck = compareMaps('betweennessMap', actual.betweennessMap, predicted.betweennessMap);
if (!bwCheck.pass) allTestsPass = false;
bwCheck.details.forEach(d => console.log(d));
console.log();

console.log('  degreeMap:');
const degCheck = compareMaps('degreeMap', actual.degreeMap, predicted.degreeMap);
if (!degCheck.pass) allTestsPass = false;
degCheck.details.forEach(d => console.log(d));
console.log();

console.log('  generationMap:');
const genCheck = compareMaps('generationMap', actual.generationMap, predicted.generationMap);
if (!genCheck.pass) allTestsPass = false;
genCheck.details.forEach(d => console.log(d));
console.log();

console.log('  languageDistribution:');
const langCheck = compareMaps('languageDistribution', actual.languageDistribution, predicted.languageDistribution);
if (!langCheck.pass) allTestsPass = false;
langCheck.details.forEach(d => console.log(d));
console.log();

console.log('── SYNTHETIC TEST RESULT ──────────────────────────────────────────');
if (allTestsPass) {
  console.log('  ✅ ALL METRICS MATCH — synthetic test PASSED');
} else {
  console.log('  ❌ SOME METRICS MISMATCH — synthetic test FAILED');
  console.log('  ⚠️  Do NOT proceed to Phase 3 until all mismatches are debugged.');
}
console.log();

// ═══════════════════════════════════════════════════════════════════════════
// PART 2: LIVE DB TEST
// ═══════════════════════════════════════════════════════════════════════════

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://promxswvsnvilplmrtsj.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

async function runLiveTest() {
  console.log('══════════════════════════════════════════════════════════════════════════');
  console.log('PART 2: LIVE DB TEST (real family from promxswvsnvilplmrtsj)');
  console.log('══════════════════════════════════════════════════════════════════════════');
  console.log();

  if (!SUPABASE_SERVICE_KEY) {
    console.log('  ⚠️  SUPABASE_SERVICE_ROLE_KEY not set — skipping live test.');
    console.log('      To run: SUPABASE_SERVICE_ROLE_KEY=... bun scripts/test_graph_analysis.ts');
    return;
  }

  // Dynamically import Supabase client (Bun supports this)
  const { createClient } = await import('@supabase/supabase-js');
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // Find a family with the most members (for a meaningful test)
  console.log('  Finding a real family with the most members...');
  const { data: families, error: famError } = await supabase
    .from('Person')
    .select('familyId')
    .is('deletedAt', null)
    .limit(500);

  if (famError || !families || families.length === 0) {
    console.log('  ⚠️  No persons found in DB — skipping live test.');
    return;
  }

  // Count members per family
  const familyCounts: Record<string, number> = {};
  for (const p of families) {
    familyCounts[p.familyId] = (familyCounts[p.familyId] ?? 0) + 1;
  }
  const sortedFamilies = Object.entries(familyCounts).sort((a, b) => b[1] - a[1]);
  const [familyId, memberCount] = sortedFamilies[0];

  console.log(`  Selected family: ${familyId} (${memberCount} persons found in sample)`);
  console.log();

  // Load family primary language
  const { data: family } = await supabase
    .from('Family')
    .select('id, name, "primaryLanguage"')
    .eq('id', familyId)
    .single();

  const primaryLanguage = family?.primaryLanguage ?? 'en';
  console.log(`  Family name: ${family?.name ?? '(unknown)'}`);
  console.log(`  Primary language: ${primaryLanguage}`);
  console.log();

  // Load all persons
  const { data: persons, error: personError } = await supabase
    .from('Person')
    .select('id, name')
    .eq('familyId', familyId)
    .is('deletedAt', null);

  if (personError || !persons) {
    console.log(`  ⚠️  Error loading persons: ${personError?.message}`);
    return;
  }

  // Load all relationships
  const { data: relationships, error: relError } = await supabase
    .from('Relationship')
    .select('"fromPersonId", "toPersonId", "relationshipType", direction')
    .eq('familyId', familyId)
    .eq('isActive', true);

  if (relError || !relationships) {
    console.log(`  ⚠️  Error loading relationships: ${relError?.message}`);
    return;
  }

  console.log(`  Loaded ${persons.length} persons and ${relationships.length} relationships`);
  console.log();

  // Transform to GraphNode[] + GraphEdge[]
  const liveNodes: GraphNode[] = persons.map(p => ({ id: p.id }));
  const liveEdges: GraphEdge[] = relationships.map(r => ({
    fromId: r.fromPersonId,
    toId: r.toPersonId,
    relationshipType: r.relationshipType,
    direction: r.direction,
  }));

  // Compute metrics
  const liveMetrics = computeGraphMetrics(liveNodes, liveEdges, primaryLanguage);

  console.log('── LIVE DB OUTPUT ─────────────────────────────────────────────────');
  console.log(JSON.stringify(liveMetrics, null, 2));
  console.log();

  // Sanity checks
  console.log('── SANITY CHECKS ──────────────────────────────────────────────────');

  const sanityChecks: Array<[string, boolean, string]> = [
    ['memberCount > 0',                liveMetrics.memberCount > 0,           `memberCount=${liveMetrics.memberCount}`],
    ['memberCount matches persons',    liveMetrics.memberCount === persons.length, `${liveMetrics.memberCount} vs ${persons.length}`],
    ['edgeCount >= 0',                 liveMetrics.edgeCount >= 0,            `edgeCount=${liveMetrics.edgeCount}`],
    ['edgeCount matches rels',         liveMetrics.edgeCount === relationships.length, `${liveMetrics.edgeCount} vs ${relationships.length}`],
    ['generationDepth >= 1',           liveMetrics.generationDepth >= 1,      `generationDepth=${liveMetrics.generationDepth}`],
    ['generationDepth <= 10',          liveMetrics.generationDepth <= 10,     `generationDepth=${liveMetrics.generationDepth} (sanity bound)`],
    ['clusteringCoefficient >= 0',     liveMetrics.clusteringCoefficient >= 0, `cc=${liveMetrics.clusteringCoefficient.toFixed(4)}`],
    ['clusteringCoefficient <= 1',     liveMetrics.clusteringCoefficient <= 1, `cc=${liveMetrics.clusteringCoefficient.toFixed(4)}`],
    ['graphDiameter >= 0',             liveMetrics.graphDiameter >= 0,        `diameter=${liveMetrics.graphDiameter}`],
    ['avgDegree >= 0',                 liveMetrics.avgDegree >= 0,            `avgDegree=${liveMetrics.avgDegree.toFixed(4)}`],
    ['distinctLineages >= 1',          liveMetrics.distinctLineages >= 1,     `lineages=${liveMetrics.distinctLineages}`],
    ['maxBetweennessNode is not null', liveMetrics.maxBetweennessNodeId !== null, `node=${liveMetrics.maxBetweennessNodeId}`],
    ['rootNodeId is not null',         liveMetrics.rootNodeId !== null,       `node=${liveMetrics.rootNodeId}`],
    ['language distribution sums to ~1.0', approxEqual(
      Object.values(liveMetrics.languageDistribution).reduce((s, v) => s + v, 0), 1.0, 0.01),
      `sum=${Object.values(liveMetrics.languageDistribution).reduce((s, v) => s + v, 0).toFixed(4)}`],
    ['all betweenness values >= 0',    Object.values(liveMetrics.betweennessMap).every(v => v >= -EPSILON), 'checked'],
    ['all betweenness values <= 1',    Object.values(liveMetrics.betweennessMap).every(v => v <= 1 + EPSILON), 'checked'],
    ['all degree values >= 0',         Object.values(liveMetrics.degreeMap).every(v => v >= 0), 'checked'],
    ['all generation values >= 0',     Object.values(liveMetrics.generationMap).every(v => v >= 0), 'checked'],
  ];

  let liveAllPass = true;
  for (const [label, ok, detail] of sanityChecks) {
    if (!ok) liveAllPass = false;
    console.log(`    ${ok ? '✅' : '❌'} ${label.padEnd(40)} ${detail}`);
  }
  console.log();

  // Print the top-5 betweenness nodes for visual inspection
  console.log('── TOP 5 BETWEENNESS NODES (for visual inspection) ────────────────');
  const sorted = Object.entries(liveMetrics.betweennessMap)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5);
  for (const [nodeId, score] of sorted) {
    const person = persons.find(p => p.id === nodeId);
    console.log(`    ${person?.name ?? nodeId.substring(0, 12)}: ${score.toFixed(4)} (degree=${liveMetrics.degreeMap[nodeId]}, gen=${liveMetrics.generationMap[nodeId]})`);
  }
  console.log();

  console.log('── LIVE TEST RESULT ───────────────────────────────────────────────');
  if (liveAllPass) {
    console.log('  ✅ ALL SANITY CHECKS PASSED — live output looks structurally reasonable');
  } else {
    console.log('  ❌ SOME SANITY CHECKS FAILED — investigate before proceeding');
  }
}

// ── RUN ──────────────────────────────────────────────────────────────────

runLiveTest().catch(err => {
  console.error('Live test failed with error:', err);
});

export {};
