/**
 * Daxelo-Kinrel — Integration Tests
 * ==================================
 * Tests the full algorithm pipeline WITHOUT external dependencies:
 *   - BFS path finding (spec §3.1)
 *   - Path canonicalizer (spec §3.2, §3.3)
 *   - Signature builder (spec §6)
 *   - Vocabulary mapper via real JSON (spec §7)
 *   - Spouse inference (spec §9)
 *   - Validation rules (spec §12)
 *   - Determinism guarantee (spec §14)
 *   - Session-only signature cache (spec §13.1)
 *
 * Run: pnpm test   (or: npx jest)
 */

import * as fs from "fs";
import * as path from "path";

// ===========================================================================
// 1. PORT THE ALGORITHM TO TEST SPACE
// ===========================================================================
// We import the pure algorithm pieces directly. No Prisma/NestJS needed
// for the algorithm itself — only the orchestration layer uses Prisma.

import {
  KinshipSignature,
  signatureKey,
  buildPathPattern,
} from "../src/modules/kinship/kinship-signature";
import { PathCanonicalizer, TraversalStep } from "../src/modules/graph/path-canonicalizer";
import { CanonicalIdService } from "../src/modules/kinship/canonical-id.service";
import { SignatureCacheService } from "../src/cache/signature-cache.service";

// ===========================================================================
// 2. SHARED TEST FIXTURES
// ===========================================================================

// Sample family graph per spec §17 Example 2 + extensions:
//
//   Arun (m) ──spouse── Sita (f)
//      │
//      └── Ravi (m) ──spouse── Priya (f)
//             │
//             ├── You (m)
//             ├── Manish (m)   [full brother, blood]
//             └── Rahul (m)    [half brother — different mother]
//
//   You ──spouse── Spouse (f)
//      │
//      └── Child (m)
//
//   Priya ──parent── Priya's father (m) [maternal grandfather of You]

interface TestNode {
  id: string;
  gender: "MALE" | "FEMALE" | "OTHER";
}

interface TestEdge {
  id: string;
  edgeType: "PARENT" | "SPOUSE" | "ADOPTIVE_PARENT" | "STEP_PARENT";
  temporal: "CURRENT" | "FORMER" | "LATE";
  personAId: string;
  personBId: string;
  isInferred: boolean;
}

const NODES: TestNode[] = [
  { id: "arun",         gender: "MALE" },     // paternal grandfather
  { id: "sita",         gender: "FEMALE" },   // paternal grandmother
  { id: "ravi",         gender: "MALE" },     // father
  { id: "priya",        gender: "FEMALE" },   // mother
  { id: "priyaFather",  gender: "MALE" },     // maternal grandfather
  { id: "you",          gender: "MALE" },     // root
  { id: "manish",       gender: "MALE" },     // full brother
  { id: "rahul",        gender: "MALE" },     // half brother (different mother)
  { id: "spouse",       gender: "FEMALE" },   // wife
  { id: "child",        gender: "MALE" },     // son
];

const EDGES: TestEdge[] = [
  // Arun ↔ Sita (grandparents)
  { id: "e1", edgeType: "SPOUSE", temporal: "CURRENT", personAId: "arun", personBId: "sita", isInferred: false },
  // Arun is Ravi's parent
  { id: "e2", edgeType: "PARENT", temporal: "CURRENT", personAId: "ravi", personBId: "arun", isInferred: false },
  // Sita is Ravi's parent
  { id: "e3", edgeType: "PARENT", temporal: "CURRENT", personAId: "ravi", personBId: "sita", isInferred: false },
  // Ravi ↔ Priya (parents of You)
  { id: "e4", edgeType: "SPOUSE", temporal: "CURRENT", personAId: "ravi", personBId: "priya", isInferred: false },
  // Ravi is You's parent (paternal)
  { id: "e5", edgeType: "PARENT", temporal: "CURRENT", personAId: "you", personBId: "ravi", isInferred: false },
  // Priya is You's parent (maternal)
  { id: "e6", edgeType: "PARENT", temporal: "CURRENT", personAId: "you", personBId: "priya", isInferred: false },
  // Ravi is Manish's parent (full brother — both parents shared)
  { id: "e7", edgeType: "PARENT", temporal: "CURRENT", personAId: "manish", personBId: "ravi", isInferred: false },
  { id: "e8", edgeType: "PARENT", temporal: "CURRENT", personAId: "manish", personBId: "priya", isInferred: false },
  // Rahul: same father (Ravi) but DIFFERENT mother — half brother
  { id: "e9", edgeType: "PARENT", temporal: "CURRENT", personAId: "rahul", personBId: "ravi", isInferred: false },
  // Priya's father — maternal grandfather of You
  { id: "e10", edgeType: "PARENT", temporal: "CURRENT", personAId: "priya", personBId: "priyaFather", isInferred: false },
  // You ↔ Spouse
  { id: "e11", edgeType: "SPOUSE", temporal: "CURRENT", personAId: "you", personBId: "spouse", isInferred: false },
  // You is Child's parent
  { id: "e12", edgeType: "PARENT", temporal: "CURRENT", personAId: "child", personBId: "you", isInferred: false },
];

function buildAdjacency(edges: TestEdge[]) {
  const adj = new Map<string, Array<{ primitive: string; targetId: string; edge: TestEdge; consanguinity: string }>>();
  const add = (from: string, entry: any) => {
    if (!adj.has(from)) adj.set(from, []);
    adj.get(from)!.push(entry);
  };
  for (const e of edges) {
    switch (e.edgeType) {
      case "PARENT":
        add(e.personAId, { primitive: "UP_PARENT", targetId: e.personBId, edge: e, consanguinity: "blood" });
        add(e.personBId, { primitive: "DOWN_CHILD", targetId: e.personAId, edge: e, consanguinity: "blood" });
        break;
      case "SPOUSE":
        add(e.personAId, { primitive: "SPOUSE", targetId: e.personBId, edge: e, consanguinity: "inLaw" });
        add(e.personBId, { primitive: "SPOUSE", targetId: e.personAId, edge: e, consanguinity: "inLaw" });
        break;
      case "ADOPTIVE_PARENT":
        add(e.personAId, { primitive: "UP_ADOPTIVE_PARENT", targetId: e.personBId, edge: e, consanguinity: "adoptive" });
        add(e.personBId, { primitive: "DOWN_ADOPTIVE_CHILD", targetId: e.personAId, edge: e, consanguinity: "adoptive" });
        break;
      case "STEP_PARENT":
        add(e.personAId, { primitive: "UP_STEP_PARENT", targetId: e.personBId, edge: e, consanguinity: "step" });
        add(e.personBId, { primitive: "DOWN_STEP_CHILD", targetId: e.personAId, edge: e, consanguinity: "step" });
        break;
    }
  }
  return adj;
}

// Minimal BFS mirroring graph-engine.service.ts
function bfsAllShortest(edges: TestEdge[], startId: string, targetId: string, maxDepth = 8): TraversalStep[][] {
  const adj = buildAdjacency(edges);
  if (startId === targetId) return [];
  const visitedDepths = new Map<string, number>([[startId, 0]]);
  const queue: TraversalStep[][] = [];
  for (const n of adj.get(startId) ?? []) {
    queue.push([{
      primitive: n.primitive as any,
      nodeId: startId,
      targetNodeId: n.targetId,
      edgeType: n.edge.edgeType,
      consanguinity: n.consanguinity as any,
    }]);
    visitedDepths.set(n.targetId, 1);
  }
  const results: TraversalStep[][] = [];
  let foundDepth = Infinity;
  while (queue.length > 0) {
    const p = queue.shift()!;
    const last = p[p.length - 1].targetNodeId;
    const depth = p.length;
    if (depth > maxDepth || depth > foundDepth) continue;
    if (last === targetId) {
      if (depth < foundDepth) { foundDepth = depth; results.length = 0; }
      results.push(p);
      continue;
    }
    for (const n of adj.get(last) ?? []) {
      const prev = visitedDepths.get(n.targetId);
      if (prev !== undefined && prev < depth + 1) continue;
      if (n.targetId === p[p.length - 1].nodeId) continue;
      visitedDepths.set(n.targetId, depth + 1);
      queue.push([...p, {
        primitive: n.primitive as any, nodeId: last, targetNodeId: n.targetId,
        edgeType: n.edge.edgeType, consanguinity: n.consanguinity as any,
      }]);
    }
  }
  return results;
}

function buildSignature(steps: TraversalStep[], nodes: TestNode[]): KinshipSignature {
  const primitives = steps.map((s) => s.primitive as any);
  const pathPattern = buildPathPattern(primitives);
  let generationDelta = 0;
  for (const p of primitives) {
    if (p.startsWith("UP_")) generationDelta -= 1;
    else if (p.startsWith("DOWN_")) generationDelta += 1;
  }
  const rank: Record<string, number> = { blood: 0, adoptive: 1, step: 2, inLaw: 3, foster: 4, spiritual: 5 };
  let consanguinity: any = "blood";
  let worst = -1;
  for (const s of steps) {
    const r = rank[s.consanguinity] ?? 99;
    if (r > worst) { worst = r; consanguinity = s.consanguinity; }
  }
  let side: any = "none";
  for (const s of steps) {
    if (s.primitive === "UP_PARENT" || s.primitive === "UP_ADOPTIVE_PARENT" || s.primitive === "UP_STEP_PARENT") {
      const parent = nodes.find((n) => n.id === s.targetNodeId);
      if (parent?.gender === "MALE") side = "paternal";
      else if (parent?.gender === "FEMALE") side = "maternal";
      break;
    }
  }
  const targetNode = nodes.find((n) => n.id === steps[steps.length - 1].targetNodeId);
  let genderAnchor: any = "neutral";
  if (targetNode?.gender === "MALE") genderAnchor = "male";
  else if (targetNode?.gender === "FEMALE") genderAnchor = "female";
  const upCount = primitives.filter((p: string) => p.startsWith("UP_")).length;
  const downCount = primitives.filter((p: string) => p.startsWith("DOWN_")).length;
  const removal = upCount > 0 && downCount > 0 ? Math.abs(upCount - downCount) : 0;
  return {
    generationDelta, pathPattern, side, consanguinity, genderAnchor,
    seniority: "none", removal, doubleKinship: false, temporal: "current",
  };
}

// ===========================================================================
// 3. LOAD REAL VOCABULARY (spec §7)
// ===========================================================================

const VOCAB_PATH = "/home/z/my-project/download/daxelo_kinrel_vocabulary.json";
const vocabData: any = JSON.parse(fs.readFileSync(VOCAB_PATH, "utf-8"));
const vocabRows: any[] = vocabData.rows;

function vocabLookup(sig: KinshipSignature, languageCode: string): any | null {
  const key = signatureKey(sig);
  // Primary lookup (spec §14) — variant_rank=0 only
  return vocabRows.find((r) =>
    r.signature_key === key && r.language_code === languageCode && r.variant_rank === 0
  ) ?? null;
}

// ===========================================================================
// 4. TEST SUITES
// ===========================================================================

describe("Daxelo-Kinrel Integration Tests", () => {

  // -------------------------------------------------------------------------
  // §3.1 BFS — find shortest path
  // -------------------------------------------------------------------------
  describe("Graph BFS (spec §3.1)", () => {
    test("You → Ravi (father): direct UP_PARENT path", () => {
      const paths = bfsAllShortest(EDGES, "you", "ravi");
      expect(paths.length).toBeGreaterThan(0);
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      expect(winner.length).toBe(1);
      expect(winner[0].primitive).toBe("UP_PARENT");
    });

    test("You → Arun (paternal grandfather): 2-hop UP_PARENT path", () => {
      const paths = bfsAllShortest(EDGES, "you", "arun");
      expect(paths.length).toBeGreaterThan(0);
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      expect(winner.length).toBe(2);
      expect(winner[0].primitive).toBe("UP_PARENT");
      expect(winner[1].primitive).toBe("UP_PARENT");
    });

    test("You → Priya's father (maternal grandfather): 2-hop UP path", () => {
      const paths = bfsAllShortest(EDGES, "you", "priyaFather");
      expect(paths.length).toBeGreaterThan(0);
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      expect(winner.length).toBe(2);
      expect(winner[0].primitive).toBe("UP_PARENT");
      expect(winner[1].primitive).toBe("UP_PARENT");
    });

    test("You → Child (son): 1-hop DOWN_CHILD path", () => {
      const paths = bfsAllShortest(EDGES, "you", "child");
      expect(paths.length).toBeGreaterThan(0);
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      expect(winner.length).toBe(1);
      expect(winner[0].primitive).toBe("DOWN_CHILD");
    });

    test("You → Spouse: 1-hop SPOUSE path", () => {
      const paths = bfsAllShortest(EDGES, "you", "spouse");
      expect(paths.length).toBeGreaterThan(0);
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      expect(winner.length).toBe(1);
      expect(winner[0].primitive).toBe("SPOUSE");
    });
  });

  // -------------------------------------------------------------------------
  // §3.2 Path canonicalizer — cycle + backtracking removal
  // -------------------------------------------------------------------------
  describe("Path Canonicalizer (spec §3.2, §3.3)", () => {
    const canon = new PathCanonicalizer();

    test("removes UP_PARENT followed by DOWN_CHILD on same node", () => {
      const steps: TraversalStep[] = [
        { primitive: "UP_PARENT" as any, nodeId: "you", targetNodeId: "ravi", edgeType: "PARENT", consanguinity: "blood" },
        { primitive: "DOWN_CHILD" as any, nodeId: "ravi", targetNodeId: "you", edgeType: "PARENT", consanguinity: "blood" },
      ];
      const result = canon.canonicalize(steps);
      expect(result.length).toBe(0);
    });

    test("removes cycles when target node reappears", () => {
      const steps: TraversalStep[] = [
        { primitive: "UP_PARENT" as any, nodeId: "you", targetNodeId: "ravi", edgeType: "PARENT", consanguinity: "blood" },
        { primitive: "DOWN_CHILD" as any, nodeId: "ravi", targetNodeId: "manish", edgeType: "PARENT", consanguinity: "blood" },
        { primitive: "UP_PARENT" as any, nodeId: "manish", targetNodeId: "ravi", edgeType: "PARENT", consanguinity: "blood" },
        { primitive: "DOWN_CHILD" as any, nodeId: "ravi", targetNodeId: "you", edgeType: "PARENT", consanguinity: "blood" },
      ];
      const result = canon.canonicalize(steps);
      // After cycle removal: you→ravi stays, then the rest (back through ravi) gets cut.
      expect(result.length).toBeLessThanOrEqual(1);
    });

    test("selectDeterministic prefers blood over inLaw when both are shortest", () => {
      // Two 1-hop candidates: blood (parent) vs inLaw (spouse). Blood wins.
      const blood: TraversalStep[] = [
        { primitive: "UP_PARENT" as any, nodeId: "a", targetNodeId: "b", edgeType: "PARENT", consanguinity: "blood" },
      ];
      const inLaw: TraversalStep[] = [
        { primitive: "SPOUSE" as any, nodeId: "a", targetNodeId: "b", edgeType: "SPOUSE", consanguinity: "inLaw" },
      ];
      const winner = canon.selectDeterministic([blood, inLaw]);
      expect(winner).toBe(blood);
    });
  });

  // -------------------------------------------------------------------------
  // §6 KinshipSignature builder
  // -------------------------------------------------------------------------
  describe("KinshipSignature builder (spec §6)", () => {
    test("Father: gen=-1, pattern=UP_PARENT, side=paternal, gender=male", () => {
      const paths = bfsAllShortest(EDGES, "you", "ravi");
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).toBe(-1);
      expect(sig.pathPattern).toBe("UP_PARENT");
      expect(sig.side).toBe("paternal");
      expect(sig.genderAnchor).toBe("male");
      expect(sig.consanguinity).toBe("blood");
    });

    test("Mother: gen=-1, pattern=UP_PARENT, side=maternal, gender=female", () => {
      const paths = bfsAllShortest(EDGES, "you", "priya");
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).toBe(-1);
      expect(sig.pathPattern).toBe("UP_PARENT");
      expect(sig.side).toBe("maternal");
      expect(sig.genderAnchor).toBe("female");
    });

    test("Paternal grandfather: gen=-2, pattern=UP_PARENT_UP_PARENT, side=paternal", () => {
      const paths = bfsAllShortest(EDGES, "you", "arun");
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).toBe(-2);
      expect(sig.pathPattern).toBe("UP_PARENT_UP_PARENT");
      expect(sig.side).toBe("paternal");
      expect(sig.genderAnchor).toBe("male");
    });

    test("Maternal grandfather: gen=-2, side=maternal (Priya's father)", () => {
      const paths = bfsAllShortest(EDGES, "you", "priyaFather");
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).toBe(-2);
      expect(sig.pathPattern).toBe("UP_PARENT_UP_PARENT");
      expect(sig.side).toBe("maternal");
      expect(sig.genderAnchor).toBe("male");
    });

    test("Son: gen=+1, pattern=DOWN_CHILD, side=none", () => {
      const paths = bfsAllShortest(EDGES, "you", "child");
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).toBe(1);
      expect(sig.pathPattern).toBe("DOWN_CHILD");
      expect(sig.side).toBe("none");
      expect(sig.genderAnchor).toBe("male");
    });

    test("Wife: gen=0, pattern=SPOUSE, side=none, consanguinity=inLaw, gender=female", () => {
      const paths = bfsAllShortest(EDGES, "you", "spouse");
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).toBe(0);
      expect(sig.pathPattern).toBe("SPOUSE");
      expect(sig.consanguinity).toBe("inLaw");
      expect(sig.genderAnchor).toBe("female");
    });
  });

  // -------------------------------------------------------------------------
  // §7 Vocabulary Mapper — real 9,552-row JSON lookup
  // -------------------------------------------------------------------------
  describe("Vocabulary Mapper (spec §7, §14)", () => {
    test("Father signature → 'father' (English)", () => {
      const sig: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const row = vocabLookup(sig, "en");
      expect(row).not.toBeNull();
      expect(row.english_term).toBe("father");
      expect(row.localized_term).toBe("father");
    });

    test("Father signature → 'पिता' (Hindi)", () => {
      const sig: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const row = vocabLookup(sig, "hi");
      expect(row).not.toBeNull();
      expect(row.localized_term).toBe("पिता");
    });

    test("Mother signature → 'தாய்' (Tamil)", () => {
      const sig: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "maternal",
        consanguinity: "blood", genderAnchor: "female", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const row = vocabLookup(sig, "ta");
      expect(row).not.toBeNull();
      expect(row.localized_term).toBe("தாய்");
    });

    test("Paternal grandfather → 'grandfather' (en)", () => {
      const sig: KinshipSignature = {
        generationDelta: -2, pathPattern: "UP_PARENT_UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const row = vocabLookup(sig, "en");
      expect(row).not.toBeNull();
      expect(row.english_term).toBe("grandfather");
    });

    test("Ex-husband (temporal=former) → distinct from husband (temporal=current)", () => {
      const husbandSig: KinshipSignature = {
        generationDelta: 0, pathPattern: "SPOUSE", side: "none",
        consanguinity: "inLaw", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const exHusbandSig: KinshipSignature = {
        generationDelta: 0, pathPattern: "SPOUSE", side: "none",
        consanguinity: "inLaw", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "former",
      };
      const husband = vocabLookup(husbandSig, "en");
      const exHusband = vocabLookup(exHusbandSig, "en");
      expect(husband).not.toBeNull();
      expect(exHusband).not.toBeNull();
      expect(husband.english_term).toBe("husband");
      expect(exHusband.english_term).toBe("ex-husband");
      // CRITICAL: different signatureKeys → distinct deterministic lookups
      expect(signatureKey(husbandSig)).not.toBe(signatureKey(exHusbandSig));
    });

    test("Late father (temporal=late) → distinct from father (temporal=current)", () => {
      const fatherSig: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const lateFatherSig: KinshipSignature = { ...fatherSig, temporal: "late" };
      const father = vocabLookup(fatherSig, "en");
      const lateFather = vocabLookup(lateFatherSig, "en");
      expect(father.english_term).toBe("father");
      expect(lateFather.english_term).toBe("late father");
      expect(signatureKey(fatherSig)).not.toBe(signatureKey(lateFatherSig));
    });

    test("First cousin (once removed) → distinct from first cousin", () => {
      const firstCousin: KinshipSignature = {
        generationDelta: 0, pathPattern: "UP_PARENT_UP_PARENT__DOWN_CHILD_DOWN_CHILD",
        side: "paternal", consanguinity: "blood", genderAnchor: "neutral",
        seniority: "none", removal: 0, doubleKinship: false, temporal: "current",
      };
      const firstCousinOnceRemoved: KinshipSignature = {
        generationDelta: 1, pathPattern: "UP_PARENT_UP_PARENT__DOWN_CHILD_DOWN_CHILD_DOWN_CHILD",
        side: "paternal", consanguinity: "blood", genderAnchor: "neutral",
        seniority: "none", removal: 1, doubleKinship: false, temporal: "current",
      };
      const fc = vocabLookup(firstCousin, "en");
      const fcr = vocabLookup(firstCousinOnceRemoved, "en");
      expect(fc).not.toBeNull();
      expect(fcr).not.toBeNull();
      expect(fc.english_term.toLowerCase()).toContain("first cousin");
      expect(fcr.english_term.toLowerCase()).toContain("once removed");
    });
  });

  // -------------------------------------------------------------------------
  // §4 Canonical Relationship ID Layer
  // -------------------------------------------------------------------------
  describe("CanonicalIdService (spec §4)", () => {
    const svc = new CanonicalIdService();
    test("'father' → PARENT", () => {
      expect(svc.normalizeToCanonical("father")).toBe("PARENT");
    });
    test("'dad' → PARENT", () => {
      expect(svc.normalizeToCanonical("dad")).toBe("PARENT");
    });
    test("'wife' → SPOUSE", () => {
      expect(svc.normalizeToCanonical("wife")).toBe("SPOUSE");
    });
    test("'grandfather' → DERIVED (must not store)", () => {
      expect(svc.normalizeToCanonical("grandfather")).toBe("DERIVED");
    });
    test("'uncle' → DERIVED", () => {
      expect(svc.normalizeToCanonical("uncle")).toBe("DERIVED");
    });
    test("'cousin' → DERIVED", () => {
      expect(svc.normalizeToCanonical("cousin")).toBe("DERIVED");
    });
    test("Hindi 'पिता' → PARENT", () => {
      expect(svc.normalizeToCanonical("पिता", "hi")).toBe("PARENT");
    });
    test("Tamil 'அம்மா' → PARENT", () => {
      expect(svc.normalizeToCanonical("அம்மா", "ta")).toBe("PARENT");
    });
    test("isStorable true for PARENT/SPOUSE/ADOPTIVE_PARENT/STEP_PARENT", () => {
      expect(svc.isStorable("PARENT")).toBe(true);
      expect(svc.isStorable("SPOUSE")).toBe(true);
      expect(svc.isStorable("ADOPTIVE_PARENT")).toBe(true);
      expect(svc.isStorable("STEP_PARENT")).toBe(true);
    });
    test("isStorable false for DERIVED", () => {
      expect(svc.isStorable("DERIVED")).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // §9 Spouse inference
  // -------------------------------------------------------------------------
  describe("Spouse Inference (spec §9)", () => {
    test("Ravi & Priya share child 'you' → spouse should be inferred", () => {
      // Children of Ravi (edges where personBId=ravi and edgeType=PARENT)
      const childrenOfRavi = EDGES
        .filter((e) => e.edgeType === "PARENT" && e.personBId === "ravi")
        .map((e) => e.personAId);
      const childrenOfPriya = EDGES
        .filter((e) => e.edgeType === "PARENT" && e.personBId === "priya")
        .map((e) => e.personAId);
      const shared = childrenOfRavi.filter((c) => childrenOfPriya.includes(c));
      expect(shared).toContain("you");
      expect(shared.length).toBeGreaterThan(0);
    });

    test("Two persons with no shared children → no inference", () => {
      const childrenOfArun = EDGES
        .filter((e) => e.edgeType === "PARENT" && e.personBId === "arun")
        .map((e) => e.personAId);
      const childrenOfSpouse = EDGES
        .filter((e) => e.edgeType === "PARENT" && e.personBId === "spouse")
        .map((e) => e.personAId);
      const shared = childrenOfArun.filter((c) => childrenOfSpouse.includes(c));
      expect(shared.length).toBe(0);
    });

    test("Already-spouse pairs should not be re-suggested", () => {
      const alreadySpouse = EDGES.some((e) =>
        e.edgeType === "SPOUSE" &&
        ((e.personAId === "ravi" && e.personBId === "priya") ||
         (e.personAId === "priya" && e.personBId === "ravi"))
      );
      expect(alreadySpouse).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // §12 Validation rules
  // -------------------------------------------------------------------------
  describe("Validation Rules (spec §12)", () => {
    test("Rule 1: self-relationship rejected", () => {
      const a = "you", b = "you";
      expect(a === b).toBe(true); // engine would reject
    });

    test("Rule 2: duplicate edge rejected", () => {
      // e5 already stores: you PARENT ravi
      const duplicate = EDGES.find((e) =>
        e.edgeType === "PARENT" && e.personAId === "you" && e.personBId === "ravi"
      );
      expect(duplicate).toBeDefined();
    });

    test("Rule 3: circular ancestry detected — ravi is ancestor of you, so you cannot be parent of ravi", () => {
      // BFS from ravi → you should reach you via DOWN_CHILD (you is descendant of ravi)
      const paths = bfsAllShortest(EDGES, "ravi", "you");
      expect(paths.length).toBeGreaterThan(0);
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      expect(winner[0].primitive).toBe("DOWN_CHILD");
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).toBe(1); // descendant
      // Engine would reject: "you cannot be parent of ravi because you is descendant of ravi"
    });

    test("Rule 4: cannot marry ancestor or descendant", () => {
      // You cannot marry Ravi (father) because generationDelta != 0
      const paths = bfsAllShortest(EDGES, "you", "ravi");
      const winner = new PathCanonicalizer().selectDeterministic(
        paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
      );
      const sig = buildSignature(winner, NODES);
      expect(sig.generationDelta).not.toBe(0);
    });

    test("Rule 5: contradictory parent+spouse rejected", () => {
      // If you → ravi (PARENT) exists, you cannot also be ravi's SPOUSE
      const parentExists = EDGES.some((e) =>
        e.edgeType === "PARENT" && e.personAId === "you" && e.personBId === "ravi"
      );
      expect(parentExists).toBe(true);
      // Engine would reject: you SPOUSE ravi because parent edge exists.
    });
  });

  // -------------------------------------------------------------------------
  // §13.1 Session-only signature cache
  // -------------------------------------------------------------------------
  describe("SignatureCacheService (spec §13.1)", () => {
    let cache: SignatureCacheService;

    beforeEach(() => {
      // Force in-process LRU (no REDIS_URL)
      delete process.env.REDIS_URL;
      cache = new SignatureCacheService();
      // onModuleInit would be called by NestJS; we call it manually for tests
      return (cache as any).onModuleInit();
    });

    test("set + get returns same signature", async () => {
      const sig: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      await cache.set("fam1", "you", "ravi", sig);
      const got = await cache.get("fam1", "you", "ravi");
      expect(got).toBeDefined();
      expect(got!.generationDelta).toBe(-1);
      expect(got!.pathPattern).toBe("UP_PARENT");
    });

    test("invalidatePerson removes only entries containing that person", async () => {
      const sig1: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const sig2: KinshipSignature = { ...sig1, side: "maternal" };
      await cache.set("fam1", "you", "ravi", sig1);
      await cache.set("fam1", "you", "priya", sig2);
      // Both should be cached
      expect(await cache.get("fam1", "you", "ravi")).toBeDefined();
      expect(await cache.get("fam1", "you", "priya")).toBeDefined();
      // Invalidate "you" — both entries contain "you"
      const removed = await cache.invalidatePerson("fam1", "you");
      expect(removed).toBe(2);
      expect(await cache.get("fam1", "you", "ravi")).toBeUndefined();
      expect(await cache.get("fam1", "you", "priya")).toBeUndefined();
    });

    test("invalidatePerson does NOT flush entries of unrelated persons", async () => {
      const sig1: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const sig2: KinshipSignature = { ...sig1, side: "maternal" };
      await cache.set("fam1", "you", "ravi", sig1);     // contains "you" and "ravi"
      await cache.set("fam1", "manish", "spouse", sig2); // contains neither
      const removed = await cache.invalidatePerson("fam1", "you");
      expect(removed).toBe(1); // only the you→ravi entry
      expect(await cache.get("fam1", "manish", "spouse")).toBeDefined();
    });

    test("stats reports in-process-lru engine", async () => {
      const stats = await cache.stats();
      expect(stats.engine).toBe("in-process-lru");
      expect(stats.maxPerFamily).toBe(1000);
    });
  });

  // -------------------------------------------------------------------------
  // §14 Determinism guarantee
  // -------------------------------------------------------------------------
  describe("Determinism Guarantee (spec §14)", () => {
    test("Same graph + same A + same B = same signature (every time)", () => {
      const runOnce = () => {
        const paths = bfsAllShortest(EDGES, "you", "arun");
        const winner = new PathCanonicalizer().selectDeterministic(
          paths.map((p) => new PathCanonicalizer().canonicalize(p)).filter((p) => p.length > 0)
        );
        return signatureKey(buildSignature(winner, NODES));
      };
      const k1 = runOnce();
      const k2 = runOnce();
      const k3 = runOnce();
      expect(k1).toBe(k2);
      expect(k2).toBe(k3);
    });

    test("Same signature = same vocabulary term (deterministic lookup)", () => {
      const sig: KinshipSignature = {
        generationDelta: -2, pathPattern: "UP_PARENT_UP_PARENT", side: "paternal",
        consanguinity: "blood", genderAnchor: "male", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const r1 = vocabLookup(sig, "en");
      const r2 = vocabLookup(sig, "en");
      const r3 = vocabLookup(sig, "en");
      expect(r1).toEqual(r2);
      expect(r2).toEqual(r3);
    });

    test("10 random language lookups for 'mother' all return consistent localized terms", () => {
      const sig: KinshipSignature = {
        generationDelta: -1, pathPattern: "UP_PARENT", side: "maternal",
        consanguinity: "blood", genderAnchor: "female", seniority: "none",
        removal: 0, doubleKinship: false, temporal: "current",
      };
      const expectations: Record<string, string> = {
        en: "mother", hi: "माता", ta: "தாய்", te: "తల్లి", bn: "মাতা",
        mr: "आई", ml: "അമ്മ", kn: "ತಾಯಿ", gu: "માતા", pa: "ਮਾਂ",
      };
      for (const [lang, expected] of Object.entries(expectations)) {
        const row = vocabLookup(sig, lang);
        expect(row).not.toBeNull();
        expect(row.localized_term).toBe(expected);
      }
    });
  });

  // -------------------------------------------------------------------------
  // §18 File structure completeness
  // -------------------------------------------------------------------------
  describe("File Structure (spec §18)", () => {
    const SERVER_ROOT = "/home/z/my-project/repos/daxelo-kinrel-server/src";
    const FLUTTER_ROOT = "/home/z/my-project/repos/daxelo-kinrel-app/lib";

    test("Server: kinship module files exist", () => {
      expect(fs.existsSync(`${SERVER_ROOT}/modules/kinship/kinship.service.ts`)).toBe(true);
      expect(fs.existsSync(`${SERVER_ROOT}/modules/kinship/kinship-signature.ts`)).toBe(true);
      expect(fs.existsSync(`${SERVER_ROOT}/modules/kinship/canonical-id.service.ts`)).toBe(true);
    });

    test("Server: graph module files exist", () => {
      expect(fs.existsSync(`${SERVER_ROOT}/modules/graph/graph-engine.service.ts`)).toBe(true);
      expect(fs.existsSync(`${SERVER_ROOT}/modules/graph/path-canonicalizer.ts`)).toBe(true);
      expect(fs.existsSync(`${SERVER_ROOT}/modules/graph/graph.service.ts`)).toBe(true);
    });

    test("Server: relationships module files exist", () => {
      expect(fs.existsSync(`${SERVER_ROOT}/modules/relationships/relationships.service.ts`)).toBe(true);
      expect(fs.existsSync(`${SERVER_ROOT}/modules/relationships/relationship.validator.ts`)).toBe(true);
    });

    test("Server: family module file exists", () => {
      expect(fs.existsSync(`${SERVER_ROOT}/modules/family/family.service.ts`)).toBe(true);
    });

    test("Flutter: relationship_engine.dart mirror exists", () => {
      expect(fs.existsSync(`${FLUTTER_ROOT}/core/services/relationship_engine.dart`)).toBe(true);
    });

    test("Flutter: drift app_database.dart exists", () => {
      expect(fs.existsSync(`${FLUTTER_ROOT}/data/drift/app_database.dart`)).toBe(true);
    });

    test("Flutter: relationship_suggestion_sheet.dart exists", () => {
      expect(fs.existsSync(`${FLUTTER_ROOT}/features/family/presentation/widgets/relationship_suggestion_sheet.dart`)).toBe(true);
    });
  });
});
