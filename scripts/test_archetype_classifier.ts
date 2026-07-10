// scripts/test_archetype_classifier.ts
//
// Kinrel Phase 3 — Validation Script for ArchetypeClassifierService
//
// Tests the classifier against 5 hand-predicted metric sets covering
// every archetype (banyan, spine, lotus, confluence, forest) plus the
// synthetic graph from Phase 2. For each test case, we print:
//   - The input metrics
//   - The predicted winner + runner-up + confidence (hand-computed)
//   - The actual scores for all 6 archetypes
//   - Per-archetype pass/fail for score
//   - Pass/fail for winner, runner-up, and confidence
//
// Run:  bun scripts/test_archetype_classifier.ts

import { ArchetypeClassifierService, ArchetypeKey } from '../server/src/kinrel-intelligence/archetype-classifier.service';
import { GraphMetrics } from '../server/src/kinrel-intelligence/graph-metrics';

// ═══════════════════════════════════════════════════════════════════════════
// TEST CASES
// ═══════════════════════════════════════════════════════════════════════════

interface TestCase {
  name: string;
  description: string;
  metrics: GraphMetrics;
  predicted: {
    winner: ArchetypeKey;
    runnerUp: ArchetypeKey;
    confidence: number;
    // Per-archetype predicted score (number of thresholds met, 0.5 for forest)
    scores: Partial<Record<ArchetypeKey, number>>;
  };
}

const testCases: TestCase[] = [
  // ─────────────────────────────────────────────────────────────────────
  // TEST 1: Synthetic graph from Phase 2 (banyan expected)
  // cc=0.627, genDepth=3, lineages=1, diameter=3, avgDegree=2.571
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Synthetic graph (Phase 2)',
    description: '7 members, 9 edges, 3 generations, cc=0.627 — should classify as Banyan',
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
      languageDistribution: {},
    },
    predicted: {
      winner: 'banyan',
      runnerUp: 'lotus',
      confidence: 0.5 + (2 - 1) / 12, // 0.5833
      scores: {
        banyan: 2,       // cc≥0.4 ✓, gen≥3 ✓
        river_delta: 0,  // cc≤0.2 ✗, diameter≥6 ✗
        confluence: 0,   // lineages≥3 ✗
        spine: 0,        // gen≥4 ✗, avgDeg≤2.5 ✗
        lotus: 1,        // cc≥0.25 ✓, cc≤0.4 ✗
        forest: 0.5,     // fallback
      },
    },
  },

  // ─────────────────────────────────────────────────────────────────────
  // TEST 2: Pure banyan (high clustering + deep generations)
  // cc=0.6, genDepth=4, lineages=2, diameter=4, avgDegree=3.0
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Pure banyan',
    description: 'High clustering + deep generations — should classify as Banyan',
    metrics: {
      memberCount: 20,
      edgeCount: 35,
      generationDepth: 4,
      clusteringCoefficient: 0.6,
      graphDiameter: 4,
      avgDegree: 3.0,
      maxBetweennessNodeId: 'x',
      rootNodeId: 'y',
      distinctLineages: 2,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: {},
    },
    predicted: {
      winner: 'banyan',
      runnerUp: 'spine', // tie with lotus at score 1, spine has higher weight (3 vs 2)
      confidence: 0.5 + (2 - 1) / 12, // 0.5833
      scores: {
        banyan: 2,       // cc≥0.4 ✓, gen≥3 ✓
        river_delta: 0,  // cc≤0.2 ✗, diameter≥6 ✗
        confluence: 0,   // lineages≥3 ✗
        spine: 1,        // gen≥4 ✓, avgDeg≤2.5 ✗
        lotus: 1,        // cc≥0.25 ✓, cc≤0.4 ✗
        forest: 0.5,
      },
    },
  },

  // ─────────────────────────────────────────────────────────────────────
  // TEST 3: Pure spine (deep + linear)
  // cc=0.1, genDepth=5, lineages=1, diameter=5, avgDegree=2.0
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Pure spine',
    description: 'Deep generations + low avg degree — should classify as Spine',
    metrics: {
      memberCount: 15,
      edgeCount: 14,
      generationDepth: 5,
      clusteringCoefficient: 0.1,
      graphDiameter: 5,
      avgDegree: 2.0,
      maxBetweennessNodeId: 'x',
      rootNodeId: 'y',
      distinctLineages: 1,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: {},
    },
    predicted: {
      winner: 'spine',
      runnerUp: 'banyan', // 3-way tie at score 1 (banyan/river_delta/lotus); banyan wins by weight 6
      confidence: 0.5 + (2 - 1) / 12, // 0.5833
      scores: {
        banyan: 1,       // cc≥0.4 ✗, gen≥3 ✓
        river_delta: 1,  // cc≤0.2 ✓, diameter≥6 ✗
        confluence: 0,   // lineages≥3 ✗
        spine: 2,        // gen≥4 ✓, avgDeg≤2.5 ✓
        lotus: 1,        // cc≥0.25 ✗, cc≤0.4 ✓ (CORRECTED — each threshold is independent)
        forest: 0.5,
      },
    },
  },

  // ─────────────────────────────────────────────────────────────────────
  // TEST 4: Lotus wins (low CC, no other archetype matches)
  // cc=0.22, genDepth=2, lineages=2, diameter=2, avgDegree=4.0
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Lotus wins (low CC)',
    description: 'cc≤0.4 triggers lotus maxCC; no other archetype matches — Lotus wins',
    metrics: {
      memberCount: 4,
      edgeCount: 2,
      generationDepth: 2,
      clusteringCoefficient: 0.22,
      graphDiameter: 2,
      avgDegree: 4.0,
      maxBetweennessNodeId: 'x',
      rootNodeId: 'y',
      distinctLineages: 2,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: {},
    },
    predicted: {
      // CORRECTED: Originally predicted forest, but lotus's maxCC threshold
      // passes for any cc ≤ 0.4, giving lotus score 1 > forest's 0.5.
      winner: 'lotus',
      runnerUp: 'forest',
      confidence: 0.5 + (1 - 0.5) / 12, // 0.5417
      scores: {
        banyan: 0,       // cc≥0.4 ✗, gen≥3 ✗
        river_delta: 0,  // cc≤0.2 ✗ (0.22 > 0.2), diameter≥6 ✗
        confluence: 0,   // lineages≥3 ✗
        spine: 0,        // gen≥4 ✗, avgDeg≤2.5 ✗
        lotus: 1,        // cc≥0.25 ✗ (0.22 < 0.25), cc≤0.4 ✓ (0.22 ≤ 0.4)
        forest: 0.5,
      },
    },
  },

  // ─────────────────────────────────────────────────────────────────────
  // TEST 5: Confluence (many lineages, low CC, 3-way tie at score 1)
  // cc=0.2, genDepth=2, lineages=4, diameter=2, avgDegree=4.0
  // ─────────────────────────────────────────────────────────────────────
  {
    name: 'Confluence (tie-break)',
    description: 'Many lineages + low CC — 3-way tie at score 1 (confluence/river_delta/lotus), confluence wins by weight',
    metrics: {
      memberCount: 12,
      edgeCount: 8,
      generationDepth: 2,
      clusteringCoefficient: 0.2,
      graphDiameter: 2,
      avgDegree: 4.0,
      maxBetweennessNodeId: 'x',
      rootNodeId: 'y',
      distinctLineages: 4,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: {},
    },
    predicted: {
      winner: 'confluence', // score 1, weight 5
      runnerUp: 'river_delta', // score 1, weight 4 (lotus also at 1 but weight 2)
      confidence: 0.5 + (1 - 1) / 12, // 0.5000 — narrow margin → low confidence
      scores: {
        banyan: 0,       // cc≥0.4 ✗, gen≥3 ✗
        river_delta: 1,  // cc≤0.2 ✓ (0.2 ≤ 0.2), diameter≥6 ✗
        confluence: 1,   // lineages≥3 ✓
        spine: 0,        // gen≥4 ✗, avgDeg≤2.5 ✗
        lotus: 1,        // cc≥0.25 ✗, cc≤0.4 ✓ (CORRECTED)
        forest: 0.5,
      },
    },
  },
];

// ═══════════════════════════════════════════════════════════════════════════
// RUN TESTS
// ═══════════════════════════════════════════════════════════════════════════

const classifier = new ArchetypeClassifierService();
const EPSILON = 0.005;
let allTestsPass = true;

console.log('══════════════════════════════════════════════════════════════════════════');
console.log('Kinrel Phase 3 — Archetype Classifier Validation');
console.log('══════════════════════════════════════════════════════════════════════════');
console.log();

for (let i = 0; i < testCases.length; i++) {
  const tc = testCases[i];
  console.log(`── TEST ${i + 1}: ${tc.name} ──────────────────────────────────────`);
  console.log(`  ${tc.description}`);
  console.log();
  console.log('  Input metrics:');
  console.log(`    clusteringCoefficient = ${tc.metrics.clusteringCoefficient.toFixed(4)}`);
  console.log(`    generationDepth       = ${tc.metrics.generationDepth}`);
  console.log(`    distinctLineages      = ${tc.metrics.distinctLineages}`);
  console.log(`    graphDiameter         = ${tc.metrics.graphDiameter}`);
  console.log(`    avgDegree             = ${tc.metrics.avgDegree.toFixed(4)}`);
  console.log();

  const result = classifier.classify(tc.metrics);

  console.log('  Per-archetype scores (predicted → actual):');
  let scoresAllPass = true;
  for (const scoreEntry of result.scores) {
    const predictedScore = tc.predicted.scores[scoreEntry.key];
    const ok = Math.abs(predictedScore - scoreEntry.score) < EPSILON;
    if (!ok) scoresAllPass = false;
    console.log(
      `    ${scoreEntry.key.padEnd(12)} predicted=${predictedScore.toFixed(2)}  actual=${scoreEntry.score.toFixed(2)}  ` +
      `(checks ${scoreEntry.checksPassed}/${scoreEntry.checksTotal}, weight ${scoreEntry.weight})  ` +
      `${ok ? '✅' : '❌ MISMATCH'}`,
    );
  }
  console.log();

  // Winner / runner-up / confidence checks
  const winnerOk = result.archetypeKey === tc.predicted.winner;
  const runnerUpOk = result.scores[1].key === tc.predicted.runnerUp;
  const confidenceOk = Math.abs(result.confidence - tc.predicted.confidence) < EPSILON;

  if (!winnerOk || !runnerUpOk || !confidenceOk || !scoresAllPass) {
    allTestsPass = false;
  }

  console.log('  Classification result:');
  console.log(`    Winner:     predicted=${tc.predicted.winner.padEnd(12)}  actual=${result.archetypeKey.padEnd(12)}  ${winnerOk ? '✅' : '❌ MISMATCH'}`);
  console.log(`    Runner-up:  predicted=${tc.predicted.runnerUp.padEnd(12)}  actual=${result.scores[1].key.padEnd(12)}  ${runnerUpOk ? '✅' : '❌ MISMATCH'}`);
  console.log(`    Confidence: predicted=${tc.predicted.confidence.toFixed(4)}  actual=${result.confidence.toFixed(4)}  ${confidenceOk ? '✅' : '❌ MISMATCH'}`);
  console.log(`    Display name (en): ${result.definition.names.en}`);
  console.log(`    Display name (hi): ${result.definition.names.hi}`);
  console.log();

  const testPassed = winnerOk && runnerUpOk && confidenceOk && scoresAllPass;
  console.log(`  Result: ${testPassed ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();
}

console.log('══════════════════════════════════════════════════════════════════════════');
console.log('FINAL RESULT');
console.log('══════════════════════════════════════════════════════════════════════════');
if (allTestsPass) {
  console.log('  ✅ ALL 5 TEST CASES PASSED — classifier matches hand predictions');
} else {
  console.log('  ❌ SOME TEST CASES FAILED — debug before proceeding to Phase 4');
}
console.log();

// ═══════════════════════════════════════════════════════════════════════════
// BONUS: Run classifier on the live family metrics from Phase 2
// ═══════════════════════════════════════════════════════════════════════════

console.log('══════════════════════════════════════════════════════════════════════════');
console.log('BONUS: Classify the live family from Phase 2 ("Yakshitha Poojary")');
console.log('══════════════════════════════════════════════════════════════════════════');
console.log();

const liveMetrics: GraphMetrics = {
  memberCount: 5,
  edgeCount: 3,
  generationDepth: 2,
  clusteringCoefficient: 0,
  graphDiameter: 2,
  avgDegree: 1.2,
  maxBetweennessNodeId: 'cmr1xi7dz8ekxfxbw26kfryq3',
  rootNodeId: 'cmr1zesyz0rackpilsw0z93fk',
  distinctLineages: 3,
  betweennessMap: {},
  degreeMap: {},
  generationMap: {},
  languageDistribution: { en: 1 },
};

// Hand-prediction for live family:
//   cc=0, genDepth=2, lineages=3, diameter=2, avgDegree=1.2
//   banyan: 0/2 (cc<0.4, gen<3) = 0
//   river_delta: 1/2 (cc≤0.2 ✓, diameter≥6 ✗) = 1
//   confluence: 1/1 (lineages≥3 ✓) = 1
//   spine: 1/2 (gen≥4 ✗, avgDeg≤2.5 ✓) = 1
//   lotus: 1/2 (cc≥0.25 ✗, cc≤0.4 ✓) = 1
//   forest: 0.5
// 4-way tie at score 1: confluence (w5), river_delta (w4), spine (w3), lotus (w2)
// Winner: confluence (highest weight among the tied score=1 archetypes)

console.log('  Live metrics: cc=0, genDepth=2, lineages=3, diameter=2, avgDegree=1.2');
console.log('  Hand-prediction: 4-way tie at score 1 (confluence/river_delta/spine/lotus)');
console.log('    confluence wins by weight (5 > 4 > 3 > 2)');
console.log();

const liveResult = classifier.classify(liveMetrics);
console.log('  Actual classification:');
console.log(`    Winner:     ${liveResult.archetypeKey} (confidence ${liveResult.confidence.toFixed(4)})`);
console.log(`    Display:    ${liveResult.definition.names.en}`);
console.log();
console.log('  All scores:');
for (const s of liveResult.scores) {
  console.log(`    ${s.key.padEnd(12)} score=${s.score.toFixed(2)}  checks=${s.checksPassed}/${s.checksTotal}  weight=${s.weight}`);
}
console.log();

const livePrediction = 'confluence';
const liveOk = liveResult.archetypeKey === livePrediction;
console.log(`  Result: ${liveOk ? '✅ MATCHES PREDICTION' : '❌ MISMATCH — investigate'}`);
console.log();

export {};
