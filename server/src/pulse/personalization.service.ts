// server/src/pulse/personalization.service.ts
//
// PersonalizationService — wraps the pure closeness.ts functions for NestJS use.
//
// Responsibilities:
//   1. Load the family graph (Persons + Relationships + Kinrel roles) ONCE per
//      brief generation, then cache it for the duration of the request.
//   2. Provide computeClosenessForTarget(targetPersonId) that collectors can
//      call to get a ClosenessResult without each collector loading the graph.
//   3. Expose applyClosenessTieBreaker() to the orchestrator.
//
// Why a separate service (not just inline in the orchestrator)?
//   - Collectors need per-target closeness scores to set BriefItemData.relevanceScore
//   - We don't want N collectors each loading the family graph (N+1 queries)
//   - The graph cache is per-request, not global (different briefs = different graphs)
//
// Usage pattern (in BriefGeneratorService):
//   const personalization = new PersonalizationService(prisma);
//   await personalization.loadFamilyGraph(familyId);
//   // Pass personalization to collectors via BriefCollectorContext
//   // Collectors call: ctx.personalization?.computeClosenessForTarget(personId)
//   // After collecting all items:
//   const sorted = personalization.applyTieBreaker(items);
//

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  ClosenessInput,
  ClosenessResult,
  PersonNode,
  RelationshipEdge,
  KinrelRole,
  applyClosenessTieBreaker,
  computeCloseness,
} from './closeness';
import { FIXED_WEIGHTS } from './closeness-weights';

const GRAPH_CACHE_TTL_MS = 60_000;
const LEARNED_WEIGHTS_CACHE_TTL_MS = 5 * 60_000; // 5 minutes

interface LearnedWeightsCache {
  weights: typeof FIXED_WEIGHTS;
  bias: number;
  beatsFixed: boolean;
  loadedAt: number;
} // 1 minute — prevents stale data across long requests

@Injectable()
export class PersonalizationService {
  private readonly logger = new Logger(PersonalizationService.name);

  // Per-family graph cache: familyId → { graph, loadedAt }
  private graphCache = new Map<
    string,
    {
      userPersonId: string | null;
      persons: PersonNode[];
      relationships: RelationshipEdge[];
      kinrelRoles: KinrelRole[];
      loadedAt: number;
    }
  >();

  // Learned-weights cache (global, not per-family)
  private learnedWeightsCache: LearnedWeightsCache | null = null;

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Load the family graph for a specific user (their linkedPerson is the
   * "userPersonId" anchor). Caches for GRAPH_CACHE_TTL_MS.
   */
  async loadFamilyGraph(familyId: string, userId: string): Promise<void> {
    const cached = this.graphCache.get(familyId);
    if (cached && Date.now() - cached.loadedAt < GRAPH_CACHE_TTL_MS) {
      // Cache hit — but we still need to update the userPersonId if it differs
      if (cached.userPersonId !== (await this.getUserPersonId(userId))) {
        // userPersonId changed (rare) — reload
      } else {
        return;
      }
    }

    const userPersonId = await this.getUserPersonId(userId);

    // Load all active Persons in the family (excluding deleted + deceased)
    const persons = await this.prisma.person.findMany({
      where: {
        familyId,
        deletedAt: null,
        isDeceased: false,
      },
      select: {
        id: true,
        generationIndex: true,
      },
    });
    const personNodes: PersonNode[] = persons.map((p) => ({
      id: p.id,
      generationIndex: p.generationIndex,
    }));

    // Load all active relationships
    const rels = await this.prisma.relationship.findMany({
      where: { familyId, isActive: true },
      select: {
        fromPersonId: true,
        toPersonId: true,
        relationshipType: true,
      },
    });
    const edges: RelationshipEdge[] = rels.map((r) => ({
      fromPersonId: r.fromPersonId,
      toPersonId: r.toPersonId,
      relationshipType: r.relationshipType,
    }));

    // Load Kinrel roles for all members
    const roles = await this.prisma.memberKinrelRole.findMany({
      where: { familyId },
      select: { memberId: true, roleKey: true },
    });
    const kinrelRoles: KinrelRole[] = roles.map((r) => ({
      personId: r.memberId,
      roleKey: r.roleKey,
    }));

    this.graphCache.set(familyId, {
      userPersonId,
      persons: personNodes,
      relationships: edges,
      kinrelRoles,
      loadedAt: Date.now(),
    });

    this.logger.debug?.(
      `PersonalizationService: loaded graph for family ${familyId} — ${personNodes.length} persons, ${edges.length} edges, ${kinrelRoles.length} Kinrel roles`,
    );
  }

  /**
   * Compute closeness score for a target Person, using the cached graph.
   * Returns 0.5 (neutral) if no graph is loaded for the family.
   */
  computeClosenessForTarget(familyId: string, targetPersonId: string): ClosenessResult {
    const cached = this.graphCache.get(familyId);
    if (!cached) {
      return {
        total: 0.5,
        graphDistance: 0.5,
        generationDistance: 0.5,
        relationshipSemantic: 0.5,
        kinrelRoleMatch: 0.5,
        sharedConnections: 0.5,
        hopCount: null,
        notes: ['No graph loaded — returning neutral 0.5'],
      };
    }

    const input: ClosenessInput = {
      userPersonId: cached.userPersonId,
      targetPersonId,
      persons: cached.persons,
      relationships: cached.relationships,
      kinrelRoles: cached.kinrelRoles,
    };

    const result = computeCloseness(input);

    // v3 (ML spec item #5): if learned weights are available AND beat the
    // fixed baseline, recompute the total score using the learned weights
    // instead of the hardcoded 0.30/0.15/0.35/0.10/0.10 blend.
    //
    // We do this ASYNCHRONOUSLY (fire-and-forget) the first time, then
    // cache the result. Subsequent calls within LEARNED_WEIGHTS_CACHE_TTL_MS
    // reuse the cached weights synchronously.
    //
    // If loading fails or no learned model exists, we fall back to the
    // fixed-formula total that computeCloseness() already returned.
    if (this.learnedWeightsCache && this.learnedWeightsCache.beatsFixed) {
      const w = this.learnedWeightsCache.weights;
      const b = this.learnedWeightsCache.bias;
      const learnedTotal =
        w.graphDistance * result.graphDistance +
        w.generationDistance * result.generationDistance +
        w.relationshipSemantic * result.relationshipSemantic +
        w.kinrelRoleMatch * result.kinrelRoleMatch +
        w.sharedConnections * result.sharedConnections +
        b;
      // Clamp to [0, 1] — the bias term can push outside the range
      result.total = Math.max(0, Math.min(1, Math.round(learnedTotal * 1000) / 1000));
      result.notes.push(`Learned weights applied (bias=${b.toFixed(3)})`);
    } else {
      // Try to load learned weights in the background for next time.
      // We don't block the current call — the fixed weights are fine for now.
      this.maybeLoadLearnedWeights().catch(() => {
        // best-effort
      });
    }

    return result;
  }

  /**
   * v3 (ML spec item #5): lazily load the learned closeness weights from
   * LearnedClosenessWeights. Cached for LEARNED_WEIGHTS_CACHE_TTL_MS.
   * If the table doesn't exist or no row exists, silently falls back to
   * the fixed weights.
   */
  private async maybeLoadLearnedWeights(): Promise<void> {
    if (this.learnedWeightsCache && Date.now() - this.learnedWeightsCache.loadedAt < LEARNED_WEIGHTS_CACHE_TTL_MS) {
      return;
    }
    try {
      const row = await this.prisma.learnedClosenessWeights.findUnique({
        where: { id: 'current' },
      });
      if (!row || !row.beatsFixed) {
        // No learned model, or the learned model didn't beat the fixed
        // baseline — keep using fixed weights.
        this.learnedWeightsCache = null;
        return;
      }
      const w = row.weights as any;
      this.learnedWeightsCache = {
        weights: {
          graphDistance: Number(w.graphDistance) || FIXED_WEIGHTS.graphDistance,
          generationDistance: Number(w.generationDistance) || FIXED_WEIGHTS.generationDistance,
          relationshipSemantic: Number(w.relationshipSemantic) || FIXED_WEIGHTS.relationshipSemantic,
          kinrelRoleMatch: Number(w.kinrelRoleMatch) || FIXED_WEIGHTS.kinrelRoleMatch,
          sharedConnections: Number(w.sharedConnections) || FIXED_WEIGHTS.sharedConnections,
        },
        bias: Number(row.bias) || 0,
        beatsFixed: true,
        loadedAt: Date.now(),
      };
      this.logger.debug?.(
        `PersonalizationService: loaded learned weights (val acc=${(row.validationAccuracy * 100).toFixed(1)}%, ` +
          `+${((row.validationAccuracy - row.fixedBaselineAccuracy) * 100).toFixed(1)}pp over fixed)`,
      );
    } catch (err) {
      // Table may not exist yet (migration not applied) — fall back silently
      this.logger.debug?.(
        `Failed to load learned weights: ${(err as Error).message} — using fixed weights`,
      );
      this.learnedWeightsCache = null;
    }
  }

  /**
   * Apply Phase 2 tie-breaking: within each priority window, sort by
   * closeness DESC. Used by the orchestrator after the initial priority sort.
   */
  applyTieBreaker<T extends { priority: number; relevanceScore?: number }>(
    items: T[],
    priorityWindow: number = 5,
  ): T[] {
    return applyClosenessTieBreaker(items, priorityWindow);
  }

  /**
   * Clear the cache for a specific family (called after brief generation
   * completes to free memory).
   */
  clearCache(familyId?: string): void {
    if (familyId) {
      this.graphCache.delete(familyId);
    } else {
      this.graphCache.clear();
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ────────────────────────────────────────────────────────────────────────

  private async getUserPersonId(userId: string): Promise<string | null> {
    const linkedPerson = await this.prisma.person.findFirst({
      where: { linkedUserId: userId, deletedAt: null },
      select: { id: true },
    });
    return linkedPerson?.id ?? null;
  }
}
