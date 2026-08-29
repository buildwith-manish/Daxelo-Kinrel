/**
 * Daxelo-Kinrel Graph Engine Service v4.0
 * ══════════════════════════════════════════════════════════════════════
 *
 * COMPLETE REWRITE to match the v4.0 Deterministic Kinship Engine spec.
 *
 * CHANGES FROM v3:
 * - Stores only 4 fundamental edge types: parent, spouse, adoptive_parent, step_parent
 * - NO confidence scores (deterministic only)
 * - NO hardcoded KINSHIP_RULES (all derived at runtime)
 * - Max depth 8 (was 15)
 * - BFS traversal with cycle detection
 * - Returns KinshipSignature (not string terms) — vocabulary mapping is separate
 * - Path canonicalization (cycle removal, backtracking removal)
 * - Double kinship detection
 * - Spouse inference from shared children
 *
 * Architecture:
 *   1. buildAdjacency()    — Load fundamental edges → adjacency list
 *   2. findShortestPath()  — BFS shortest path (depth 8, cycle detection)
 *   3. canonicalizePath()  — Remove cycles, backtracking
 *   4. buildSignature()    — Path → KinshipSignature
 *   5. resolve()           — Full pipeline: path → signature → term
 */

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

// ── Exported Types ────────────────────────────────────────────────────

export type TraversePrimitive =
  | 'UP_PARENT'
  | 'DOWN_CHILD'
  | 'SPOUSE'
  | 'UP_ADOPTIVE_PARENT'
  | 'UP_STEP_PARENT';

export type Consanguinity = 'blood' | 'half' | 'step' | 'adoptive' | 'inLaw' | 'affine';
export type FamilySide = 'paternal' | 'maternal' | 'none';
export type ResolutionStatus = 'confirmed' | 'derived' | 'inferred' | 'ambiguous' | 'incomplete';

export interface KinshipSignature {
  generationDelta: number;
  pathPattern: string;
  side: FamilySide;
  consanguinity: Consanguinity;
  genderAnchor: string;
  seniority: string;
  removal: number;
  doubleKinship: boolean;
  resolutionStatus: ResolutionStatus;
  intermediateSeniority: string;
  spouseSide: FamilySide;
  intermediateGender: string;
}

export interface KinshipResult {
  term: string;
  fundamentalEdge: string | null;
  signature: KinshipSignature;
  isDerived: boolean;
  isSuggested: boolean;
  path: PathStep[];
}

export interface PathStep {
  personId: string;
  personName: string;
  primitive: TraversePrimitive;
  direction?: string;        // v4.0 legacy field - 'up' / 'down' / 'sideways'
  relationshipType?: string; // v4.0 legacy field - original relationshipKey
}

export interface PathResult {
  found: boolean;
  path: PathStep[];
  distance: number;
  kinshipTerm?: string;      // v4.0 legacy — populated by callers that resolve vocabulary
  kinshipTermHindi?: string; // v4.0 legacy — populated by callers that resolve vocabulary
  signature?: KinshipSignature;
  result?: KinshipResult;
}

export interface ComputedRelationship {
  personId: string;
  personName: string;
  relationshipKey: string;
  computedTerm: string;
  computedTermHindi: string;  // v4.0 legacy field — populated by callers (default empty string)
  distance: number;
  path: PathStep[];
  signature: KinshipSignature;
}

// ── Internal Types ────────────────────────────────────────────────────

interface AdjacencyEntry {
  neighborId: string;
  primitive: TraversePrimitive;
}

interface PersonRecord {
  id: string;
  name: string;
  gender?: string | null;
}

interface BfsState {
  nodeId: string;
  path: TraversePrimitive[];
  visited: string[];
}

interface BfsResult {
  path: TraversePrimitive[];
  visitedNodes: string[];
}

// ── Constants ─────────────────────────────────────────────────────────

const MAX_DEPTH = 8;

const FUNDAMENTAL_EDGES = new Set([
  'parent',
  'spouse',
  'adoptive_parent',
  'step_parent',
]);

// v3.0 §13.2 — Adjacency cache TTL (60 seconds)
const ADJACENCY_CACHE_TTL_MS = 60_000;

// v3.0 §3.3 — Deterministic path priority: blood > adoptive > step > inLaw
// Lower number = higher priority (preferred first).
const PRIORITY_BLOOD = 0;
const PRIORITY_ADOPTIVE = 1;
const PRIORITY_STEP = 2;
const PRIORITY_INLAW = 3;

function priorityForPrimitive(p: TraversePrimitive): number {
  switch (p) {
    case 'UP_PARENT':
    case 'DOWN_CHILD':
      return PRIORITY_BLOOD;
    case 'UP_ADOPTIVE_PARENT':
      return PRIORITY_ADOPTIVE;
    case 'UP_STEP_PARENT':
      return PRIORITY_STEP;
    case 'SPOUSE':
      return PRIORITY_INLAW;
    default:
      return PRIORITY_INLAW;
  }
}

function pathPriority(path: TraversePrimitive[]): number {
  // Sum of primitives' priorities — lower is better (blood preferred).
  // For comparison across paths of equal length, this is a stable sort key.
  let sum = 0;
  for (const p of path) sum += priorityForPrimitive(p);
  return sum;
}

// ── Cached Adjacency (per family, TTL 60s) ────────────────────────────

interface CachedAdjacency {
  adjacency: Record<string, AdjacencyEntry[]>;
  persons: PersonRecord[];
  expiresAt: number;
}

// ── Service ───────────────────────────────────────────────────────────

@Injectable()
export class GraphEngineService {
  private readonly logger = new Logger(GraphEngineService.name);

  // v3.0 §13.2 — In-memory adjacency cache, keyed by familyId.
  // TTL = 60s. Invalidated on any relationship mutation via invalidateCache().
  private readonly adjacencyCache = new Map<string, CachedAdjacency>();

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Resolves the kinship between two persons using the deterministic engine.
   * Returns null if:
   * - fromPersonId === toPersonId (self)
   * - No path exists within max depth 8
   */
  async resolveKinship(
    familyId: string,
    fromPersonId: string,
    toPersonId: string,
  ): Promise<KinshipResult | null> {
    if (fromPersonId === toPersonId) return null;

    const { persons, relationships } = await this.loadFamilyGraph(familyId);
    const adjacency = this.buildAdjacencyFromCacheOrFresh(familyId, relationships);

    const bfsResult = this.findShortestPath(fromPersonId, toPersonId, adjacency);
    if (!bfsResult) return null;

    const canonicalPath = this.canonicalizePath(bfsResult.path, bfsResult.visitedNodes);
    if (canonicalPath.length === 0) return null;

    const signature = this.buildSignature(
      canonicalPath,
      bfsResult.visitedNodes,
      fromPersonId,
      toPersonId,
      persons,
      adjacency,
    );

    return this.buildResult(signature, toPersonId, persons);
  }

  /**
   * Finds the shortest path between two persons.
   * Returns the path + visited nodes, or null if no path found.
   */
  async findPath(
    familyId: string,
    fromPersonId: string,
    toPersonId: string,
  ): Promise<PathResult> {
    if (fromPersonId === toPersonId) {
      return { found: false, path: [], distance: 0 };
    }

    const { persons, relationships } = await this.loadFamilyGraph(familyId);
    const adjacency = this.buildAdjacencyFromCacheOrFresh(familyId, relationships);

    const bfsResult = this.findShortestPath(fromPersonId, toPersonId, adjacency);
    if (!bfsResult) {
      return { found: false, path: [], distance: 0 };
    }

    const canonicalPath = this.canonicalizePath(bfsResult.path, bfsResult.visitedNodes);
    const signature = this.buildSignature(
      canonicalPath,
      bfsResult.visitedNodes,
      fromPersonId,
      toPersonId,
      persons,
      adjacency,
    );

    const pathSteps: PathStep[] = canonicalPath.map((primitive, i) => {
      const nodeId = bfsResult.visitedNodes[i + 1] || '';
      const person = persons.find((p) => p.id === nodeId);
      return {
        personId: nodeId,
        personName: person?.name || 'Unknown',
        primitive,
      };
    });

    const result = this.buildResult(signature, toPersonId, persons);

    return {
      found: true,
      path: pathSteps,
      distance: canonicalPath.length,
      signature,
      result,
    };
  }

  /**
   * Gets ALL computed relationships for a person (every reachable person
   * within max depth 8, with their resolved kinship term).
   */
  async getAllRelationships(
    familyId: string,
    personId: string,
  ): Promise<ComputedRelationship[]> {
    const { persons, relationships } = await this.loadFamilyGraph(familyId);
    const adjacency = this.buildAdjacencyFromCacheOrFresh(familyId, relationships);

    const results: ComputedRelationship[] = [];

    for (const person of persons) {
      if (person.id === personId) continue;

      const bfsResult = this.findShortestPath(personId, person.id, adjacency);
      if (!bfsResult) continue;

      const canonicalPath = this.canonicalizePath(bfsResult.path, bfsResult.visitedNodes);
      if (canonicalPath.length === 0) continue;

      const signature = this.buildSignature(
        canonicalPath,
        bfsResult.visitedNodes,
        personId,
        person.id,
        persons,
        adjacency,
      );

      const result = this.buildResult(signature, person.id, persons);

      results.push({
        personId: person.id,
        personName: person.name,
        relationshipKey: result.fundamentalEdge || signature.pathPattern,
        computedTerm: result.term,
        computedTermHindi: '', // v4.0 legacy — populated downstream if needed
        distance: canonicalPath.length,
        path: canonicalPath.map((primitive, i) => ({
          personId: bfsResult.visitedNodes[i + 1] || '',
          personName: persons.find((p) => p.id === bfsResult.visitedNodes[i + 1])?.name || 'Unknown',
          primitive,
        })),
        signature,
      });
    }

    return results;
  }

  /**
   * Gets all ancestors of a person (traversing UP_PARENT edges).
   */
  async getAncestors(familyId: string, personId: string): Promise<PersonRecord[]> {
    const { persons, relationships } = await this.loadFamilyGraph(familyId);
    const adjacency = this.buildAdjacencyFromCacheOrFresh(familyId, relationships);

    const ancestors: PersonRecord[] = [];
    const visited = new Set<string>([personId]);
    const queue = [personId];

    while (queue.length > 0) {
      const current = queue.shift()!;
      const neighbors = adjacency[current] || [];

      for (const n of neighbors) {
        if (n.primitive !== 'UP_PARENT' && n.primitive !== 'UP_ADOPTIVE_PARENT' && n.primitive !== 'UP_STEP_PARENT') continue;
        if (visited.has(n.neighborId)) continue;
        visited.add(n.neighborId);

        const person = persons.find((p) => p.id === n.neighborId);
        if (person) ancestors.push(person);
        queue.push(n.neighborId);
      }
    }

    return ancestors;
  }

  /**
   * Gets all descendants of a person (traversing DOWN_CHILD edges).
   */
  async getDescendants(familyId: string, personId: string): Promise<PersonRecord[]> {
    const { persons, relationships } = await this.loadFamilyGraph(familyId);
    const adjacency = this.buildAdjacencyFromCacheOrFresh(familyId, relationships);

    const descendants: PersonRecord[] = [];
    const visited = new Set<string>([personId]);
    const queue = [personId];

    while (queue.length > 0) {
      const current = queue.shift()!;
      const neighbors = adjacency[current] || [];

      for (const n of neighbors) {
        if (n.primitive !== 'DOWN_CHILD') continue;
        if (visited.has(n.neighborId)) continue;
        visited.add(n.neighborId);

        const person = persons.find((p) => p.id === n.neighborId);
        if (person) descendants.push(person);
        queue.push(n.neighborId);
      }
    }

    return descendants;
  }

  /**
   * v4.0: Suggests a spouse relationship if two persons share at least
   * one child and are NOT already spouses.
   * Returns a KinshipResult with isSuggested=true, or null.
   */
  async suggestSpouseIfSharedChildren(
    familyId: string,
    personAId: string,
    personBId: string,
  ): Promise<KinshipResult | null> {
    if (personAId === personBId) return null;

    const { persons, relationships } = await this.loadFamilyGraph(familyId);

    // Check if already spouses
    for (const rel of relationships) {
      const type = rel.relationshipKey.toLowerCase();
      if (type === 'spouse') {
        if (
          (rel.fromId === personAId && rel.toId === personBId) ||
          (rel.fromId === personBId && rel.toId === personAId)
        ) {
          return null;
        }
      }
    }

    // Find children of personA
    const childrenA = new Set<string>();
    for (const rel of relationships) {
      const type = rel.relationshipKey.toLowerCase();
      if (type === 'parent') {
        if (rel.toId === personAId) childrenA.add(rel.fromId);
        if (rel.fromId === personAId) childrenA.add(rel.toId);
      }
    }

    // Find children of personB
    const childrenB = new Set<string>();
    for (const rel of relationships) {
      const type = rel.relationshipKey.toLowerCase();
      if (type === 'parent') {
        if (rel.toId === personBId) childrenB.add(rel.fromId);
        if (rel.fromId === personBId) childrenB.add(rel.toId);
      }
    }

    // Check for shared children
    const shared = [...childrenA].filter((c) => childrenB.has(c));
    if (shared.length === 0) return null;

    // Suggest spouse!
    const personB = persons.find((p) => p.id === personBId);
    const gender = personB?.gender?.toLowerCase() === 'female' ? 'female' : 'male';

    const signature: KinshipSignature = {
      generationDelta: 0,
      pathPattern: 'SPOUSE',
      side: 'none',
      consanguinity: 'affine',
      genderAnchor: gender,
      seniority: 'none',
      removal: 0,
      doubleKinship: false,
      resolutionStatus: 'inferred',
      intermediateSeniority: 'none',
      spouseSide: 'none',
      intermediateGender: 'none',
    };

    return {
      term: gender === 'female' ? 'Wife' : 'Husband',
      fundamentalEdge: 'spouse',
      signature,
      isDerived: false,
      isSuggested: true,
      path: [],
    };
  }

  // ── Private: Graph Loading ──────────────────────────────────────────

  /**
   * v4.1: Invalidate the in-memory graph cache for a family.
   * v3.0 §13.2: Now actually invalidates the 60-second adjacency cache
   * (previously a no-op). Called by RelationshipsService on every
   * relationship mutation.
   */
  invalidateCache(familyId: string): void {
    if (this.adjacencyCache.has(familyId)) {
      this.adjacencyCache.delete(familyId);
      this.logger.debug(`Adjacency cache invalidated for family ${familyId}`);
    }
  }

  private async loadFamilyGraph(familyId: string): Promise<{
    persons: PersonRecord[];
    relationships: { id: string; fromId: string; toId: string; relationshipKey: string }[];
  }> {
    // v3.0 §13.2 — Try the adjacency cache first.
    const cached = this.adjacencyCache.get(familyId);
    const now = Date.now();
    if (cached && cached.expiresAt > now) {
      // Reconstruct relationships array from cached adjacency? No —
      // callers (buildAdjacency etc.) only need the adjacency + persons.
      // We return the cached structure, but the relationships field
      // is unused downstream once adjacency is built. To keep the
      // contract stable, we return an empty relationships array and
      // rely on the cached adjacency.
      return {
        persons: cached.persons,
        relationships: [],
      };
    }

    const [personRows, relationshipRows] = await Promise.all([
      this.prisma.person.findMany({
        where: { familyId, deletedAt: null },
        select: { id: true, name: true, gender: true },
      }),
      this.prisma.relationship.findMany({
        where: { familyId, isActive: true },
        select: { id: true, fromPersonId: true, toPersonId: true, relationshipKey: true },
      }),
    ]);

    const persons = personRows.map((p) => ({ id: p.id, name: p.name, gender: p.gender }));
    const relationships = relationshipRows.map((r) => ({
      id: r.id,
      fromId: r.fromPersonId,
      toId: r.toPersonId,
      relationshipKey: r.relationshipKey,
    }));

    // Build + cache the adjacency for 60s.
    const adjacency = this.buildAdjacencyFromCacheOrFresh(familyId, relationships);
    this.adjacencyCache.set(familyId, {
      adjacency,
      persons,
      expiresAt: now + ADJACENCY_CACHE_TTL_MS,
    });

    return { persons, relationships };
  }

  /**
   * v3.0 §13.2 — Build adjacency from the cached structure if available.
   * Falls through to the inline buildAdjacency when cache is empty.
   */
  private buildAdjacencyFromCacheOrFresh(
    familyId: string,
    relationships: { fromId: string; toId: string; relationshipKey: string }[],
  ): Record<string, AdjacencyEntry[]> {
    // If the cache is fresh, loadFamilyGraph already returned an empty
    // relationships array; we need to use the cached adjacency directly.
    const cached = this.adjacencyCache.get(familyId);
    if (cached && cached.expiresAt > Date.now() && cached.adjacency) {
      return cached.adjacency;
    }
    return this.buildAdjacency(relationships);
  }

  // ── Private: Adjacency List ─────────────────────────────────────────

  private buildAdjacency(
    relationships: { fromId: string; toId: string; relationshipKey: string }[],
  ): Record<string, AdjacencyEntry[]> {
    const adjacency: Record<string, AdjacencyEntry[]> = {};

    for (const rel of relationships) {
      const type = rel.relationshipKey.toLowerCase();

      let forwardPrim: TraversePrimitive | null = null;
      let reversePrim: TraversePrimitive | null = null;

      switch (type) {
        case 'parent':
        case 'father':
        case 'mother':
          forwardPrim = 'UP_PARENT';
          reversePrim = 'DOWN_CHILD';
          break;
        case 'spouse':
        case 'husband':
        case 'wife':
          forwardPrim = 'SPOUSE';
          reversePrim = 'SPOUSE';
          break;
        case 'adoptive_parent':
        case 'adoptive_father':
        case 'adoptive_mother':
          forwardPrim = 'UP_ADOPTIVE_PARENT';
          reversePrim = 'DOWN_CHILD';
          break;
        case 'step_parent':
        case 'step_father':
        case 'step_mother':
        case 'stepfather':
        case 'stepmother':
          forwardPrim = 'UP_STEP_PARENT';
          reversePrim = 'DOWN_CHILD';
          break;
        case 'child':
        case 'son':
        case 'daughter':
          forwardPrim = 'DOWN_CHILD';
          reversePrim = 'UP_PARENT';
          break;
        default:
          // Skip non-fundamental types
          continue;
      }

      if (!adjacency[rel.fromId]) adjacency[rel.fromId] = [];
      adjacency[rel.fromId].push({ neighborId: rel.toId, primitive: forwardPrim });

      if (!adjacency[rel.toId]) adjacency[rel.toId] = [];
      adjacency[rel.toId].push({ neighborId: rel.fromId, primitive: reversePrim });
    }

    return adjacency;
  }

  // ── Private: BFS ────────────────────────────────────────────────────

  /**
   * v3.0 §3.3 — Find the SHORTEST path between two persons.
   *
   * When multiple shortest paths of equal length exist, applies the
   * deterministic priority: blood > adoptive > step > inLaw.
   *
   * Algorithm: standard BFS to discover the shortest distance, then a
   * second pass to enumerate all shortest paths of that exact length,
   * then pick the one with the lowest path-priority score.
   *
   * Cycle detection is enabled throughout. Max traversal depth = 8.
   */
  private findShortestPath(
    fromId: string,
    toId: string,
    adjacency: Record<string, AdjacencyEntry[]>,
  ): BfsResult | null {
    // Phase 1: standard BFS to find the shortest distance.
    // (We also collect each reachable node's distance from `fromId`.)
    const dist = new Map<string, number>();
    dist.set(fromId, 0);
    const queue: string[] = [fromId];
    let shortestDistance = -1;

    while (queue.length > 0) {
      const current = queue.shift()!;
      const d = dist.get(current) ?? 0;

      if (current === toId && d > 0) {
        shortestDistance = d;
        break;
      }

      if (d >= MAX_DEPTH) continue;

      const neighbors = adjacency[current] || [];
      for (const n of neighbors) {
        if (dist.has(n.neighborId)) continue;
        dist.set(n.neighborId, d + 1);
        queue.push(n.neighborId);
      }
    }

    if (shortestDistance <= 0) return null;

    // Phase 2: DFS-enumerate all paths of length === shortestDistance
    // from `fromId` to `toId`. Cap the enumeration to prevent
    // pathological blow-ups on dense graphs.
    const allPaths: TraversePrimitive[][] = [];
    const allVisited: string[][] = [];
    const MAX_ENUMERATED_PATHS = 64;
    this.enumerateAllShortestPaths(
      fromId,
      toId,
      adjacency,
      dist,
      shortestDistance,
      [],
      [fromId],
      new Set<string>([fromId]),
      allPaths,
      allVisited,
      MAX_ENUMERATED_PATHS,
    );

    if (allPaths.length === 0) {
      // Fallback to single-path BFS if enumeration failed (shouldn't happen,
      // but defensive).
      return this.findShortestPathSimple(fromId, toId, adjacency);
    }

    // Phase 3: pick the path with the lowest priority score.
    // blood (0) > adoptive (1) > step (2) > inLaw (3).
    // Ties broken by lexical ordering of the path pattern for determinism.
    let bestIdx = 0;
    let bestPriority = pathPriority(allPaths[0]);
    let bestPattern = allPaths[0].join('_');
    for (let i = 1; i < allPaths.length; i++) {
      const p = pathPriority(allPaths[i]);
      const pat = allPaths[i].join('_');
      if (
        p < bestPriority ||
        (p === bestPriority && pat < bestPattern)
      ) {
        bestIdx = i;
        bestPriority = p;
        bestPattern = pat;
      }
    }

    return {
      path: allPaths[bestIdx],
      visitedNodes: allVisited[bestIdx],
    };
  }

  /**
   * Enumerate all paths of length === targetDistance from `current` to `target`.
   * Uses distance map from Phase 1 to prune any step that doesn't reduce
   * distance to target by exactly 1 (so we only walk along shortest paths).
   */
  private enumerateAllShortestPaths(
    current: string,
    target: string,
    adjacency: Record<string, AdjacencyEntry[]>,
    dist: Map<string, number>,
    targetDistance: number,
    pathSoFar: TraversePrimitive[],
    visitedSoFar: string[],
    visitedSet: Set<string>,
    outPaths: TraversePrimitive[][],
    outVisited: string[][],
    cap: number,
  ): void {
    if (outPaths.length >= cap) return;

    if (pathSoFar.length === targetDistance) {
      if (current === target) {
        outPaths.push([...pathSoFar]);
        outVisited.push([...visitedSoFar]);
      }
      return;
    }

    if (pathSoFar.length > targetDistance) return;

    const neighbors = adjacency[current] || [];
    for (const n of neighbors) {
      if (visitedSet.has(n.neighborId)) continue;

      // v3.0 §3.2 — Only follow edges that lead to nodes which are
      // exactly one step closer to the target (per the BFS distance map).
      // This prunes any detour and keeps enumeration bounded.
      const expectedDist = (dist.get(current) ?? 0) + 1;
      const neighborDist = dist.get(n.neighborId) ?? Infinity;
      if (neighborDist !== expectedDist) continue;

      // Also require: neighbor must be on a path that can still reach target
      // within the remaining distance budget. Since BFS distance is the
      // shortest from `fromId`, and target distance is `targetDistance`,
      // the only valid neighbors are those whose dist === expectedDist.
      visitedSet.add(n.neighborId);
      pathSoFar.push(n.primitive);
      visitedSoFar.push(n.neighborId);

      this.enumerateAllShortestPaths(
        n.neighborId,
        target,
        adjacency,
        dist,
        targetDistance,
        pathSoFar,
        visitedSoFar,
        visitedSet,
        outPaths,
        outVisited,
        cap,
      );

      pathSoFar.pop();
      visitedSoFar.pop();
      visitedSet.delete(n.neighborId);
    }
  }

  /**
   * Fallback single-path BFS — used when path enumeration fails for
   * some reason. Identical to the pre-v3.0 algorithm.
   */
  private findShortestPathSimple(
    fromId: string,
    toId: string,
    adjacency: Record<string, AdjacencyEntry[]>,
  ): BfsResult | null {
    const queue: BfsState[] = [{ nodeId: fromId, path: [], visited: [fromId] }];
    const visited = new Set<string>([fromId]);

    while (queue.length > 0) {
      const current = queue.shift()!;

      if (current.nodeId === toId && current.path.length > 0) {
        return { path: current.path, visitedNodes: current.visited };
      }

      if (current.path.length >= MAX_DEPTH) continue;

      const neighbors = adjacency[current.nodeId] || [];
      for (const n of neighbors) {
        if (visited.has(n.neighborId)) continue;
        visited.add(n.neighborId);
        queue.push({
          nodeId: n.neighborId,
          path: [...current.path, n.primitive],
          visited: [...current.visited, n.neighborId],
        });
      }
    }

    return null;
  }

  // ── Private: Path Canonicalization ──────────────────────────────────

  private canonicalizePath(
    path: TraversePrimitive[],
    visitedNodes: string[],
  ): TraversePrimitive[] {
    if (path.length < 2) return path;

    // Remove backtracking: UP_PARENT + DOWN_CHILD cancels, etc.
    const result: TraversePrimitive[] = [];
    for (const prim of path) {
      if (result.length > 0) {
        const prev = result[result.length - 1];
        if (
          (prev === 'UP_PARENT' && prim === 'DOWN_CHILD') ||
          (prev === 'DOWN_CHILD' && prim === 'UP_PARENT') ||
          (prev === 'SPOUSE' && prim === 'SPOUSE')
        ) {
          result.pop();
          continue;
        }
      }
      result.push(prim);
    }

    return result;
  }

  // ── Private: Signature Builder ──────────────────────────────────────

  private buildSignature(
    path: TraversePrimitive[],
    visitedNodes: string[],
    fromPersonId: string,
    toPersonId: string,
    persons: PersonRecord[],
    adjacency: Record<string, AdjacencyEntry[]>,
  ): KinshipSignature {
    let upCount = 0;
    let downCount = 0;

    for (const p of path) {
      if (p === 'UP_PARENT' || p === 'UP_ADOPTIVE_PARENT' || p === 'UP_STEP_PARENT') upCount++;
      else if (p === 'DOWN_CHILD') downCount++;
    }

    const generationDelta = downCount - upCount;
    const pathPattern = path.join('_');

    // Side detection using visitedNodes
    const side = this.detectSide(path, visitedNodes, persons);

    // Consanguinity
    const consanguinity = this.detectConsanguinity(path, fromPersonId, toPersonId, adjacency);

    // Gender
    const target = persons.find((p) => p.id === toPersonId);
    const genderAnchor = target?.gender?.toLowerCase() === 'female' ? 'female' : 'male';

    // Removal (cousins only)
    let removal = 0;
    if (upCount >= 2 && downCount >= 2) {
      removal = Math.abs(upCount - downCount);
    }

    // Double kinship
    const doubleKinship = this.detectDoubleKinship(fromPersonId, toPersonId, path.length, adjacency);

    // Resolution status
    const isFundamental =
      pathPattern === 'UP_PARENT' ||
      pathPattern === 'DOWN_CHILD' ||
      pathPattern === 'SPOUSE' ||
      pathPattern === 'UP_ADOPTIVE_PARENT' ||
      pathPattern === 'UP_STEP_PARENT';

    const resolutionStatus: ResolutionStatus = isFundamental ? 'confirmed' : 'derived';

    return {
      generationDelta,
      pathPattern,
      side,
      consanguinity,
      genderAnchor,
      seniority: 'none',
      removal,
      doubleKinship,
      resolutionStatus,
      intermediateSeniority: 'none',
      spouseSide: 'none',
      intermediateGender: 'none',
    };
  }

  private detectSide(
    path: TraversePrimitive[],
    visitedNodes: string[],
    persons: PersonRecord[],
  ): FamilySide {
    if (path.length === 0) return 'none';
    if (path[0] === 'SPOUSE') return 'none';

    for (let i = 0; i < path.length; i++) {
      const prim = path[i];
      if (prim === 'UP_PARENT' || prim === 'UP_ADOPTIVE_PARENT' || prim === 'UP_STEP_PARENT') {
        if (i + 1 < visitedNodes.length) {
          const parentId = visitedNodes[i + 1];
          const parent = persons.find((p) => p.id === parentId);
          return parent?.gender?.toLowerCase() === 'female' ? 'maternal' : 'paternal';
        }
        break;
      }
    }

    return 'none';
  }

  private detectConsanguinity(
    path: TraversePrimitive[],
    fromPersonId: string,
    toPersonId: string,
    adjacency: Record<string, AdjacencyEntry[]>,
  ): Consanguinity {
    if (path.length > 0 && path[0] === 'SPOUSE') {
      if (path.length === 1) return 'affine';
      return 'inLaw';
    }

    if (path.some((p) => p === 'UP_STEP_PARENT')) return 'step';
    if (path.some((p) => p === 'UP_ADOPTIVE_PARENT')) return 'adoptive';

    // Sibling consanguinity
    if (
      path.length === 2 &&
      path[0] === 'UP_PARENT' &&
      path[1] === 'DOWN_CHILD'
    ) {
      const parentsOfA = this.getParents(fromPersonId, adjacency);
      const parentsOfB = this.getParents(toPersonId, adjacency);
      const shared = [...parentsOfA].filter((p) => parentsOfB.has(p));

      if (shared.length >= 2) return 'blood';
      if (shared.length === 1) return 'half';
      return 'step';
    }

    return 'blood';
  }

  private getParents(
    personId: string,
    adjacency: Record<string, AdjacencyEntry[]>,
  ): Set<string> {
    const parents = new Set<string>();
    const neighbors = adjacency[personId] || [];
    for (const n of neighbors) {
      if (n.primitive === 'UP_PARENT' || n.primitive === 'UP_ADOPTIVE_PARENT' || n.primitive === 'UP_STEP_PARENT') {
        parents.add(n.neighborId);
      }
    }
    return parents;
  }

  private detectDoubleKinship(
    fromId: string,
    toId: string,
    pathLength: number,
    adjacency: Record<string, AdjacencyEntry[]>,
  ): boolean {
    if (pathLength === 0) return false;

    const pathsFound: TraversePrimitive[][] = [];
    this.findAllPathsOfLength(
      fromId,
      toId,
      adjacency,
      pathLength,
      [],
      new Set([fromId]),
      pathsFound,
    );

    return pathsFound.length >= 2;
  }

  private findAllPathsOfLength(
    currentId: string,
    targetId: string,
    adjacency: Record<string, AdjacencyEntry[]>,
    targetLength: number,
    currentPath: TraversePrimitive[],
    visited: Set<string>,
    results: TraversePrimitive[][],
  ): void {
    if (currentPath.length === targetLength) {
      if (currentId === targetId) {
        results.push([...currentPath]);
      }
      return;
    }

    if (currentPath.length > targetLength) return;

    const neighbors = adjacency[currentId] || [];
    for (const n of neighbors) {
      if (visited.has(n.neighborId)) continue;
      visited.add(n.neighborId);
      currentPath.push(n.primitive);
      this.findAllPathsOfLength(
        n.neighborId,
        targetId,
        adjacency,
        targetLength,
        currentPath,
        visited,
        results,
      );
      currentPath.pop();
      visited.delete(n.neighborId);
    }
  }

  // ── Private: Result Builder ─────────────────────────────────────────

  private buildResult(
    signature: KinshipSignature,
    toPersonId: string,
    persons: PersonRecord[],
  ): KinshipResult {
    const term = this.resolveTerm(signature);

    const isFundamental =
      signature.pathPattern === 'UP_PARENT' ||
      signature.pathPattern === 'DOWN_CHILD' ||
      signature.pathPattern === 'SPOUSE' ||
      signature.pathPattern === 'UP_ADOPTIVE_PARENT' ||
      signature.pathPattern === 'UP_STEP_PARENT';

    let fundamentalEdge: string | null = null;
    if (isFundamental) {
      if (signature.pathPattern === 'UP_PARENT' || signature.pathPattern === 'DOWN_CHILD') {
        fundamentalEdge = 'parent';
      } else if (signature.pathPattern === 'SPOUSE') {
        fundamentalEdge = 'spouse';
      } else if (signature.pathPattern === 'UP_ADOPTIVE_PARENT') {
        fundamentalEdge = 'adoptive_parent';
      } else if (signature.pathPattern === 'UP_STEP_PARENT') {
        fundamentalEdge = 'step_parent';
      }
    }

    return {
      term,
      fundamentalEdge,
      signature,
      isDerived: !isFundamental,
      isSuggested: false,
      path: [],
    };
  }

  /**
   * Maps a KinshipSignature to a human-readable term.
   * This is a minimal local mapper — the full 5,396+ term vocabulary
   * is served via the /kinship/resolve API endpoint.
   */
  private resolveTerm(signature: KinshipSignature): string {
    const { pathPattern, generationDelta, side, consanguinity, genderAnchor, seniority, removal, doubleKinship } = signature;
    const isFemale = genderAnchor === 'female';

    // Parent
    if (pathPattern === 'UP_PARENT' && generationDelta === -1) {
      if (consanguinity === 'adoptive') return isFemale ? 'Adoptive Mother' : 'Adoptive Father';
      if (consanguinity === 'step') return isFemale ? 'Step Mother' : 'Step Father';
      return isFemale ? 'Mother' : 'Father';
    }

    // Grandparent
    if (pathPattern === 'UP_PARENT_UP_PARENT' && generationDelta === -2) {
      if (side === 'paternal') return isFemale ? 'Grandmother (Paternal)' : 'Grandfather (Paternal)';
      return isFemale ? 'Grandmother (Maternal)' : 'Grandfather (Maternal)';
    }

    // Great grandparent
    if (pathPattern === 'UP_PARENT_UP_PARENT_UP_PARENT' && generationDelta === -3) {
      return isFemale ? 'Great Grandmother' : 'Great Grandfather';
    }

    // Child
    if (pathPattern === 'DOWN_CHILD' && generationDelta === 1) {
      return isFemale ? 'Daughter' : 'Son';
    }

    // Grandchild
    if (pathPattern === 'DOWN_CHILD_DOWN_CHILD' && generationDelta === 2) {
      return isFemale ? 'Granddaughter' : 'Grandson';
    }

    // Great grandchild
    if (pathPattern === 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD' && generationDelta === 3) {
      return isFemale ? 'Great Granddaughter' : 'Great Grandson';
    }

    // Siblings
    if (pathPattern === 'UP_PARENT_DOWN_CHILD' && generationDelta === 0) {
      const label = isFemale ? 'Sister' : 'Brother';
      switch (consanguinity) {
        case 'blood':
          if (seniority === 'elder') return `Elder ${label}`;
          if (seniority === 'younger') return `Younger ${label}`;
          return label;
        case 'half':
          return `Half ${label}`;
        case 'step':
          return `Step ${label}`;
        case 'adoptive':
          return `Adoptive ${label}`;
        default:
          return label;
      }
    }

    // Uncle/Aunt
    if (pathPattern === 'UP_PARENT_UP_PARENT_DOWN_CHILD' && generationDelta === -1) {
      if (side === 'paternal') return isFemale ? 'Aunt (Paternal)' : 'Uncle (Paternal)';
      return isFemale ? 'Aunt (Maternal)' : 'Uncle (Maternal)';
    }

    // Great uncle/aunt
    if (pathPattern === 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD' && generationDelta === -2) {
      return isFemale ? 'Great Aunt' : 'Great Uncle';
    }

    // Nephew/Niece
    if (pathPattern === 'UP_PARENT_DOWN_CHILD_DOWN_CHILD' && generationDelta === 1) {
      return isFemale ? 'Niece' : 'Nephew';
    }

    // First cousin
    if (pathPattern === 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD' && generationDelta === 0) {
      if (doubleKinship) return 'Double Cousin';
      return 'Cousin';
    }

    // Cousin removed
    if (
      pathPattern === 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD' ||
      pathPattern === 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD'
    ) {
      if (removal === 1) return 'Cousin (Once Removed)';
      if (removal === 2) return 'Cousin (Twice Removed)';
      return 'Cousin';
    }

    // Second cousin
    if (
      pathPattern === 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD' &&
      generationDelta === 0
    ) {
      return 'Second Cousin';
    }

    // In-laws
    if (pathPattern === 'SPOUSE_UP_PARENT' && generationDelta === -1) {
      return isFemale ? 'Mother-in-Law' : 'Father-in-Law';
    }

    if (pathPattern === 'SPOUSE_UP_PARENT_UP_PARENT' && generationDelta === -2) {
      return isFemale ? 'Grandmother-in-Law' : 'Grandfather-in-Law';
    }

    if (pathPattern === 'SPOUSE_UP_PARENT_DOWN_CHILD' && generationDelta === 0) {
      return isFemale ? 'Sister-in-Law' : 'Brother-in-Law';
    }

    if (pathPattern === 'SPOUSE_DOWN_CHILD' && generationDelta === 1) {
      return isFemale ? 'Daughter-in-Law' : 'Son-in-Law';
    }

    // Spouse
    if (pathPattern === 'SPOUSE' && generationDelta === 0) {
      return isFemale ? 'Wife' : 'Husband';
    }

    // Step parents
    if (pathPattern === 'UP_STEP_PARENT' && generationDelta === -1) {
      return isFemale ? 'Step Mother' : 'Step Father';
    }

    // Adoptive parents
    if (pathPattern === 'UP_ADOPTIVE_PARENT' && generationDelta === -1) {
      return isFemale ? 'Adoptive Mother' : 'Adoptive Father';
    }

    // Fallback: compose descriptive term
    const parts: string[] = [];
    if (consanguinity === 'half') parts.push('Half');
    if (consanguinity === 'step') parts.push('Step');
    if (consanguinity === 'adoptive') parts.push('Adoptive');
    if (consanguinity === 'inLaw') parts.push('In-Law');
    if (generationDelta < -2) parts.push('Great');
    if (generationDelta === -2) parts.push('Grand');
    if (generationDelta < 0) parts.push(isFemale ? 'Mother' : 'Father');
    else if (generationDelta > 2) { parts.push('Great'); parts.push(isFemale ? 'Granddaughter' : 'Grandson'); }
    else if (generationDelta === 2) parts.push(isFemale ? 'Granddaughter' : 'Grandson');
    else if (generationDelta === 1) parts.push(isFemale ? 'Daughter' : 'Son');
    else parts.push('Relative');

    return parts.join(' ');
  }
}
