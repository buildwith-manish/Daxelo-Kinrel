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
}

export interface PathResult {
  found: boolean;
  path: PathStep[];
  distance: number;
  signature?: KinshipSignature;
  result?: KinshipResult;
}

export interface ComputedRelationship {
  personId: string;
  personName: string;
  relationshipKey: string;
  computedTerm: string;
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

// ── Service ───────────────────────────────────────────────────────────

@Injectable()
export class GraphEngineService {
  private readonly logger = new Logger(GraphEngineService.name);

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
    const adjacency = this.buildAdjacency(relationships);

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
    const adjacency = this.buildAdjacency(relationships);

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
    const adjacency = this.buildAdjacency(relationships);

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
    const adjacency = this.buildAdjacency(relationships);

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
    const adjacency = this.buildAdjacency(relationships);

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

  private async loadFamilyGraph(familyId: string): Promise<{
    persons: PersonRecord[];
    relationships: { id: string; fromId: string; toId: string; relationshipKey: string }[];
  }> {
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

    return {
      persons: personRows.map((p) => ({ id: p.id, name: p.name, gender: p.gender })),
      relationships: relationshipRows.map((r) => ({
        id: r.id,
        fromId: r.fromPersonId,
        toId: r.toPersonId,
        relationshipKey: r.relationshipKey,
      })),
    };
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

  private findShortestPath(
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
