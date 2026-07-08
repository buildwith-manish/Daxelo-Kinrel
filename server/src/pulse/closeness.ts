// server/src/pulse/closeness.ts
//
// PULSE Phase 2 — Pure graph-aware personalization computations.
//
// This file has ZERO NestJS dependencies — it can be unit-tested standalone with `bun`.
// (Same pattern as AURA's `graph-metrics.ts` and `brief-types.ts`.)
//
// It computes a 0.0–1.0 "closeness score" between two Persons in a family,
// derived from graph topology + AURA roles + relationship semantics.
// This score becomes the `relevanceScore` field on BriefItem rows, and is used
// by the orchestrator to reorder items when priorities are close.
//
// Why this matters: in Phase 1, BirthdayCollector gave priority 50 to "Person
// with no direct relationship to the user". That's wrong if the Person is the
// user's grandparent's sibling (a close elder) vs a distant cousin-in-law. The
// closeness score lets us differentiate.
//
// Algorithm (closeness score = weighted blend of 5 signals):
//
//   1. Graph distance (0-1)        — BFS shortest path between user's Person
//                                     and target Person. 1.0 if same person,
//                                     0.5 if 1 hop, 0.3 if 2 hops, 0.1 if 3+,
//                                     0.0 if disconnected. Weight: 30%
//
//   2. Generation distance (0-1)   — |genIndex difference|. 1.0 if same gen,
//                                     0.7 if ±1 gen, 0.4 if ±2 gens, 0.1 if
//                                     3+ gens. Weight: 15%
//
//   3. Relationship semantic (0-1) — direct relationship type. Parent/child/
//                                     spouse = 1.0; sibling = 0.9; grandparent
//                                     = 0.85; aunt/uncle = 0.75; cousin = 0.6;
//                                     niece/nephew = 0.7; in-law = 0.5;
//                                     unrelated = 0.1. Weight: 35%
//
//   4. AURA role match (0-1)       — if BOTH Persons have AURA roles, score
//                                     based on complementary roles:
//                                       anchor + leaf    = 0.9 (anchor cares for leaf)
//                                       bridge + weaver  = 0.8 (bridge connects, weaver maintains)
//                                       root + any       = 0.85 (root is respected by all)
//                                       same role        = 0.6 (peer)
//                                       otherwise        = 0.5
//                                     Weight: 10%
//
//   5. Shared connections (0-1)    — Jaccard similarity of each Person's
//                                     relationship neighbors. 1.0 if all
//                                     neighbors shared, 0.0 if none. Weight: 10%
//
// Final: closeness = 0.30*dist + 0.15*gen + 0.35*sem + 0.10*aura + 0.10*shared
// Range: 0.0 – 1.0
//
// Edge cases:
//   - If user has no Person node (linkedPerson is null), return 0.5 (neutral)
//   - If target is the user's own Person, return 1.0
//   - If the graph has no path between them (disconnected components), still
//     compute the other 4 signals using only direct relationship semantics

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

/** A Person node in the family graph, with only the fields needed for closeness. */
export interface PersonNode {
  id: string;
  generationIndex: number;
}

/** A directed relationship edge in the family graph. */
export interface RelationshipEdge {
  fromPersonId: string;
  toPersonId: string;
  relationshipType: string; // e.g. 'father', 'mother', 'spouse', 'cousin'
}

/** AURA role for a Person (from MemberAuraRole). */
export interface AuraRole {
  personId: string;
  roleKey: string; // root | anchor | bridge | weaver | leaf | twin_node
}

/** Input bundle for closeness computation. */
export interface ClosenessInput {
  userPersonId: string | null; // null if user has no linkedPerson
  targetPersonId: string;
  persons: PersonNode[];
  relationships: RelationshipEdge[];
  auraRoles: AuraRole[];
}

/** Output bundle — full breakdown for debugging + transparency. */
export interface ClosenessResult {
  total: number; // 0.0 – 1.0
  graphDistance: number; // 0.0 – 1.0
  generationDistance: number; // 0.0 – 1.0
  relationshipSemantic: number; // 0.0 – 1.0
  auraRoleMatch: number; // 0.0 – 1.0
  sharedConnections: number; // 0.0 – 1.0
  hopCount: number | null; // null if disconnected
  notes: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Relationship semantic scores
// ─────────────────────────────────────────────────────────────────────────────
//
// Map relationshipType strings (used in the Relationship.relationshipType column)
// to semantic closeness scores. The values come from Indian family kinship norms:
//   - Parents/children/spouses are the closest
//   - Siblings are nearly as close
//   - Grandparents are very close (cultural respect)
//   - Aunts/uncles (mother's brother = "mama", father's sister = "bua") are close
//   - First cousins are moderately close (especially in joint families)
//   - In-laws are close but slightly less than blood
//   - Distant relatives (second cousins, etc.) are far
//
const RELATIONSHIP_SEMANTIC: Record<string, number> = {
  // Direct line — closest
  father: 1.0,
  mother: 1.0,
  son: 1.0,
  daughter: 1.0,
  husband: 1.0,
  wife: 1.0,
  spouse: 1.0,
  parent: 1.0,
  child: 1.0,

  // Siblings — very close
  brother: 0.9,
  sister: 0.9,
  sibling: 0.9,

  // Grandparents — very close (cultural respect)
  grandfather: 0.85,
  grandmother: 0.85,
  grandson: 0.85,
  granddaughter: 0.85,
  grandparent: 0.85,
  grandchild: 0.85,

  // Aunt/uncle — close
  uncle: 0.75,
  aunt: 0.75,
  nephew: 0.7,
  niece: 0.7,

  // First cousins — moderately close
  cousin: 0.6,

  // In-laws — close but slightly less than blood
  father_in_law: 0.7,
  mother_in_law: 0.7,
  brother_in_law: 0.65,
  sister_in_law: 0.65,
  son_in_law: 0.7,
  daughter_in_law: 0.7,

  // Step/half — slightly less than full
  stepfather: 0.6,
  stepmother: 0.6,
  stepson: 0.6,
  stepdaughter: 0.6,
  half_brother: 0.75,
  half_sister: 0.75,

  // Distant
  custom: 0.3,
};

const DEFAULT_SEMANTIC = 0.3;

// ─────────────────────────────────────────────────────────────────────────────
// AURA role pair scores
// ─────────────────────────────────────────────────────────────────────────────
//
// These capture "how much does this role-pair naturally care about each other":
//   - Anchor (the family caretaker) cares deeply for everyone, especially leaves
//   - Bridge (the connector) cares for weavers (who maintain sub-graphs)
//   - Root (the elder) is respected by everyone
//   - Twin nodes (siblings/cousins close in age) are peers
//
// We use a Map keyed by sorted `roleA|roleB` strings.
//
const AURA_ROLE_PAIR_SCORE: Record<string, number> = {
  'anchor|leaf': 0.9,
  'anchor|root': 0.85,
  'anchor|bridge': 0.7,
  'anchor|weaver': 0.65,
  'anchor|twin_node': 0.75,
  'anchor|anchor': 0.6, // peer anchors
  'bridge|weaver': 0.8,
  'bridge|leaf': 0.65,
  'bridge|root': 0.7,
  'bridge|twin_node': 0.7,
  'bridge|bridge': 0.55,
  'root|leaf': 0.85,
  'root|weaver': 0.75,
  'root|twin_node': 0.7,
  'root|root': 0.5,
  'weaver|leaf': 0.7,
  'weaver|twin_node': 0.65,
  'weaver|weaver': 0.6,
  'leaf|twin_node': 0.85, // peers, often close in age
  'leaf|leaf': 0.55,
  'twin_node|twin_node': 0.85, // siblings/cousins
};

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compute the closeness score between the user's Person and a target Person.
 *
 * Returns a ClosenessResult with the total score + per-signal breakdown.
 * Used by:
 *   - BriefGeneratorService (to set BriefItem.relevanceScore)
 *   - Phase 2 reordering logic (when priorities are within ±5 of each other)
 */
export function computeCloseness(input: ClosenessInput): ClosenessResult {
  const notes: string[] = [];

  // Edge case: user has no linkedPerson → return neutral 0.5
  if (!input.userPersonId) {
    return {
      total: 0.5,
      graphDistance: 0.5,
      generationDistance: 0.5,
      relationshipSemantic: 0.5,
      auraRoleMatch: 0.5,
      sharedConnections: 0.5,
      hopCount: null,
      notes: ['User has no linkedPerson — returning neutral 0.5'],
    };
  }

  // Edge case: target IS the user's Person
  if (input.userPersonId === input.targetPersonId) {
    return {
      total: 1.0,
      graphDistance: 1.0,
      generationDistance: 1.0,
      relationshipSemantic: 1.0,
      auraRoleMatch: 1.0,
      sharedConnections: 1.0,
      hopCount: 0,
      notes: ['Target is the user themselves'],
    };
  }

  // ── 1. Graph distance (BFS shortest path) ────────────────────────────
  const hopCount = bfsShortestPath(
    input.userPersonId,
    input.targetPersonId,
    input.relationships,
  );
  let graphDistance: number;
  if (hopCount === null) {
    graphDistance = 0.0;
    notes.push('Disconnected in graph (no path found)');
  } else if (hopCount === 0) {
    graphDistance = 1.0;
  } else if (hopCount === 1) {
    graphDistance = 0.85;
  } else if (hopCount === 2) {
    graphDistance = 0.5;
  } else if (hopCount === 3) {
    graphDistance = 0.3;
  } else {
    graphDistance = 0.1;
  }
  notes.push(`Graph distance: ${hopCount === null ? '∞' : hopCount} hops → ${graphDistance}`);

  // ── 2. Generation distance ───────────────────────────────────────────
  const userPerson = input.persons.find((p) => p.id === input.userPersonId);
  const targetPerson = input.persons.find((p) => p.id === input.targetPersonId);
  let generationDistance: number;
  if (!userPerson || !targetPerson) {
    generationDistance = 0.5;
    notes.push('Missing Person node — generation distance defaulting to 0.5');
  } else {
    const genDiff = Math.abs(userPerson.generationIndex - targetPerson.generationIndex);
    if (genDiff === 0) generationDistance = 1.0;
    else if (genDiff === 1) generationDistance = 0.7;
    else if (genDiff === 2) generationDistance = 0.4;
    else generationDistance = 0.1;
    notes.push(`Generation distance: ${genDiff} → ${generationDistance}`);
  }

  // ── 3. Relationship semantic ─────────────────────────────────────────
  // Find any direct relationship between user ↔ target (in either direction)
  const directRel = input.relationships.find(
    (r) =>
      (r.fromPersonId === input.userPersonId && r.toPersonId === input.targetPersonId) ||
      (r.fromPersonId === input.targetPersonId && r.toPersonId === input.userPersonId),
  );
  let relationshipSemantic: number;
  if (directRel) {
    const relType = (directRel.relationshipType || '').toLowerCase();
    relationshipSemantic = RELATIONSHIP_SEMANTIC[relType] ?? DEFAULT_SEMANTIC;
    notes.push(`Direct relationship '${directRel.relationshipType}' → ${relationshipSemantic}`);
  } else {
    relationshipSemantic = 0.1; // no direct relationship
    notes.push('No direct relationship → 0.1');
  }

  // ── 4. AURA role match ───────────────────────────────────────────────
  const userRole = input.auraRoles.find((r) => r.personId === input.userPersonId)?.roleKey;
  const targetRole = input.auraRoles.find((r) => r.personId === input.targetPersonId)?.roleKey;
  let auraRoleMatch: number;
  if (!userRole || !targetRole) {
    auraRoleMatch = 0.5;
    notes.push('Missing AURA role for one or both Persons → 0.5');
  } else {
    const pairKey = [userRole, targetRole].sort().join('|');
    auraRoleMatch = AURA_ROLE_PAIR_SCORE[pairKey] ?? 0.5;
    notes.push(`AURA role pair '${userRole}'↔'${targetRole}' → ${auraRoleMatch}`);
  }

  // ── 5. Shared connections (Jaccard) ──────────────────────────────────
  const userNeighbors = getNeighbors(input.userPersonId, input.relationships);
  const targetNeighbors = getNeighbors(input.targetPersonId, input.relationships);
  let sharedConnections: number;
  if (userNeighbors.size === 0 && targetNeighbors.size === 0) {
    sharedConnections = 0.0;
    notes.push('Both Persons have no neighbors → 0.0');
  } else {
    const intersection = new Set([...userNeighbors].filter((x) => targetNeighbors.has(x)));
    const union = new Set([...userNeighbors, ...targetNeighbors]);
    sharedConnections = union.size === 0 ? 0 : intersection.size / union.size;
    notes.push(`Shared: ${intersection.size}/${union.size} → ${sharedConnections.toFixed(3)}`);
  }

  // ── Blend ────────────────────────────────────────────────────────────
  const total =
    0.30 * graphDistance +
    0.15 * generationDistance +
    0.35 * relationshipSemantic +
    0.10 * auraRoleMatch +
    0.10 * sharedConnections;

  return {
    total: round(total, 3),
    graphDistance,
    generationDistance,
    relationshipSemantic,
    auraRoleMatch,
    sharedConnections,
    hopCount,
    notes,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * BFS shortest path between two Persons in an undirected graph built from
 * directed Relationship edges (treated as undirected for distance purposes —
 * "A is father of B" implies B can reach A in 1 hop).
 *
 * Returns the hop count (0 = same node, 1 = direct, 2 = through one intermediate,
 * etc.) or null if no path exists. Caps at 6 hops (returns 6 even if farther).
 */
export function bfsShortestPath(
  fromId: string,
  toId: string,
  edges: RelationshipEdge[],
): number | null {
  if (fromId === toId) return 0;

  // Build adjacency list (undirected)
  const adj = new Map<string, Set<string>>();
  for (const e of edges) {
    if (!adj.has(e.fromPersonId)) adj.set(e.fromPersonId, new Set());
    if (!adj.has(e.toPersonId)) adj.set(e.toPersonId, new Set());
    adj.get(e.fromPersonId)!.add(e.toPersonId);
    adj.get(e.toPersonId)!.add(e.fromPersonId);
  }

  if (!adj.has(fromId) || !adj.has(toId)) return null;

  const visited = new Set<string>([fromId]);
  let frontier: string[] = [fromId];
  let hops = 0;

  while (frontier.length > 0 && hops < 6) {
    hops++;
    const next: string[] = [];
    for (const node of frontier) {
      const neighbors = adj.get(node);
      if (!neighbors) continue;
      for (const n of neighbors) {
        if (n === toId) return hops;
        if (!visited.has(n)) {
          visited.add(n);
          next.push(n);
        }
      }
    }
    frontier = next;
  }
  return null;
}

/** Get all neighbors of a Person (undirected — both from and to edges). */
export function getNeighbors(
  personId: string,
  edges: RelationshipEdge[],
): Set<string> {
  const neighbors = new Set<string>();
  for (const e of edges) {
    if (e.fromPersonId === personId) neighbors.add(e.toPersonId);
    if (e.toPersonId === personId) neighbors.add(e.fromPersonId);
  }
  return neighbors;
}

/** Round to N decimal places. */
function round(n: number, decimals: number): number {
  const factor = Math.pow(10, decimals);
  return Math.round(n * factor) / factor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 reordering: when two items have priorities within ±5 of each other,
// the one with higher closeness score goes first.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Phase 2 tie-breaking sort. Use AFTER the priority sort has run.
 * For items within `priorityWindow` (default 5) of each other, reorder by
 * closeness score DESC.
 *
 * This is a stable sort within priority "buckets" — it doesn't change the
 * order of items with very different priorities, only breaks ties.
 */
export function applyClosenessTieBreaker<T extends { priority: number; relevanceScore?: number }>(
  items: T[],
  priorityWindow: number = 5,
): T[] {
  if (items.length <= 1) return items;

  const result: T[] = [...items];
  // Sort by priority DESC first (stable)
  result.sort((a, b) => b.priority - a.priority);

  // Then within each priority window, sort by relevanceScore DESC
  // We do a single pass: for each adjacent pair, if priorities are within the
  // window AND the lower-relevance item is above the higher-relevance one,
  // swap them. This is a simple insertion sort within windows — not perfectly
  // optimal but good enough for the small N (6 items) we deal with.
  let i = 0;
  while (i < result.length - 1) {
    let j = i + 1;
    // Find the end of this priority window
    while (j < result.length && result[i].priority - result[j].priority <= priorityWindow) {
      j++;
    }
    // Sort the window [i, j) by relevanceScore DESC
    const window = result.slice(i, j);
    window.sort((a, b) => (b.relevanceScore ?? 0.5) - (a.relevanceScore ?? 0.5));
    for (let k = 0; k < window.length; k++) {
      result[i + k] = window[k];
    }
    i = j;
  }

  return result;
}
