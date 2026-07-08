// server/src/aura/graph-metrics.ts
//
// AURA — Pure graph computation module (no NestJS / Prisma dependencies).
//
// This file contains ALL the graph algorithms: adjacency construction,
// BFS generation assignment, clustering coefficient, all-pairs shortest
// paths, Brandes betweenness centrality, lineage detection (union-find),
// and language distribution derivation.
//
// It is deliberately separated from graph-analysis.service.ts so it can
// be unit-tested in isolation without importing NestJS.
//
// ─────────────────────────────────────────────────────────────────────────
// TYPES
// ─────────────────────────────────────────────────────────────────────────

export interface GraphNode {
  id: string;
}

export interface GraphEdge {
  fromId: string;
  toId: string;
  relationshipType: string; // e.g. 'father', 'mother', 'spouse', 'amma', 'pita'
  direction: string;        // 'from' = fromPerson IS the relationshipType of toPerson
}

export interface AdjacencyMap {
  [nodeId: string]: string[];
}

export interface GraphMetrics {
  memberCount: number;
  edgeCount: number;
  generationDepth: number;          // max generation index + 1
  clusteringCoefficient: number;    // 0.0–1.0
  graphDiameter: number;            // longest shortest path
  avgDegree: number;                // average connections per node
  maxBetweennessNodeId: string | null;  // the "anchor"
  rootNodeId: string | null;        // oldest ancestor (gen-0 with most connections)
  distinctLineages: number;         // connected components via parent-child edges

  betweennessMap: Record<string, number>;  // normalized 0.0–1.0
  degreeMap: Record<string, number>;
  generationMap: Record<string, number>;

  languageDistribution: Record<string, number>; // ISO-639-1 code → ratio (sums to 1.0)
}

// ─────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────

// Relationship types where the person described IS a parent.
// When direction='from', fromPerson is the parent.
// When direction='to', toPerson is the parent.
const PARENT_TYPES = new Set([
  // English / generic
  'father', 'mother', 'parent', 'stepfather', 'stepmother',
  // Hindi
  'pita', 'mata', 'pitaji', 'bapu',
  // Tamil
  'appa', 'amma', 'thandhai', 'thaye',
  // Telugu
  'nanna', 'naanna',
  // Kannada
  'thande', 'thaayi',
  // Malayalam
  'achan', 'ammachi',
  // Marathi
  'baba', 'aai',
  // Bengali
  'ma', 'baba_bn',
  // Punjabi
  'papa',
]);

// Relationship types where the person described IS a child.
// When direction='from', fromPerson is the child → toPerson is the parent.
const CHILD_TYPES = new Set([
  'son', 'daughter', 'child', 'beta', 'betti',
]);

// Map of relationship-type strings → ISO-639-1 language code.
// Used to derive the family's linguistic fingerprint from edge types.
// Unambiguous Indian-language kinship terms are mapped; English/generic
// terms are mapped to 'en'; unknown terms fall back to familyPrimaryLanguage.
const RELATIONSHIP_TYPE_TO_LANGUAGE: Record<string, string> = {
  // English
  father: 'en', mother: 'en', parent: 'en', spouse: 'en',
  son: 'en', daughter: 'en', brother: 'en', sister: 'en',
  husband: 'en', wife: 'en', custom: 'en',
  stepfather: 'en', stepmother: 'en',
  // Hindi
  pita: 'hi', mata: 'hi', pitaji: 'hi', bapu: 'hi',
  // Tamil
  appa: 'ta', amma: 'ta', thandhai: 'ta', thaye: 'ta',
  // Telugu
  nanna: 'te', naanna: 'te',
  // Kannada
  thande: 'kn', thaayi: 'kn',
  // Malayalam
  achan: 'ml', ammachi: 'ml',
  // Marathi
  baba: 'mr', aai: 'mr',
  // Bengali
  ma: 'bn', baba_bn: 'bn',
  // Punjabi
  papa: 'pa',
};

// ─────────────────────────────────────────────────────────────────────────
// HELPER: resolve parent-child direction from an edge
// ─────────────────────────────────────────────────────────────────────────

/**
 * Given a GraphEdge, determine the parent→child direction.
 * Returns { parentId, childId } if the edge is a parent-child relationship,
 * or null if it's a spouse/sibling/other non-hierarchical edge.
 *
 * Direction semantics (from the Relationship table schema):
 *   direction='from' → fromPerson IS the relationshipType of toPerson
 *   direction='to'   → toPerson IS the relationshipType of fromPerson
 *
 * So for relationshipType='father', direction='from':
 *   fromPerson is the father → fromPerson is parent, toPerson is child.
 */
function resolveParentChild(edge: GraphEdge): { parentId: string; childId: string } | null {
  const type = edge.relationshipType.toLowerCase().trim();

  if (PARENT_TYPES.has(type)) {
    if (edge.direction === 'to') {
      return { parentId: edge.toId, childId: edge.fromId };
    }
    return { parentId: edge.fromId, childId: edge.toId };
  }

  if (CHILD_TYPES.has(type)) {
    if (edge.direction === 'to') {
      return { parentId: edge.fromId, childId: edge.toId };
    }
    return { parentId: edge.toId, childId: edge.fromId };
  }

  return null; // spouse, sibling, or unknown — not a parent-child edge
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: build undirected adjacency map
// ─────────────────────────────────────────────────────────────────────────

function buildAdjacency(nodes: GraphNode[], edges: GraphEdge[]): AdjacencyMap {
  const adj: AdjacencyMap = {};
  for (const node of nodes) {
    adj[node.id] = [];
  }
  for (const edge of edges) {
    if (!adj[edge.fromId]) adj[edge.fromId] = [];
    if (!adj[edge.toId]) adj[edge.toId] = [];
    // Undirected: both directions, deduped
    if (!adj[edge.fromId].includes(edge.toId)) adj[edge.fromId].push(edge.toId);
    if (!adj[edge.toId].includes(edge.fromId)) adj[edge.toId].push(edge.fromId);
  }
  return adj;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: assign generations via BFS from roots (nodes with no parents)
// ─────────────────────────────────────────────────────────────────────────

function assignGenerations(nodes: GraphNode[], edges: GraphEdge[]): Record<string, number> {
  const childMap: Record<string, string[]> = {};
  const parentMap: Record<string, string[]> = {};
  for (const node of nodes) {
    childMap[node.id] = [];
    parentMap[node.id] = [];
  }

  for (const edge of edges) {
    const pc = resolveParentChild(edge);
    if (pc) {
      childMap[pc.parentId].push(pc.childId);
      parentMap[pc.childId].push(pc.parentId);
    }
  }

  // Roots: nodes with no parents
  const roots = nodes.filter((n) => parentMap[n.id].length === 0).map((n) => n.id);

  const genMap: Record<string, number> = {};
  const queue: Array<{ id: string; gen: number }> = roots.map((r) => ({ id: r, gen: 0 }));

  while (queue.length > 0) {
    const { id, gen } = queue.shift()!;
    if (genMap[id] !== undefined) continue;
    genMap[id] = gen;
    for (const childId of childMap[id]) {
      if (genMap[childId] === undefined) {
        queue.push({ id: childId, gen: gen + 1 });
      }
    }
  }

  // Disconnected nodes (no parent path from any root) → generation 0
  for (const node of nodes) {
    if (genMap[node.id] === undefined) genMap[node.id] = 0;
  }

  return genMap;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: degree map
// ─────────────────────────────────────────────────────────────────────────

function computeDegreeMap(adjacency: AdjacencyMap): Record<string, number> {
  const degreeMap: Record<string, number> = {};
  for (const [nodeId, neighbors] of Object.entries(adjacency)) {
    degreeMap[nodeId] = neighbors.length;
  }
  return degreeMap;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: clustering coefficient
// ─────────────────────────────────────────────────────────────────────────
//
// For each node v with degree k ≥ 2:
//   localCC(v) = (2 × triangles among v's neighbors) / (k × (k-1))
// Global CC = mean of localCC(v) for all v with degree ≥ 2.

function computeClusteringCoefficient(nodes: GraphNode[], adjacency: AdjacencyMap): number {
  let totalCC = 0;
  let countedNodes = 0;

  for (const node of nodes) {
    const neighbors = adjacency[node.id] ?? [];
    const k = neighbors.length;
    if (k < 2) continue; // CC undefined for degree < 2

    let triangles = 0;
    for (let i = 0; i < neighbors.length; i++) {
      for (let j = i + 1; j < neighbors.length; j++) {
        if ((adjacency[neighbors[i]] ?? []).includes(neighbors[j])) {
          triangles++;
        }
      }
    }

    const localCC = (2 * triangles) / (k * (k - 1));
    totalCC += localCC;
    countedNodes++;
  }

  return countedNodes > 0 ? totalCC / countedNodes : 0;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: all-pairs shortest paths (BFS from each node)
// ─────────────────────────────────────────────────────────────────────────
//
// O(V × (V + E)). Returns the distances matrix and the graph diameter
// (longest shortest path).

function computeAllPairsShortestPaths(
  nodes: GraphNode[],
  adjacency: AdjacencyMap,
): { distances: Record<string, Record<string, number>>; diameter: number } {
  const distances: Record<string, Record<string, number>> = {};
  let diameter = 0;

  for (const sourceNode of nodes) {
    const dist: Record<string, number> = { [sourceNode.id]: 0 };
    const queue = [sourceNode.id];
    let qi = 0;

    while (qi < queue.length) {
      const current = queue[qi++];
      for (const neighbor of adjacency[current] ?? []) {
        if (dist[neighbor] === undefined) {
          dist[neighbor] = dist[current] + 1;
          queue.push(neighbor);
          if (dist[neighbor] > diameter) diameter = dist[neighbor];
        }
      }
    }

    distances[sourceNode.id] = dist;
  }

  return { distances, diameter };
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: betweenness centrality (Brandes' algorithm)
// ─────────────────────────────────────────────────────────────────────────
//
// Betweenness of node v = fraction of all shortest paths (between all
// unordered pairs s,t where s≠v≠t) that pass through v.
//
// Brandes' algorithm runs in O(V × E) for unweighted graphs.
// For undirected graphs, each path is counted twice (once from each
// endpoint), so we halve all values before normalizing.

function computeBetweennessCentrality(
  nodes: GraphNode[],
  adjacency: AdjacencyMap,
): Record<string, number> {
  const nodeIds = nodes.map((n) => n.id);
  const betweenness: Record<string, number> = {};
  for (const id of nodeIds) betweenness[id] = 0;

  for (const source of nodeIds) {
    // ── Phase 1: BFS from source, tracking predecessors and path counts ──
    const stack: string[] = [];
    const pred: Record<string, string[]> = {};
    const sigma: Record<string, number> = { [source]: 1 };
    const dist: Record<string, number> = { [source]: 0 };
    const queue = [source];
    let qi = 0;

    for (const id of nodeIds) pred[id] = [];

    while (qi < queue.length) {
      const v = queue[qi++];
      stack.push(v);

      for (const w of adjacency[v] ?? []) {
        if (dist[w] === undefined) {
          dist[w] = dist[v] + 1;
          queue.push(w);
        }
        if (dist[w] === dist[v] + 1) {
          sigma[w] = (sigma[w] ?? 0) + (sigma[v] ?? 1);
          pred[w].push(v);
        }
      }
    }

    // ── Phase 2: back-propagate dependencies (delta) ──
    const delta: Record<string, number> = {};
    for (const id of nodeIds) delta[id] = 0;

    while (stack.length > 0) {
      const w = stack.pop()!;
      for (const v of pred[w]) {
        delta[v] += ((sigma[v] ?? 1) / (sigma[w] ?? 1)) * (1 + delta[w]);
      }
      if (w !== source) {
        betweenness[w] += delta[w];
      }
    }
  }

  // ── Normalize for undirected graph ──
  // 1. Halve all values (undo double-counting from ordered pairs)
  // 2. Divide by ((n-1)(n-2))/2 (number of unordered pairs excluding v)
  const n = nodeIds.length;
  if (n > 2) {
    for (const id of nodeIds) betweenness[id] /= 2;
    const norm = ((n - 1) * (n - 2)) / 2;
    for (const id of nodeIds) betweenness[id] /= norm;
  }

  return betweenness;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: lineage detection (union-find on parent-child edges only)
// ─────────────────────────────────────────────────────────────────────────
//
// A "lineage" is a connected component of the ancestor graph.
// We use union-find (disjoint sets) on parent-child edges only.
// Spouse and sibling edges do NOT merge lineages.

function detectLineages(nodes: GraphNode[], edges: GraphEdge[]): number {
  const parent: Record<string, string> = {};
  for (const n of nodes) parent[n.id] = n.id;

  const find = (id: string): string => {
    if (parent[id] !== id) parent[id] = find(parent[id]);
    return parent[id];
  };

  const union = (a: string, b: string) => {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent[ra] = rb;
  };

  for (const edge of edges) {
    const pc = resolveParentChild(edge);
    if (pc) {
      union(pc.parentId, pc.childId);
    }
  }

  const roots = new Set<string>();
  for (const n of nodes) roots.add(find(n.id));
  return roots.size;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: language distribution
// ─────────────────────────────────────────────────────────────────────────
//
// Derives a language code from each edge's relationshipType via the
// RELATIONSHIP_TYPE_TO_LANGUAGE lookup. Unknown types fall back to
// familyPrimaryLanguage. Returns a map of language code → ratio (sums to 1.0).

function computeLanguageDistribution(
  edges: GraphEdge[],
  familyPrimaryLanguage: string,
): Record<string, number> {
  const counts: Record<string, number> = {};
  const fallback = familyPrimaryLanguage || 'hi';

  for (const edge of edges) {
    const type = edge.relationshipType?.toLowerCase()?.trim() ?? '';
    const code = RELATIONSHIP_TYPE_TO_LANGUAGE[type] ?? fallback;
    counts[code] = (counts[code] ?? 0) + 1;
  }

  const total = Object.values(counts).reduce((s, c) => s + c, 0) || 1;

  const distribution: Record<string, number> = {};
  for (const [code, count] of Object.entries(counts)) {
    distribution[code] = count / total;
  }
  return distribution;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: find node with max betweenness
// ─────────────────────────────────────────────────────────────────────────

function findMaxBetweennessNode(betweennessMap: Record<string, number>): string | null {
  let maxNode: string | null = null;
  let maxScore = -1;
  for (const [id, score] of Object.entries(betweennessMap)) {
    if (score > maxScore) {
      maxScore = score;
      maxNode = id;
    }
  }
  return maxNode;
}

// ─────────────────────────────────────────────────────────────────────────
// HELPER: find root node (gen-0 with highest degree; ties broken by first
// occurrence in the nodes array)
// ─────────────────────────────────────────────────────────────────────────

function findRootNode(
  nodes: GraphNode[],
  generationMap: Record<string, number>,
  adjacency: AdjacencyMap,
): string | null {
  const gen0Nodes = nodes.filter((n) => (generationMap[n.id] ?? 0) === 0);
  if (gen0Nodes.length === 0) return null;
  return gen0Nodes.reduce((best, curr) => {
    const bestDeg = (adjacency[best.id] ?? []).length;
    const currDeg = (adjacency[curr.id] ?? []).length;
    return currDeg > bestDeg ? curr : best;
  }).id;
}

// ─────────────────────────────────────────────────────────────────────────
// MAIN: computeGraphMetrics — pure function, no side effects
// ─────────────────────────────────────────────────────────────────────────

export function computeGraphMetrics(
  nodes: GraphNode[],
  edges: GraphEdge[],
  familyPrimaryLanguage: string = 'en',
): GraphMetrics {
  if (nodes.length === 0) {
    return {
      memberCount: 0,
      edgeCount: 0,
      generationDepth: 1,
      clusteringCoefficient: 0,
      graphDiameter: 0,
      avgDegree: 0,
      maxBetweennessNodeId: null,
      rootNodeId: null,
      distinctLineages: 1,
      betweennessMap: {},
      degreeMap: {},
      generationMap: {},
      languageDistribution: { [familyPrimaryLanguage || 'hi']: 1 },
    };
  }

  const adjacency = buildAdjacency(nodes, edges);
  const generationMap = assignGenerations(nodes, edges);
  const degreeMap = computeDegreeMap(adjacency);

  const clusteringCoefficient = computeClusteringCoefficient(nodes, adjacency);
  const { diameter } = computeAllPairsShortestPaths(nodes, adjacency);
  const betweennessMap = computeBetweennessCentrality(nodes, adjacency);
  const distinctLineages = detectLineages(nodes, edges);
  const languageDistribution = computeLanguageDistribution(edges, familyPrimaryLanguage);

  const maxBetweennessNodeId = findMaxBetweennessNode(betweennessMap);
  const rootNodeId = findRootNode(nodes, generationMap, adjacency);

  const maxGeneration = Math.max(...Object.values(generationMap));
  const avgDegree =
    nodes.length > 0
      ? Object.values(degreeMap).reduce((s, d) => s + d, 0) / nodes.length
      : 0;

  return {
    memberCount: nodes.length,
    edgeCount: edges.length,
    generationDepth: maxGeneration + 1,
    clusteringCoefficient,
    graphDiameter: diameter,
    avgDegree,
    maxBetweennessNodeId,
    rootNodeId,
    distinctLineages,
    betweennessMap,
    degreeMap,
    generationMap,
    languageDistribution,
  };
}
