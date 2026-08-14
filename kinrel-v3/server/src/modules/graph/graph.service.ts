/**
 * Daxelo-Kinrel — Graph Service: Tree building & enriched graph (spec §18)
 * ========================================================================
 * Builds the enriched tree structure for UI rendering.
 * Caches adjacency for 60s (spec §13.2).
 */

import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service";
import { GraphEngineService } from "../graph/graph-engine.service";
import { KinshipService } from "../kinship/kinship.service";
import { signatureKey } from "../kinship/kinship-signature";

export interface TreeNode {
  person: {
    id: string;
    fullName: string;
    gender: "MALE" | "FEMALE" | "OTHER";
    birthDate: Date | null;
    deathDate: Date | null;
  };
  parents: TreeNode[];
  children: TreeNode[];
  spouses: { personId: string; fullName: string; isInferred: boolean }[];
  // Lazy: kinship label relative to the root user (computed only for visible nodes)
  kinshipLabel?: string;
}

@Injectable()
export class GraphService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly graphEngine: GraphEngineService,
    private readonly kinship: KinshipService,
  ) {}

  /**
   * Build the enriched family tree rooted at `rootPersonId`.
   * Renders up to 4 generations up + 4 generations down by default.
   */
  async buildTree(
    familyId: string,
    rootPersonId: string,
    locale: string = "en",
    options: { upDepth?: number; downDepth?: number } = {},
  ): Promise<TreeNode> {
    const upDepth = options.upDepth ?? 4;
    const downDepth = options.downDepth ?? 4;
    const nodes = await this.graphEngine.loadNodes(familyId);
    const edges = await this.graphEngine.loadEdges(familyId);

    const root = nodes.get(rootPersonId);
    if (!root) throw new Error("Root person not found");

    const personRow = await this.prisma.person.findUnique({ where: { id: rootPersonId } });
    if (!personRow) throw new Error("Root person not found");

    // Build adjacency maps
    const parentsOf = new Map<string, string[]>();
    const childrenOf = new Map<string, string[]>();
    const spousesOf = new Map<string, { id: string; isInferred: boolean }[]>();
    for (const e of edges) {
      if (e.edgeType === "PARENT") {
        if (!parentsOf.has(e.personAId)) parentsOf.set(e.personAId, []);
        parentsOf.get(e.personAId)!.push(e.personBId);
        if (!childrenOf.has(e.personBId)) childrenOf.set(e.personBId, []);
        childrenOf.get(e.personBId)!.push(e.personAId);
      } else if (e.edgeType === "SPOUSE") {
        if (!spousesOf.has(e.personAId)) spousesOf.set(e.personAId, []);
        if (!spousesOf.has(e.personBId)) spousesOf.set(e.personBId, []);
        spousesOf.get(e.personAId)!.push({ id: e.personBId, isInferred: e.isInferred });
        spousesOf.get(e.personBId)!.push({ id: e.personAId, isInferred: e.isInferred });
      }
    }

    const visited = new Set<string>();
    const personCache = new Map<string, any>();

    const loadPerson = async (id: string) => {
      if (personCache.has(id)) return personCache.get(id);
      const p = await this.prisma.person.findUnique({ where: { id } });
      if (p) personCache.set(id, p);
      return p;
    };

    const buildNode = async (personId: string, depth: number, direction: "up" | "down" | "root"): Promise<TreeNode> => {
      if (visited.has(personId)) {
        // Already in tree — return a stub to avoid duplication
        const p = await loadPerson(personId);
        return {
          person: { id: p.id, fullName: p.fullName, gender: p.gender, birthDate: p.birthDate, deathDate: p.deathDate },
          parents: [], children: [], spouses: [],
        };
      }
      visited.add(personId);
      const p = await loadPerson(personId);
      const node: TreeNode = {
        person: { id: p.id, fullName: p.fullName, gender: p.gender, birthDate: p.birthDate, deathDate: p.deathDate },
        parents: [], children: [], spouses: [],
      };

      // Compute kinship label relative to root
      if (personId !== rootPersonId) {
        try {
          const sig = await this.graphEngine.resolveSignature(familyId, rootPersonId, personId);
          if (sig) {
            const lookup = await this.kinship.resolveTerm(sig.signature, locale);
            node.kinshipLabel = lookup.localizedTerm;
          }
        } catch { /* leave undefined */ }
      }

      // Recurse up
      if (direction !== "down" && depth < upDepth) {
        for (const parentId of parentsOf.get(personId) ?? []) {
          node.parents.push(await buildNode(parentId, depth + 1, "up"));
        }
      }
      // Recurse down
      if (direction !== "up" && depth < downDepth) {
        for (const childId of childrenOf.get(personId) ?? []) {
          node.children.push(await buildNode(childId, depth + 1, "down"));
        }
      }
      // Spouses (one level)
      for (const sp of spousesOf.get(personId) ?? []) {
        const spP = await loadPerson(sp.id);
        if (spP) {
          node.spouses.push({
            personId: sp.id,
            fullName: spP.fullName,
            isInferred: sp.isInferred,
          });
        }
      }
      return node;
    };

    return buildNode(rootPersonId, 0, "root");
  }
}
