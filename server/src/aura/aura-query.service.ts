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

import { Injectable, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  ArchetypeClassifierService,
  ArchetypeDefinition,
} from './archetype-classifier.service';

// Bug 15 fix: the canonical list of valid archetype keys. Kept in sync
// with `ArchetypeKey` in archetype-classifier.service.ts. If a new
// archetype is added there, add it here too. We use this to validate
// the DB-stored `archetypeKey` before passing it to `getDefinition`,
// so a stale/typo'd key in the DB doesn't silently fall back to lotus.
const VALID_ARCHETYPE_KEYS = new Set<string>([
  'banyan',
  'river_delta',
  'confluence',
  'spine',
  'lotus',
  'forest',
]);

@Injectable()
export class AuraQueryService {
  private readonly logger = new Logger(AuraQueryService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly classifier: ArchetypeClassifierService,
  ) {}

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
        // Bug 8 fix: include the full archetype definition (names +
        // descriptions in all 8 supported languages) so the Flutter
        // client can render the user's locale instead of hardcoding
        // English. The backend already has these strings in
        // ARCHETYPES[].names / .descriptions — they were just never
        // sent to the client.
        //
        // Bug 15 fix: validate `archetypeKey` against the known keys
        // before calling `getDefinition`. If the DB holds a stale/typo'd
        // key (e.g. from a manual edit or a renamed archetype),
        // `getDefinition` would silently fall back to ARCHETYPES[4]
        // (lotus) — the user would see a Lotus symbol but the row's
        // archetypeKey would still say something else, so the next
        // recompute could flip it back. We log a warning so the
        // mismatch is visible in server logs.
        definition: this._definitionToPlainObject(
          this._safeGetDefinition(aura.archetypeKey),
        ),
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
   * Convert an ArchetypeDefinition to a plain object for the JSON response.
   * Strips the methods + thresholds (which are classifier internals) and
   * keeps only the locale-string maps the Flutter client needs.
   */
  private _definitionToPlainObject(def: ArchetypeDefinition) {
    return {
      key: def.key,
      glyphStyle: def.glyphStyle,
      names: def.names,
      descriptions: def.descriptions,
    };
  }

  /**
   * Bug 15 fix: validate `archetypeKey` against the known keys before
   * calling `getDefinition`. If the DB holds a stale/typo'd key (e.g.
   * from a manual edit, a renamed archetype, or a row written by an
   * older version of the classifier), `getDefinition` would silently
   * fall back to ARCHETYPES[4] (lotus). We log a warning so the
   * mismatch is visible in server logs, then return the lotus
   * definition as a safe fallback.
   */
  private _safeGetDefinition(archetypeKey: string): ArchetypeDefinition {
    if (!VALID_ARCHETYPE_KEYS.has(archetypeKey)) {
      this.logger.warn(
        `Unknown archetypeKey "${archetypeKey}" in DB — falling back to lotus. ` +
          `This usually means the row was written by an older app version ` +
          `or manually edited. A recompute will fix it.`,
      );
      return this.classifier.getDefinition('lotus');
    }
    return this.classifier.getDefinition(archetypeKey as never);
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
        // Bug 9 fix: include languageDistribution in the history response
        // so the AURA Timeline can answer "which language dominated our
        // family at this point in time?". Previously the column was
        // never selected, so the timeline lost that data point.
        languageDistribution: true,
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
