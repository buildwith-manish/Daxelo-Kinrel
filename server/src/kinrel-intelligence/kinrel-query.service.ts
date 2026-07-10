// server/src/kinrel/kinrel-query.service.ts
//
// Kinrel — Query Service
//
// Read-only queries for the Kinrel API endpoints. All methods verify family
// membership before returning data (defense-in-depth on top of RLS).
//
// Endpoints served:
//   GET /kinrel/:familyId          → getFamilyKinrel(familyId, userId)
//   GET /kinrel/:familyId/roles    → getMemberRoles(familyId, userId)
//   GET /kinrel/:familyId/history  → getKinrelHistory(familyId, userId)

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
export class KinrelQueryService {
  private readonly logger = new Logger(KinrelQueryService.name);

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
   * GET /kinrel/:familyId
   * Returns the current Kinrel parameters for a family.
   * Used by Flutter on first load and as a fallback if realtime fails.
   */
  async getFamilyKinrel(familyId: string, userId: string) {
    await this.requireFamilyMembership(familyId, userId);

    const kinrel = await this.prisma.familyKinrel.findUnique({
      where: { familyId },
    });

    if (!kinrel) {
      throw new NotFoundException(
        `Kinrel not yet computed for family ${familyId}. ` +
          `POST /kinrel/${familyId}/recompute to trigger computation.`,
      );
    }

    return {
      familyId: kinrel.familyId,
      // Symbol parameters for Flutter rendering
      symbol: {
        ringCount: kinrel.ringCount,
        spokeCount: kinrel.spokeCount,
        innerPatternType: kinrel.innerPatternType,
        outerRingRadiusPct: Number(kinrel.outerRingRadiusPct),
        patternComplexity: kinrel.patternComplexity,
        primaryColorHex: kinrel.primaryColorHex,
        secondaryColorHex: kinrel.secondaryColorHex,
        accentColorHex: kinrel.accentColorHex,
        pulseSpeedMs: kinrel.pulseSpeedMs,
      },
      // Archetype for display
      archetype: {
        key: kinrel.archetypeKey,
        confidence: Number(kinrel.archetypeConfidence),
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
          this._safeGetDefinition(kinrel.archetypeKey),
        ),
      },
      // Raw metrics for debugging / advanced display
      metrics: {
        memberCount: kinrel.memberCount,
        generationDepth: kinrel.generationDepth,
        edgeCount: kinrel.edgeCount,
        clusteringCoefficient: Number(kinrel.clusteringCoefficient),
        graphDiameter: kinrel.graphDiameter,
        avgDegree: Number(kinrel.avgDegree),
        distinctLineages: kinrel.distinctLineages,
        languageDistribution: kinrel.languageDistribution,
        maxBetweennessNode: kinrel.maxBetweennessNode,
        rootNode: kinrel.rootNode,
      },
      computedAt: kinrel.computedAt,
      updatedAt: kinrel.updatedAt,
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
   * GET /kinrel/:familyId/roles
   * Returns all member role glyphs for a family.
   */
  async getMemberRoles(familyId: string, userId: string) {
    await this.requireFamilyMembership(familyId, userId);

    const roles = await this.prisma.memberKinrelRole.findMany({
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
   * GET /kinrel/:familyId/history
   * Returns the Kinrel Timeline — all historical Kinrel snapshots.
   */
  async getKinrelHistory(familyId: string, userId: string) {
    await this.requireFamilyMembership(familyId, userId);

    const history = await this.prisma.familyKinrelHistory.findMany({
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
        // so the Kinrel Timeline can answer "which language dominated our
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
