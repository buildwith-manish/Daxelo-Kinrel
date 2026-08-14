/**
 * Daxelo-Kinrel — Family Service (orchestration layer, spec §18)
 * ===============================================================
 * Top-level orchestrator. Ties together:
 *   - RelationshipsService (CRUD + normalizer)
 *   - GraphEngineService (BFS + signature)
 *   - KinshipService (vocabulary lookup)
 *   - GraphService (tree building for UI)
 *   - Spouse inference (spec §9)
 *
 * Public API used by controllers:
 *   - createRelationship()
 *   - detectRelationship()
 *   - getTree()
 *   - inferSpouse()        (spec §9)
 *   - resolveKinshipLabel()
 */

import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service";
import { RelationshipsService, CreateRelationshipInput } from "../relationships/relationships.service";
import { GraphEngineService } from "../graph/graph-engine.service";
import { GraphService, TreeNode } from "../graph/graph.service";
import { KinshipService } from "../kinship/kinship.service";
import { signatureKey } from "../kinship/kinship-signature";

@Injectable()
export class FamilyService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipsService,
    private readonly graphEngine: GraphEngineService,
    private readonly graphService: GraphService,
    private readonly kinship: KinshipService,
  ) {}

  // ----- Family CRUD ----------------------------------------------------

  async createFamily(name: string) {
    return this.prisma.family.create({ data: { name } });
  }

  async prismaFamilyFind(id: string) {
    return this.prisma.family.findUnique({ where: { id } });
  }

  async addPerson(familyId: string, data: {
    fullName: string;
    gender: "MALE" | "FEMALE" | "OTHER";
    birthDate?: Date;
    deathDate?: Date;
    isAdopted?: boolean;
  }) {
    return this.prisma.person.create({ data: { familyId, ...data } });
  }

  // ----- Relationship orchestration ------------------------------------

  async createRelationship(input: CreateRelationshipInput) {
    return this.relationships.create(input);
  }

  /**
   * Auto-detect workflow (spec §10). Long-press A → tap B → engine returns
   * detected term + signature + (if applicable) the missing fundamental edge
   * the user must confirm before storage.
   */
  async detectRelationship(familyId: string, personAId: string, personBId: string, locale = "en") {
    return this.relationships.autoDetect(familyId, personAId, personBId, locale);
  }

  /**
   * Resolve a localized kinship label for the relationship from A to B.
   * Deterministic per spec §14.
   */
  async resolveKinshipLabel(familyId: string, personAId: string, personBId: string, locale = "en") {
    const pathResult = await this.graphEngine.resolveSignature(familyId, personAId, personBId);
    if (!pathResult) {
      return { resolved: false, reason: "No path within depth 8." };
    }
    const lookup = await this.kinship.resolveTerm(pathResult.signature, locale);
    return {
      resolved: true,
      label: lookup.localizedTerm,
      englishTerm: lookup.englishTerm,
      canonicalId: lookup.canonicalId,
      category: lookup.category,
      signature: pathResult.signature,
      signatureKey: signatureKey(pathResult.signature),
      matchedViaFallback: lookup.matchedViaFallback,
      fallbackStep: lookup.fallbackStep,
    };
  }

  // ----- Tree building (UI) --------------------------------------------

  async getTree(
    familyId: string,
    rootPersonId: string,
    locale = "en",
    options: { upDepth?: number; downDepth?: number } = {},
  ): Promise<TreeNode> {
    return this.graphService.buildTree(familyId, rootPersonId, locale, options);
  }

  // ----- Spouse inference (spec §9) ------------------------------------

  /**
   * If Person A and Person B are both parents of the same child,
   * suggest a spouse relationship. Returns the suggestion — does NOT persist.
   * (spec §9.2: dashed line in UI; user must confirm before storing.)
   */
  async inferSpouse(familyId: string, personAId: string, personBId: string) {
    // Find shared children: edges where edgeType=PARENT AND personB=personA's parent
    // i.e. children of A: childEdges where personBId = personAId
    const childrenOfA = await this.prisma.relationship.findMany({
      where: { familyId, personBId: personAId, edgeType: "PARENT" },
      select: { personAId: true },
    });
    const childrenOfB = await this.prisma.relationship.findMany({
      where: { familyId, personBId: personBId, edgeType: "PARENT" },
      select: { personAId: true },
    });
    const setA = new Set(childrenOfA.map((c) => c.personAId));
    const shared = childrenOfB.filter((c) => setA.has(c.personAId)).map((c) => c.personAId);

    if (shared.length === 0) {
      return { inferred: false, reason: "No shared children — no spouse inference possible." };
    }

    // Check if a spouse edge already exists
    const existing = await this.prisma.relationship.findFirst({
      where: {
        familyId,
        edgeType: "SPOUSE",
        OR: [
          { personAId, personBId },
          { personAId: personBId, personBId: personAId },
        ],
      },
    });
    if (existing) {
      return { inferred: false, reason: "Spouse edge already exists.", existingEdgeId: existing.id };
    }

    return {
      inferred: true,
      sharedChildrenIds: shared,
      suggestedEdge: {
        edgeType: "SPOUSE",
        personAId,
        personBId,
        isInferred: true,
      },
      // Per spec §9.2 — caller (UI/controller) must show this as a dashed line
      // and only persist after explicit user confirmation.
    };
  }

  /**
   * Confirm a spouse inference — converts inferred suggestion into a persisted edge.
   */
  async confirmSpouseInference(familyId: string, personAId: string, personBId: string) {
    return this.relationships.create({
      familyId,
      personAId,
      personBId,
      edgeType: "SPOUSE",
      isInferred: false,
    });
  }
}
