/**
 * Daxelo-Kinrel — Relationship Validator (spec §12)
 * ===================================================
 * Before creating any relationship, these rules MUST pass:
 *
 *   1. Reject self-relationships. A person cannot relate to themselves.
 *   2. Reject duplicate edges. No two identical fundamental edges between same pair.
 *   3. Reject circular ancestry. If A is an ancestor of B, B cannot be a parent of A.
 *   4. Reject invalid spouse relationships. Cannot marry an ancestor or descendant.
 *   5. Reject contradictory relationships. If A is already B's parent, A cannot be B's spouse.
 *   6. Preserve existing valid relationships. Never overwrite confirmed data automatically.
 */

import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service";
import { GraphEngineService } from "../graph/graph-engine.service";

export type ValidationResult = { ok: true } | { ok: false; reason: string; rule: string };

@Injectable()
export class RelationshipValidator {
  constructor(
    private readonly prisma: PrismaService,
    private readonly graphEngine: GraphEngineService,
  ) {}

  async validateCreate(params: {
    familyId: string;
    personAId: string;
    personBId: string;
    edgeType: "PARENT" | "SPOUSE" | "ADOPTIVE_PARENT" | "STEP_PARENT";
    temporal?: "CURRENT" | "FORMER" | "LATE";
  }): Promise<ValidationResult> {
    const { familyId, personAId, personBId, edgeType } = params;
    const temporal = params.temporal ?? "CURRENT";

    // Rule 1: reject self-relationships
    if (personAId === personBId) {
      return { ok: false, reason: "A person cannot relate to themselves.", rule: "no_self_relationship" };
    }

    // Rule 2: reject duplicate edges
    const existing = await this.prisma.relationship.findFirst({
      where: { familyId, personAId, personBId, edgeType, temporal },
    });
    if (existing) {
      return {
        ok: false,
        reason: `An identical ${edgeType} edge already exists between these persons.`,
        rule: "no_duplicate_edge",
      };
    }

    // Rule 4: cannot marry an ancestor or descendant
    if (edgeType === "SPOUSE") {
      const aToB = await this.graphEngine.resolveSignature(familyId, personAId, personBId);
      if (aToB && aToB.signature.generationDelta !== 0) {
        return {
          ok: false,
          reason: "Cannot marry an ancestor or descendant.",
          rule: "no_spouse_to_ancestor_or_descendant",
        };
      }
      // Rule 5: if A is already B's parent, A cannot be B's spouse
      const parentEdge = await this.prisma.relationship.findFirst({
        where: { familyId, personAId, personBId, edgeType: "PARENT" },
      });
      if (parentEdge) {
        return {
          ok: false,
          reason: "Cannot marry a person who is already your child (parent edge exists).",
          rule: "no_contradictory_parent_spouse",
        };
      }
    }

    // Rule 3: reject circular ancestry
    if (edgeType === "PARENT" || edgeType === "ADOPTIVE_PARENT" || edgeType === "STEP_PARENT") {
      // Creating: personA's parent is personB. Check that personB is not a descendant of personA.
      const bToA = await this.graphEngine.resolveSignature(familyId, personBId, personAId);
      if (bToA && bToA.signature.generationDelta > 0) {
        return {
          ok: false,
          reason: "Cannot create parent edge — would form circular ancestry.",
          rule: "no_circular_ancestry",
        };
      }
    }

    return { ok: true };
  }
}
