/**
 * Daxelo-Kinrel — Relationship Service (spec §8, §10)
 * =====================================================
 * CRUD + Relationship Normalizer for fundamental edges.
 *
 *   Detected Term (e.g., "wife")
 *         ↓
 *   CanonicalId  ("SPOUSE")
 *         ↓
 *   Relationship Normalizer  (this service)
 *         ↓
 *   Fundamental Edge  ("spouse")
 *         ↓
 *   Store in Database
 *
 * Critical rule (spec §8.2): if the user-facing term is DERIVED (uncle,
 * cousin, grandfather...), the normalizer must trace back to the missing
 * fundamental edge that would complete the graph, ask the user to confirm,
 * and store only the fundamental edge.
 */

import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service";
import { CanonicalIdService } from "../kinship/canonical-id.service";
import { RelationshipValidator, ValidationResult } from "./relationship.validator";
import { GraphEngineService } from "../graph/graph-engine.service";
import { KinshipService } from "../kinship/kinship.service";
import { SignatureCacheService } from "../../cache/signature-cache.service";

export interface CreateRelationshipInput {
  familyId: string;
  personAId: string;
  personBId: string;
  // Either pass a user-facing term (which we normalize) OR an explicit edge type.
  detectedTerm?: string;
  locale?: string;
  edgeType?: "PARENT" | "SPOUSE" | "ADOPTIVE_PARENT" | "STEP_PARENT";
  temporal?: "CURRENT" | "FORMER" | "LATE";
  isInferred?: boolean;
}

export interface NormalizationResult {
  accepted: boolean;
  canonicalId: string;
  edgeType?: "PARENT" | "SPOUSE" | "ADOPTIVE_PARENT" | "STEP_PARENT";
  reason?: string;
  /** When the term is DERIVED, the engine returns the missing fundamental edge
   *  the user must confirm before storage. (spec §8.2) */
  missingFundamentalEdge?: {
    description: string;
    suggestedEdgeType: "PARENT" | "SPOUSE" | "ADOPTIVE_PARENT" | "STEP_PARENT";
  };
}

@Injectable()
export class RelationshipsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly canonicalId: CanonicalIdService,
    private readonly validator: RelationshipValidator,
    private readonly graphEngine: GraphEngineService,
    private readonly kinship: KinshipService,
    private readonly signatureCache: SignatureCacheService,
  ) {}

  /**
   * Normalize a user-facing detected term into a storable fundamental edge.
   * (spec §8)
   */
  normalize(detectedTerm: string, locale: string = "en"): NormalizationResult {
    const canonical = this.canonicalId.normalizeToCanonical(detectedTerm, locale);
    if (canonical === "DERIVED") {
      // Spec §8.2: trace back to the missing fundamental edge.
      // The actual missing-edge resolution happens at the FamilyService level
      // because it requires graph context. Here we just return a hint.
      return {
        accepted: false,
        canonicalId: "DERIVED",
        reason: `"${detectedTerm}" is a derived kinship label. The engine must ask the user for the missing fundamental edge.`,
        missingFundamentalEdge: {
          description: `Please confirm the fundamental relationship that produces "${detectedTerm}".`,
          suggestedEdgeType: "PARENT", // most common; engine refines via graph analysis
        },
      };
    }
    // Map canonical → edge type
    const edgeTypeMap: Record<string, "PARENT" | "SPOUSE" | "ADOPTIVE_PARENT" | "STEP_PARENT"> = {
      PARENT: "PARENT",
      SPOUSE: "SPOUSE",
      ADOPTIVE_PARENT: "ADOPTIVE_PARENT",
      STEP_PARENT: "STEP_PARENT",
    };
    return { accepted: true, canonicalId: canonical, edgeType: edgeTypeMap[canonical] };
  }

  /**
   * Create a fundamental edge after validation.
   * Throws on validation failure.
   */
  async create(input: CreateRelationshipInput) {
    let edgeType = input.edgeType;
    if (!edgeType && input.detectedTerm) {
      const norm = this.normalize(input.detectedTerm, input.locale ?? "en");
      if (!norm.accepted || !norm.edgeType) {
        throw new Error(norm.reason ?? "Normalization failed");
      }
      edgeType = norm.edgeType;
    }
    if (!edgeType) throw new Error("Either edgeType or detectedTerm must be provided");

    const validation: ValidationResult = await this.validator.validateCreate({
      familyId: input.familyId,
      personAId: input.personAId,
      personBId: input.personBId,
      edgeType,
      temporal: input.temporal,
    });
    if (!validation.ok) {
      const fail = validation as { ok: false; reason: string; rule: string };
      throw new Error(`[${fail.rule}] ${fail.reason}`);
    }

    const created = await this.prisma.relationship.create({
      data: {
        familyId: input.familyId,
        personAId: input.personAId,
        personBId: input.personBId,
        edgeType,
        temporal: input.temporal ?? "CURRENT",
        isInferred: input.isInferred ?? false,
      },
    });

    // Invalidate caches (spec §13):
    //   §13.2 — adjacency cache: invalidate whole family (rebuilt from edges)
    //   §13.1 — signature cache: targeted invalidation only (do NOT flush entire cache)
    this.graphEngine.invalidateFamily(input.familyId);
    await this.signatureCache.invalidatePerson(input.familyId, input.personAId);
    await this.signatureCache.invalidatePerson(input.familyId, input.personBId);
    return created;
  }

  async list(familyId: string) {
    return this.prisma.relationship.findMany({ where: { familyId } });
  }

  async delete(id: string) {
    const edge = await this.prisma.relationship.findUnique({ where: { id } });
    if (!edge) throw new Error("Edge not found");
    await this.prisma.relationship.delete({ where: { id } });
    this.graphEngine.invalidateFamily(edge.familyId);
    await this.signatureCache.invalidatePerson(edge.familyId, edge.personAId);
    await this.signatureCache.invalidatePerson(edge.familyId, edge.personBId);
    return { deleted: true, id };
  }

  /**
   * Auto-detect workflow (spec §10):
   *   1. BFS shortest path between A and B
   *   2. Build signature
   *   3. Resolve term via KinshipService
   *   4. Normalize to canonical
   *   5. If DERIVED → return missing-fundamental-edge prompt
   *   6. If fundamental → store + invalidate cache
   */
  async autoDetect(familyId: string, personAId: string, personBId: string, locale: string = "en") {
    const pathResult = await this.graphEngine.resolveSignature(familyId, personAId, personBId);
    if (!pathResult) {
      return {
        detected: false,
        reason: "Insufficient graph info — please specify the fundamental edge manually.",
        manualPickerOptions: ["PARENT", "SPOUSE", "ADOPTIVE_PARENT", "STEP_PARENT"],
      };
    }
    const lookup = await this.kinship.resolveTerm(pathResult.signature, locale);
    const norm = this.normalize(lookup.englishTerm, locale);
    return {
      detected: true,
      signature: pathResult.signature,
      term: lookup.localizedTerm,
      englishTerm: lookup.englishTerm,
      canonicalId: norm.canonicalId,
      requiresUserConfirmation: !norm.accepted,
      missingFundamentalEdge: norm.missingFundamentalEdge ?? null,
      path: pathResult.steps,
    };
  }
}
