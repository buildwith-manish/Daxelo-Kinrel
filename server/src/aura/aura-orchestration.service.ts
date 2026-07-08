// server/src/aura/aura-orchestration.service.ts
//
// AURA — Orchestration Service
//
// The main coordinator for AURA computation. Wires together:
//   1. GraphAnalysisService   → compute graph metrics (Phase 2)
//   2. ArchetypeClassifierService → classify into one of 6 archetypes (Phase 3)
//   3. AuraParameterGeneratorService → map metrics → symbol params (Phase 4)
//   4. Prisma upsert → store FamilyAura row
//   5. Prisma create → push FamilyAuraHistory snapshot
//   6. RoleGlyphService → compute + upsert MemberAuraRole rows
//
// Realtime broadcast is automatic: FamilyAura + MemberAuraRole are in the
// supabase_realtime publication, so Flutter receives postgres_changes
// events when we upsert. No explicit broadcast code needed here.
//
// Error handling: any failure in steps 1–6 is logged and re-thrown so the
// caller (AuraEventListener or AuraController) can decide what to do.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { GraphAnalysisService } from './graph-analysis.service';
import { ArchetypeClassifierService } from './archetype-classifier.service';
import { AuraParameterGeneratorService } from './aura-parameter-generator.service';
import { RoleGlyphService } from './role-glyph.service';

export interface ComputeAndSaveOptions {
  /** Optional: which member triggered this recompute (for history snapshot) */
  triggerMemberId?: string | null;
  /** Optional: what event type triggered this (for history snapshot) */
  triggerEventType?: string;
}

@Injectable()
export class AuraOrchestrationService {
  private readonly logger = new Logger(AuraOrchestrationService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly graphAnalysis: GraphAnalysisService,
    private readonly classifier: ArchetypeClassifierService,
    private readonly paramGenerator: AuraParameterGeneratorService,
    private readonly roleGlyph: RoleGlyphService,
  ) {}

  /**
   * Compute the full AURA for a family and persist all results.
   *
   * Steps:
   *   1. Compute graph metrics
   *   2. Classify archetype
   *   3. Generate symbol parameters
   *   4. Load previous AURA (to detect archetype changes)
   *   5. Upsert FamilyAura row
   *   6. Create FamilyAuraHistory snapshot
   *   7. Compute + upsert MemberAuraRole rows
   *
   * Realtime broadcast happens automatically via the supabase_realtime
   * publication on FamilyAura + MemberAuraRole.
   */
  async computeAndSave(
    familyId: string,
    options: ComputeAndSaveOptions = {},
  ): Promise<void> {
    const startTime = Date.now();
    this.logger.log(`Starting AURA computation for family ${familyId}`);

    // Step 1: Compute graph metrics
    const metrics = await this.graphAnalysis.computeMetrics(familyId);

    if (metrics.memberCount === 0) {
      this.logger.warn(`Family ${familyId} has 0 members — skipping AURA computation`);
      return;
    }

    // Step 2: Classify archetype
    const classification = this.classifier.classify(metrics);

    // Step 3: Generate symbol parameters
    const params = this.paramGenerator.generate(metrics, classification.archetypeKey);

    // Step 4: Load previous AURA to detect archetype changes
    const previousAura = await this.prisma.familyAura.findUnique({
      where: { familyId },
      select: { archetypeKey: true },
    });

    // archetypeChanged is TRUE only when there was a previous archetype
    // AND it differs from the new one. The first computation (previousAura
    // is null) is NOT a change — there was nothing to change from.
    const archetypeChanged =
      previousAura !== null &&
      previousAura.archetypeKey !== classification.archetypeKey;

    // ── Validate triggerMemberId exists before passing to history snapshot ──
    // The triggerMemberId comes from Supabase Realtime events, which may
    // reference a Person that was just deleted (e.g., family.member.removed
    // events carry the ID of the deleted person). By the time the debounced
    // recompute fires (2s later), that Person row is gone, and the FK
    // constraint on FamilyAuraHistory.triggerMemberId would fail.
    // Solution: verify the Person exists; if not, set triggerMemberId to null.
    let safeTriggerMemberId: string | null = options.triggerMemberId ?? null;
    if (safeTriggerMemberId !== null) {
      const triggerPerson = await this.prisma.person.findUnique({
        where: { id: safeTriggerMemberId },
        select: { id: true },
      });
      if (!triggerPerson) {
        this.logger.debug(
          `triggerMemberId ${safeTriggerMemberId} no longer exists — setting to null`,
        );
        safeTriggerMemberId = null;
      }
    }

    // Step 5: Upsert family_aura
    await this.prisma.familyAura.upsert({
      where: { familyId },
      create: {
        familyId,
        memberCount: metrics.memberCount,
        generationDepth: metrics.generationDepth,
        edgeCount: metrics.edgeCount,
        clusteringCoefficient: metrics.clusteringCoefficient,
        graphDiameter: metrics.graphDiameter,
        avgDegree: metrics.avgDegree,
        maxBetweennessNode: metrics.maxBetweennessNodeId,
        rootNode: metrics.rootNodeId,
        distinctLineages: metrics.distinctLineages,
        languageDistribution: metrics.languageDistribution as any,
        ringCount: params.ringCount,
        spokeCount: params.spokeCount,
        innerPatternType: params.innerPatternType,
        outerRingRadiusPct: params.outerRingRadiusPct,
        patternComplexity: params.patternComplexity,
        primaryColorHex: params.primaryColorHex,
        secondaryColorHex: params.secondaryColorHex,
        accentColorHex: params.accentColorHex,
        pulseSpeedMs: params.pulseSpeedMs,
        archetypeKey: classification.archetypeKey,
        archetypeConfidence: classification.confidence,
        computedAt: new Date(),
      },
      update: {
        memberCount: metrics.memberCount,
        generationDepth: metrics.generationDepth,
        edgeCount: metrics.edgeCount,
        clusteringCoefficient: metrics.clusteringCoefficient,
        graphDiameter: metrics.graphDiameter,
        avgDegree: metrics.avgDegree,
        maxBetweennessNode: metrics.maxBetweennessNodeId,
        rootNode: metrics.rootNodeId,
        distinctLineages: metrics.distinctLineages,
        languageDistribution: metrics.languageDistribution as any,
        ringCount: params.ringCount,
        spokeCount: params.spokeCount,
        innerPatternType: params.innerPatternType,
        outerRingRadiusPct: params.outerRingRadiusPct,
        patternComplexity: params.patternComplexity,
        primaryColorHex: params.primaryColorHex,
        secondaryColorHex: params.secondaryColorHex,
        accentColorHex: params.accentColorHex,
        pulseSpeedMs: params.pulseSpeedMs,
        archetypeKey: classification.archetypeKey,
        archetypeConfidence: classification.confidence,
        computedAt: new Date(),
      },
    });

    // Step 6: Save history snapshot
    await this.prisma.familyAuraHistory.create({
      data: {
        familyId,
        memberCount: metrics.memberCount,
        generationDepth: metrics.generationDepth,
        archetypeKey: classification.archetypeKey,
        ringCount: params.ringCount,
        spokeCount: params.spokeCount,
        innerPatternType: params.innerPatternType,
        primaryColorHex: params.primaryColorHex,
        secondaryColorHex: params.secondaryColorHex,
        accentColorHex: params.accentColorHex,
        // Bug 9 fix: persist the raw languageDistribution in the history
        // snapshot so the AURA Timeline can answer "which language
        // dominated our family at this point in time?". Previously the
        // snapshot stored colours but not the language map, making the
        // historical linguistic fingerprint unrecoverable.
        languageDistribution: metrics.languageDistribution as any,
        triggerMemberId: safeTriggerMemberId,
        triggerEventType: options.triggerEventType ?? 'manual_recompute',
        archetypeChanged,
        previousArchetype: archetypeChanged ? (previousAura?.archetypeKey ?? null) : null,
        capturedAt: new Date(),
      },
    });

    // Step 7: Update member role glyphs
    await this.roleGlyph.computeAndSaveRoles(familyId, metrics, params);

    const elapsedMs = Date.now() - startTime;
    this.logger.log(
      `AURA computed for family ${familyId} in ${elapsedMs}ms: ` +
        `${classification.archetypeKey} (confidence: ${classification.confidence.toFixed(3)}, ` +
        `archetype changed: ${archetypeChanged})`,
    );
  }
}
