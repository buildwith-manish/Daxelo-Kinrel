// scripts/test_parameter_generator.ts
//
// AURA Phase 4 — Validation Script for AuraParameterGeneratorService
//
// Tests the parameter generator against 4 hand-predicted metric sets covering:
//   1. Synthetic graph from Phase 2 (banyan, multi-language)
//   2. Single-language family (confluence, like the live family)
//   3. Large family with high connectivity (banyan, multi-language, log ring count)
//   4. Very deep family (spine, logarithmic ring count boundary, spoke bonus)
//
// For each test case, we print predicted vs actual for EVERY parameter,
// including the hex color strings.
//
// BONUS: chains Phase 2 (graph metrics) → Phase 3 (classifier) → Phase 4 (params)
// on the live family from the DB to verify the full pipeline.
//
// Run:  bun scripts/test_parameter_generator.ts

import { AuraParameterGeneratorService, AuraSymbolParameters } from '../server/src/aura/aura-parameter-generator.service';
import { GraphMetrics } from '../server/src/aura/graph-metrics';
import { ArchetypeKey } from '../server/src/aura/archetype-classifier.service';

// ═══════════════════════════════════════════════════════════════════════════
// TEST CASES
// ═══════════════════════════════════════════════════════════════════════════

interface TestCase {
  name: string;
  description: string;
  archetype: ArchetypeKey;
  metrics: GraphMetrics;
  predicted: AuraSymbolParameters;
}

const testCases: TestCase[] = [
  // ─────────────────────────────────────────────────────────────────────
  // TEST 1: Synthetic graph from Phase 2 (banyan, multi-language)
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Synthetic graph (Phase 2)',
    description: '7 members, 9 edges, 3 generations, cc=0.627, langs={en:0.667, ta:0.222, hi:0.111}',
    archetype: 'banyan',
    metrics: {
      memberCount: 7,
      edgeCount: 9,
      generationDepth: 3,
      clusteringCoefficient: 0.6267,
      graphDiameter: 3,
      avgDegree: 2.5714,
      maxBetweennessNodeId: 'test-a',
      rootNodeId: 'test-a',
      distinctLineages: 1,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: { en: 0.6667, ta: 0.2222, hi: 0.1111 },
    },
    predicted: {
      ringCount: 4,           // genDepth=3 ≤ 5 → 3+1
      spokeCount: 3,          // base=min(8,max(3,1+2))=3; bonus=min(4,⌊7/20⌋)=0
      innerPatternType: 'web', // banyan → web
      outerRingRadiusPct: 0.6125, // 0.5 + (3/12)*0.45
      patternComplexity: 2,   // round(0.6267 * log10(7) * 4) = round(2.118) = 2
      primaryColorHex: '#2273c3',   // en hue=210, S=0.7, L=0.45
      secondaryColorHex: '#6b248f', // ta hue=280, S=0.6, L=0.35
      accentColorHex: '#c68039',    // hi hue=30 (weighted avg of rest), S=0.55, L=0.5
      pulseSpeedMs: 4714,     // 6000 - (2.5714/8)*4000 = 6000 - 1285.7 = 4714
    },
  },

  // ─────────────────────────────────────────────────────────────────────
  // TEST 2: Single-language family (confluence, like live family)
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Single-language (confluence)',
    description: '5 members, 3 edges, cc=0, langs={en:1.0}, confluence archetype',
    archetype: 'confluence',
    metrics: {
      memberCount: 5,
      edgeCount: 3,
      generationDepth: 2,
      clusteringCoefficient: 0,
      graphDiameter: 2,
      avgDegree: 1.2,
      maxBetweennessNodeId: 'x',
      rootNodeId: 'y',
      distinctLineages: 3,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: { en: 1.0 },
    },
    predicted: {
      ringCount: 3,           // genDepth=2 ≤ 5 → 2+1
      spokeCount: 5,          // base=min(8,max(3,3+2))=5; bonus=0
      innerPatternType: 'star', // confluence → star
      outerRingRadiusPct: 0.575, // 0.5 + (2/12)*0.45 = 0.5 + 0.075
      patternComplexity: 1,   // round(0 * log10(5) * 4) = 0 → max(1, 0) = 1
      primaryColorHex: '#2273c3',   // en hue=210
      secondaryColorHex: '#8f2459', // (210+120)%360=330, S=0.6, L=0.35
      accentColorHex: '#80c639',    // (210+240)%360=90, S=0.55, L=0.5
      pulseSpeedMs: 5400,     // 6000 - (1.2/8)*4000 = 6000 - 600
    },
  },

  // ─────────────────────────────────────────────────────────────────────
  // TEST 3: Large family with high connectivity (banyan, multi-language)
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Large family (banyan)',
    description: '50 members, cc=0.5, genDepth=6, diameter=8, langs={hi:0.5, ta:0.3, te:0.2}',
    archetype: 'banyan',
    metrics: {
      memberCount: 50,
      edgeCount: 80,
      generationDepth: 6,
      clusteringCoefficient: 0.5,
      graphDiameter: 8,
      avgDegree: 4.0,
      maxBetweennessNodeId: 'x',
      rootNodeId: 'y',
      distinctLineages: 2,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: { hi: 0.5, ta: 0.3, te: 0.2 },
    },
    predicted: {
      ringCount: 6,           // genDepth=6 > 5 → min(8, round(5+log2(2)))=min(8,6)
      spokeCount: 6,          // base=min(8,max(3,2+2))=4; bonus=min(4,⌊50/20⌋)=2; total=6
      innerPatternType: 'web', // banyan → web
      outerRingRadiusPct: 0.8, // 0.5 + (8/12)*0.45 = 0.5 + 0.3
      patternComplexity: 3,   // round(0.5 * log10(50) * 4) = round(0.5 * 1.699 * 4) = round(3.398) = 3
      primaryColorHex: '#c37322',   // hi hue=30, S=0.7, L=0.45
      secondaryColorHex: '#6b248f', // ta hue=280, S=0.6, L=0.35
      accentColorHex: '#39c6c6',    // te hue=180 (weighted avg of rest), S=0.55, L=0.5
      pulseSpeedMs: 4000,     // 6000 - (4/8)*4000 = 6000 - 2000
    },
  },

  // ─────────────────────────────────────────────────────────────────────
  // TEST 4: Very deep family (spine, logarithmic ring count boundary)
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Very deep family (spine)',
    description: '100 members, cc=0.3, genDepth=10, diameter=12, spine archetype — ring count clamps at 8',
    archetype: 'spine',
    metrics: {
      memberCount: 100,
      edgeCount: 150,
      generationDepth: 10,
      clusteringCoefficient: 0.3,
      graphDiameter: 12,
      avgDegree: 3.0,
      maxBetweennessNodeId: 'x',
      rootNodeId: 'y',
      distinctLineages: 1,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: { en: 1.0 },
    },
    predicted: {
      ringCount: 8,           // genDepth=10 > 5 → min(8, round(5+log2(6)))=min(8, round(7.585))=min(8,8)
      spokeCount: 7,          // base=min(8,max(3,1+2))=3; bonus=min(4,⌊100/20⌋)=min(4,5)=4; total=min(12,7)
      innerPatternType: 'grid', // spine → grid
      outerRingRadiusPct: 0.95, // 0.5 + (12/12)*0.45 = 0.5 + 0.45
      patternComplexity: 2,   // round(0.3 * log10(100) * 4) = round(0.3 * 2 * 4) = round(2.4) = 2
      primaryColorHex: '#2273c3',   // en hue=210
      secondaryColorHex: '#8f2459', // (210+120)%360=330
      accentColorHex: '#80c639',    // (210+240)%360=90
      pulseSpeedMs: 4500,     // 6000 - (3/8)*4000 = 6000 - 1500
    },
  },
];

// ═══════════════════════════════════════════════════════════════════════════
// RUN TESTS
// ═══════════════════════════════════════════════════════════════════════════

const generator = new AuraParameterGeneratorService();
const EPSILON = 0.005;
let allTestsPass = true;

console.log('══════════════════════════════════════════════════════════════════════════');
console.log('AURA Phase 4 — Parameter Generator Validation');
console.log('══════════════════════════════════════════════════════════════════════════');
console.log();

for (let i = 0; i < testCases.length; i++) {
  const tc = testCases[i];
  console.log(`── TEST ${i + 1}: ${tc.name} ──────────────────────────────────────`);
  console.log(`  ${tc.description}`);
  console.log();
  console.log('  Input metrics:');
  console.log(`    generationDepth      = ${tc.metrics.generationDepth}`);
  console.log(`    distinctLineages     = ${tc.metrics.distinctLineages}`);
  console.log(`    memberCount          = ${tc.metrics.memberCount}`);
  console.log(`    graphDiameter        = ${tc.metrics.graphDiameter}`);
  console.log(`    clusteringCoefficient= ${tc.metrics.clusteringCoefficient.toFixed(4)}`);
  console.log(`    avgDegree            = ${tc.metrics.avgDegree.toFixed(4)}`);
  console.log(`    languageDistribution = ${JSON.stringify(tc.metrics.languageDistribution)}`);
  console.log(`    archetype            = ${tc.archetype}`);
  console.log();

  const actual = generator.generate(tc.metrics, tc.archetype);

  console.log('  Parameter comparison (predicted → actual):');
  console.log();

  let testPassed = true;

  // Numeric parameters
  const numericChecks: Array<[string, number, number]> = [
    ['ringCount',          tc.predicted.ringCount,          actual.ringCount],
    ['spokeCount',         tc.predicted.spokeCount,         actual.spokeCount],
    ['outerRingRadiusPct', tc.predicted.outerRingRadiusPct, actual.outerRingRadiusPct],
    ['patternComplexity',  tc.predicted.patternComplexity,  actual.patternComplexity],
    ['pulseSpeedMs',       tc.predicted.pulseSpeedMs,       actual.pulseSpeedMs],
  ];

  for (const [label, pred, act] of numericChecks) {
    const ok = Math.abs(pred - act) < EPSILON;
    if (!ok) testPassed = false;
    console.log(`    ${label.padEnd(20)} predicted=${pred.toFixed(4).padStart(8)}  actual=${act.toFixed(4).padStart(8)}  ${ok ? '✅' : '❌ MISMATCH'}`);
  }

  // String parameters
  const stringChecks: Array<[string, string, string]> = [
    ['innerPatternType',   tc.predicted.innerPatternType,   actual.innerPatternType],
    ['primaryColorHex',    tc.predicted.primaryColorHex,    actual.primaryColorHex],
    ['secondaryColorHex',  tc.predicted.secondaryColorHex,  actual.secondaryColorHex],
    ['accentColorHex',     tc.predicted.accentColorHex,     actual.accentColorHex],
  ];

  for (const [label, pred, act] of stringChecks) {
    const ok = pred.toLowerCase() === act.toLowerCase();
    if (!ok) testPassed = false;
    console.log(`    ${label.padEnd(20)} predicted=${pred.padEnd(10)}  actual=${act.padEnd(10)}  ${ok ? '✅' : '❌ MISMATCH'}`);
  }
  console.log();

  if (!testPassed) allTestsPass = false;
  console.log(`  Result: ${testPassed ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();
}

console.log('══════════════════════════════════════════════════════════════════════════');
console.log('FINAL RESULT');
console.log('══════════════════════════════════════════════════════════════════════════');
if (allTestsPass) {
  console.log('  ✅ ALL 4 TEST CASES PASSED — parameter generator matches hand predictions');
} else {
  console.log('  ❌ SOME TEST CASES FAILED — debug before proceeding to Phase 5');
}
console.log();

// ═══════════════════════════════════════════════════════════════════════════
// BONUS: Full pipeline test — Phase 2 → Phase 3 → Phase 4 on live family
// ═══════════════════════════════════════════════════════════════════════════

console.log('══════════════════════════════════════════════════════════════════════════');
console.log('BONUS: Full pipeline (graph → archetype → params) on live family');
console.log('══════════════════════════════════════════════════════════════════════════');
console.log();

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://promxswvsnvilplmrtsj.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

async function runPipelineTest() {
  if (!SUPABASE_SERVICE_KEY) {
    console.log('  ⚠️  SUPABASE_SERVICE_ROLE_KEY not set — skipping live pipeline test.');
    return;
  }

  const { createClient } = await import('@supabase/supabase-js');
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // Use the same family from Phase 2: cmr1xhyo7bivcw8rzx0hlguyi (Yakshitha Poojary)
  const familyId = 'cmr1xhyo7bivcw8rzx0hlguyi';
  console.log(`  Family: ${familyId}`);

  // Load family + persons + relationships
  const [{ data: family }, { data: persons }, { data: relationships }] = await Promise.all([
    supabase.from('Family').select('id, name, "primaryLanguage"').eq('id', familyId).single(),
    supabase.from('Person').select('id, name').eq('familyId', familyId).is('deletedAt', null),
    supabase.from('Relationship').select('"fromPersonId", "toPersonId", "relationshipType", direction').eq('familyId', familyId).eq('isActive', true),
  ]);

  console.log(`  Family name: ${family?.name}`);
  console.log(`  Primary language: ${family?.primaryLanguage}`);
  console.log(`  Persons: ${persons?.length ?? 0}`);
  console.log(`  Relationships: ${relationships?.length ?? 0}`);
  console.log();

  // ── Phase 2: Graph metrics ──
  const { computeGraphMetrics } = await import('../server/src/aura/graph-metrics');
  const nodes = (persons ?? []).map((p: any) => ({ id: p.id }));
  const edges = (relationships ?? []).map((r: any) => ({
    fromId: r.fromPersonId,
    toId: r.toPersonId,
    relationshipType: r.relationshipType,
    direction: r.direction,
  }));
  const metrics = computeGraphMetrics(nodes, edges, family?.primaryLanguage ?? 'en');
  console.log('  Phase 2 (graph metrics):');
  console.log(`    memberCount=${metrics.memberCount}, edgeCount=${metrics.edgeCount}`);
  console.log(`    generationDepth=${metrics.generationDepth}, distinctLineages=${metrics.distinctLineages}`);
  console.log(`    clusteringCoefficient=${metrics.clusteringCoefficient.toFixed(4)}, diameter=${metrics.graphDiameter}`);
  console.log(`    avgDegree=${metrics.avgDegree.toFixed(4)}, languageDistribution=${JSON.stringify(metrics.languageDistribution)}`);
  console.log();

  // ── Phase 3: Archetype classification ──
  const { ArchetypeClassifierService } = await import('../server/src/aura/archetype-classifier.service');
  const classifier = new ArchetypeClassifierService();
  const classification = classifier.classify(metrics);
  console.log('  Phase 3 (archetype):');
  console.log(`    archetype=${classification.archetypeKey}, confidence=${classification.confidence.toFixed(4)}`);
  console.log(`    display name (en)=${classification.definition.names.en}`);
  console.log();

  // ── Phase 4: Parameter generation ──
  const params = generator.generate(metrics, classification.archetypeKey);
  console.log('  Phase 4 (parameters):');
  console.log(`    ringCount=${params.ringCount}, spokeCount=${params.spokeCount}`);
  console.log(`    innerPatternType=${params.innerPatternType}`);
  console.log(`    outerRingRadiusPct=${params.outerRingRadiusPct.toFixed(4)}`);
  console.log(`    patternComplexity=${params.patternComplexity}`);
  console.log(`    primaryColorHex=${params.primaryColorHex}`);
  console.log(`    secondaryColorHex=${params.secondaryColorHex}`);
  console.log(`    accentColorHex=${params.accentColorHex}`);
  console.log(`    pulseSpeedMs=${params.pulseSpeedMs}`);
  console.log();

  // ── Sanity checks ──
  console.log('  Sanity checks:');
  const sanityChecks: Array<[string, boolean, string]> = [
    ['ringCount in [1,8]',         params.ringCount >= 1 && params.ringCount <= 8, `${params.ringCount}`],
    ['spokeCount in [3,12]',       params.spokeCount >= 3 && params.spokeCount <= 12, `${params.spokeCount}`],
    ['outerRingRadiusPct in [0.5,0.95]', params.outerRingRadiusPct >= 0.5 && params.outerRingRadiusPct <= 0.95, `${params.outerRingRadiusPct.toFixed(4)}`],
    ['patternComplexity in [1,10]', params.patternComplexity >= 1 && params.patternComplexity <= 10, `${params.patternComplexity}`],
    ['pulseSpeedMs in [2000,6000]', params.pulseSpeedMs >= 2000 && params.pulseSpeedMs <= 6000, `${params.pulseSpeedMs}`],
    ['primaryColorHex is valid hex', /^#[0-9a-f]{6}$/.test(params.primaryColorHex), params.primaryColorHex],
    ['secondaryColorHex is valid hex', /^#[0-9a-f]{6}$/.test(params.secondaryColorHex), params.secondaryColorHex],
    ['accentColorHex is valid hex', /^#[0-9a-f]{6}$/.test(params.accentColorHex), params.accentColorHex],
    ['innerPatternType is valid', ['lotus','grid','diamond','star','web','spiral'].includes(params.innerPatternType), params.innerPatternType],
  ];

  let pipelinePass = true;
  for (const [label, ok, detail] of sanityChecks) {
    if (!ok) pipelinePass = false;
    console.log(`    ${ok ? '✅' : '❌'} ${label.padEnd(35)} ${detail}`);
  }
  console.log();
  console.log(`  Pipeline result: ${pipelinePass ? '✅ ALL SANITY CHECKS PASSED' : '❌ SOME CHECKS FAILED'}`);
}

runPipelineTest().catch(err => {
  console.error('Pipeline test failed with error:', err);
});

export {};
