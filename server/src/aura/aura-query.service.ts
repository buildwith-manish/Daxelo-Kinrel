// server/src/aura/aura-query.service.ts
//
// AURA — Query Service
//
// Read-only queries for the AURA API endpoints. All methods verify family
// membership before returning data (defense-in-depth on top of RLS).
//
// Endpoints served:
//   GET /aura/:familyId          → getFamilyAura(familyId, userId)
//   GET /aura/:familyId/roles    → getMemberRoles(familyId, userId)
//   GET /aura/:familyId/history  → getAuraHistory(familyId, userId)

import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AuraQueryService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Verify the user is a member of the family. Throws ForbiddenException if not.
   * This is defense-in-depth on top of the RLS policies — even if a bug in the
   * auth guard let an unauthenticated request through, this check would block it.
   */
  private async requireFamilyMembership(familyId: string, userId: string): Promise<void> {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { id: true },
    });
    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }
  }

  /**
   * GET /aura/:familyId
   * Returns the current AURA parameters for a family.
   * Used by Flutter on first load and as a fallback if realtime fails.
   */
  async getFamilyAura(familyId: string, userId: string) {
    await this.requireFamilyMembership(familyId, userId);

    const aura = await this.prisma.familyAura.findUnique({
      where: { familyId },
    });

    if (!aura) {
      throw new NotFoundException(
        `AURA not yet computed for family ${familyId}. ` +
          `POST /aura/${familyId}/recompute to trigger computation.`,
      );
    }

    return {
      familyId: aura.familyId,
      // Symbol parameters for Flutter rendering
      symbol: {
        ringCount: aura.ringCount,
        spokeCount: aura.spokeCount,
        innerPatternType: aura.innerPatternType,
        outerRingRadiusPct: Number(aura.outerRingRadiusPct),
        patternComplexity: aura.patternComplexity,
        primaryColorHex: aura.primaryColorHex,
        secondaryColorHex: aura.secondaryColorHex,
        accentColorHex: aura.accentColorHex,
        pulseSpeedMs: aura.pulseSpeedMs,
      },
      // Archetype for display
      archetype: {
        key: aura.archetypeKey,
        confidence: Number(aura.archetypeConfidence),
      },
      // Raw metrics for debugging / advanced display
      metrics: {
        memberCount: aura.memberCount,
        generationDepth: aura.generationDepth,
        edgeCount: aura.edgeCount,
        clusteringCoefficient: Number(aura.clusteringCoefficient),
        graphDiameter: aura.graphDiameter,
        avgDegree: Number(aura.avgDegree),
        distinctLineages: aura.distinctLineages,
        languageDistribution: aura.languageDistribution,
        maxBetweennessNode: aura.maxBetweennessNode,
        rootNode: aura.rootNode,
      },
      computedAt: aura.computedAt,
      updatedAt: aura.updatedAt,
    };
  }

  /**
   * GET /aura/:familyId/roles
   * Returns all member role glyphs for a family.
   */
  async getMemberRoles(familyId: string, userId: string) {
    await this.requireFamilyMembership(familyId, userId);

    const roles = await this.prisma.memberAuraRole.findMany({
      where: { familyId },
      select: {
        memberId: true,
        roleKey: true,
        glyphShape: true,
        glyphColorHex: true,
        generationIndex: true,
        betweennessScore: true,
        degreeCount: true,
      },
    });

    return { familyId, roles };
  }

  /**
   * GET /aura/:familyId/history
   * Returns the AURA Timeline — all historical AURA snapshots.
   */
  async getAuraHistory(familyId: string, userId: string) {
    await this.requireFamilyMembership(familyId, userId);

    const history = await this.prisma.familyAuraHistory.findMany({
      where: { familyId },
      orderBy: { capturedAt: 'asc' },
      select: {
        id: true,
        memberCount: true,
        generationDepth: true,
        archetypeKey: true,
        ringCount: true,
        spokeCount: true,
        innerPatternType: true,
        primaryColorHex: true,
        secondaryColorHex: true,
        accentColorHex: true,
        archetypeChanged: true,
        previousArchetype: true,
        capturedAt: true,
        triggerMemberId: true,
        triggerEventType: true,
      },
    });

    return { familyId, history };
  }
}
