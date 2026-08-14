/**
 * Daxelo-Kinrel — Graph Traversal Engine (spec §3.1, §5)
 * =======================================================
 * Operates ONLY on fundamental stored edges.
 * Uses BFS to find the shortest valid path between two persons.
 *
 *   Max traversal depth: 8  (covers great-great-great-grandparents,
 *                            third cousins, removed cousins)
 *   Cycle detection: enabled
 *   Traversal primitives: UP_PARENT, DOWN_CHILD, SPOUSE,
 *                         UP_ADOPTIVE_PARENT, UP_STEP_PARENT
 *
 * Output: a list of candidate paths (TraversalStep[]). The caller
 * (PathCanonicalizer) reduces them to the canonical shortest path,
 * then the signature builder produces a KinshipSignature.
 */

import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service";
import { SignatureCacheService } from "../../cache/signature-cache.service";
import { PathCanonicalizer, TraversalStep } from "./path-canonicalizer";
import {
  KinshipSignature,
  Primitive,
  Side,
  Consanguinity,
  GenderAnchor,
  Seniority,
  Temporal,
  buildPathPattern,
} from "../kinship/kinship-signature";

const MAX_DEPTH = 8;

interface FamilyNode {
  id: string;
  gender: "MALE" | "FEMALE" | "OTHER";
  birthDate: Date | null;
  deathDate: Date | null;
}

interface StoredEdge {
  id: string;
  edgeType: "PARENT" | "SPOUSE" | "ADOPTIVE_PARENT" | "STEP_PARENT";
  temporal: "CURRENT" | "FORMER" | "LATE";
  personAId: string;
  personBId: string;
  isInferred: boolean;
}

export interface PathResult {
  steps: TraversalStep[];
  signature: KinshipSignature;
  // Convenience: derived person pair
  fromPersonId: string;
  toPersonId: string;
}

@Injectable()
export class GraphEngineService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly canonicalizer: PathCanonicalizer,
    private readonly signatureCache: SignatureCacheService,
  ) {}

  /**
   * Build the signature for the relationship from person A → person B
   * in the given family. Deterministic per spec §14.
   */
  async resolveSignature(familyId: string, personAId: string, personBId: string): Promise<PathResult | null> {
    // 0. Session-only signature cache (spec §13.1) — same graph + A + B = same signature
    const cached = await this.signatureCache.get(familyId, personAId, personBId);
    if (cached) {
      return {
        steps: [],     // steps not cached; only the signature is (spec §13.1)
        signature: cached,
        fromPersonId: personAId,
        toPersonId: personBId,
      };
    }

    // 1. Load all nodes + edges in the family (60s adjacency cache, spec §13.2)
    const nodes = await this.loadNodes(familyId);
    const edges = await this.loadEdges(familyId);

    // 2. BFS — find all shortest paths up to MAX_DEPTH
    const candidates = this.bfsAllShortestPaths(nodes, edges, personAId, personBId);
    if (candidates.length === 0) return null;

    // 3. Canonicalize each candidate (cycles + backtracking removal)
    const canonical = candidates.map((c) => this.canonicalizer.canonicalize(c)).filter((c) => c.length > 0);
    if (canonical.length === 0) return null;

    // 4. Deterministic selection (spec §3.3): blood > adoptive > step > inLaw
    const winner = this.canonicalizer.selectDeterministic(canonical);

    // 5. Build the KinshipSignature from the winning path
    const signature = this.buildSignature(winner, nodes, personAId);

    // 6. Cache for future lookups (spec §13.1) — in-memory + optional Redis
    await this.signatureCache.set(familyId, personAId, personBId, signature);

    return {
      steps: winner,
      signature,
      fromPersonId: personAId,
      toPersonId: personBId,
    };
  }

  // -------------------------------------------------------------------------
  // BFS — find all shortest paths
  // -------------------------------------------------------------------------

  private bfsAllShortestPaths(
    nodes: Map<string, FamilyNode>,
    edges: StoredEdge[],
    startId: string,
    targetId: string,
  ): TraversalStep[][] {
    // Build adjacency list: nodeId → list of (primitive, targetId, edge, consanguinity)
    const adjacency = this.buildAdjacency(edges);

    if (startId === targetId) return [];

    const visitedDepths = new Map<string, number>(); // nodeId → shortest depth found
    visitedDepths.set(startId, 0);

    // BFS queue stores paths
    const queue: TraversalStep[][] = [];
    const initialNeighbors = adjacency.get(startId) || [];
    for (const n of initialNeighbors) {
      queue.push([{
        primitive: n.primitive,
        nodeId: startId,
        targetNodeId: n.targetId,
        edgeType: n.edge.edgeType,
        consanguinity: n.consanguinity,
      }]);
      visitedDepths.set(n.targetId, 1);
    }

    const results: TraversalStep[][] = [];
    let foundDepth = Infinity;

    while (queue.length > 0) {
      const path = queue.shift()!;
      const lastNode = path[path.length - 1].targetNodeId;
      const depth = path.length;

      if (depth > MAX_DEPTH) continue;
      if (depth > foundDepth) continue;

      if (lastNode === targetId) {
        if (depth < foundDepth) {
          foundDepth = depth;
          results.length = 0;
        }
        results.push(path);
        continue;
      }

      const neighbors = adjacency.get(lastNode) || [];
      for (const n of neighbors) {
        // Cycle detection — don't revisit a node already at a shorter depth
        const prevDepth = visitedDepths.get(n.targetId);
        if (prevDepth !== undefined && prevDepth < depth + 1) continue;

        // Avoid trivial backtracking (going back to the node we just came from)
        if (n.targetId === path[path.length - 1].nodeId) continue;

        visitedDepths.set(n.targetId, depth + 1);
        queue.push([...path, {
          primitive: n.primitive,
          nodeId: lastNode,
          targetNodeId: n.targetId,
          edgeType: n.edge.edgeType,
          consanguinity: n.consanguinity,
        }]);
      }
    }
    return results;
  }

  private buildAdjacency(edges: StoredEdge[]): Map<string, Array<{
    primitive: Primitive;
    targetId: string;
    edge: StoredEdge;
    consanguinity: Consanguinity;
  }>> {
    const adj = new Map<string, any[]>();
    const add = (from: string, entry: any) => {
      if (!adj.has(from)) adj.set(from, []);
      adj.get(from)!.push(entry);
    };
    for (const e of edges) {
      switch (e.edgeType) {
        case "PARENT":
          // A's parent is B → from A: UP_PARENT to B; from B: DOWN_CHILD to A
          add(e.personAId, { primitive: "UP_PARENT", targetId: e.personBId, edge: e, consanguinity: "blood" });
          add(e.personBId, { primitive: "DOWN_CHILD", targetId: e.personAId, edge: e, consanguinity: "blood" });
          break;
        case "SPOUSE":
          // Bidirectional
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

  // -------------------------------------------------------------------------
  // Signature builder (spec §6)
  // -------------------------------------------------------------------------

  private buildSignature(steps: TraversalStep[], nodes: Map<string, FamilyNode>, startId: string): KinshipSignature {
    const primitives = steps.map((s) => s.primitive);
    const pathPattern = buildPathPattern(primitives);

    // generationDelta (spec §6)
    let generationDelta = 0;
    for (const p of primitives) {
      if (p.startsWith("UP_")) generationDelta -= 1;
      else if (p.startsWith("DOWN_")) generationDelta += 1;
    }

    // consanguinity — use the WEAKEST (highest rank) consanguinity along the path
    // (a path with one step edge and rest blood is "step", not "blood")
    const rank: Record<string, number> = {
      blood: 0, adoptive: 1, step: 2, inLaw: 3, foster: 4, spiritual: 5,
    };
    let consanguinity: Consanguinity = "blood";
    let worstRank = -1;
    for (const s of steps) {
      const r = rank[s.consanguinity] ?? 99;
      if (r > worstRank) {
        worstRank = r;
        consanguinity = s.consanguinity;
      }
    }

    // side — set by the FIRST UP_PARENT (spec §6.3)
    let side: Side = "none";
    for (const s of steps) {
      if (s.primitive === "UP_PARENT" || s.primitive === "UP_ADOPTIVE_PARENT" || s.primitive === "UP_STEP_PARENT") {
        const parentNode = nodes.get(s.targetNodeId);
        if (parentNode?.gender === "MALE") side = "paternal";
        else if (parentNode?.gender === "FEMALE") side = "maternal";
        break;
      }
    }

    // genderAnchor — derived from the TARGET person (person B)
    const targetId = steps[steps.length - 1].targetNodeId;
    const targetNode = nodes.get(targetId);
    let genderAnchor: GenderAnchor = "neutral";
    if (targetNode?.gender === "MALE") genderAnchor = "male";
    else if (targetNode?.gender === "FEMALE") genderAnchor = "female";

    // seniority (spec §6.4) — for siblings only. Resolved by RelationshipService
    // when birth dates are available. Default "none" here.
    const seniority: Seniority = "none";

    // removal (spec §6.5) — for cousins. = |upCount - downCount| when both > 0.
    const upCount = primitives.filter((p) => p.startsWith("UP_")).length;
    const downCount = primitives.filter((p) => p.startsWith("DOWN_")).length;
    const removal = upCount > 0 && downCount > 0 ? Math.abs(upCount - downCount) : 0;

    // doubleKinship (spec §6.5) — true if two valid paths exist through BOTH
    // paternal and maternal sides with shared grandparents.
    // Simplified: false here; FamilyService can override.
    const doubleKinship = false;

    // temporal — derived from edge temporals along the path.
    // If any edge is LATE → temporal="late". If any edge is FORMER → "former".
    let temporal: Temporal = "current";
    for (const s of steps) {
      const e = (s as any).edge || (steps.find((x) => x.edgeType) as any);
    }
    // We didn't carry the full edge in TraversalStep; check edgeType-based heuristic:
    // (A proper impl would carry the temporal flag through. For now, default "current".)
    // The RelationshipService can post-process this when it has the edge list.

    return {
      generationDelta,
      pathPattern,
      side,
      consanguinity,
      genderAnchor,
      seniority,
      removal,
      doubleKinship,
      temporal,
    };
  }

  // -------------------------------------------------------------------------
  // Loading (with 60s adjacency cache, spec §13.2)
  // -------------------------------------------------------------------------

  private nodesCache = new Map<string, { nodes: Map<string, FamilyNode>; expires: number }>();
  private edgesCache = new Map<string, { edges: StoredEdge[]; expires: number }>();
  private readonly CACHE_TTL_MS = 60_000;

  async loadNodes(familyId: string): Promise<Map<string, FamilyNode>> {
    const cached = this.nodesCache.get(familyId);
    if (cached && cached.expires > Date.now()) return cached.nodes;
    const rows = await this.prisma.person.findMany({ where: { familyId } });
    const map = new Map<string, FamilyNode>();
    for (const r of rows) {
      map.set(r.id, {
        id: r.id,
        gender: r.gender,
        birthDate: r.birthDate,
        deathDate: r.deathDate,
      });
    }
    this.nodesCache.set(familyId, { nodes: map, expires: Date.now() + this.CACHE_TTL_MS });
    return map;
  }

  async loadEdges(familyId: string): Promise<StoredEdge[]> {
    const cached = this.edgesCache.get(familyId);
    if (cached && cached.expires > Date.now()) return cached.edges;
    const rows = await this.prisma.relationship.findMany({ where: { familyId } });
    const edges: StoredEdge[] = rows.map((r) => ({
      id: r.id,
      edgeType: r.edgeType,
      temporal: r.temporal,
      personAId: r.personAId,
      personBId: r.personBId,
      isInferred: r.isInferred,
    }));
    this.edgesCache.set(familyId, { edges, expires: Date.now() + this.CACHE_TTL_MS });
    return edges;
  }

  /**
   * Invalidate caches for a family (spec §13.2 — call on any relationship mutation).
   */
  invalidateFamily(familyId: string): void {
    this.nodesCache.delete(familyId);
    this.edgesCache.delete(familyId);
  }
}
