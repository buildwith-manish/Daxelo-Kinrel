// server/src/pulse/personalization.service.ts
//
// PersonalizationService — wraps the pure closeness.ts functions for NestJS use.
//
// Responsibilities:
//   1. Load the family graph (Persons + Relationships + AURA roles) ONCE per
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
  AuraRole,
  applyClosenessTieBreaker,
  computeCloseness,
} from './closeness';

const GRAPH_CACHE_TTL_MS = 60_000; // 1 minute — prevents stale data across long requests

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
      auraRoles: AuraRole[];
      loadedAt: number;
    }
  >();

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

    // Load AURA roles for all members
    const roles = await this.prisma.memberAuraRole.findMany({
      where: { familyId },
      select: { memberId: true, roleKey: true },
    });
    const auraRoles: AuraRole[] = roles.map((r) => ({
      personId: r.memberId,
      roleKey: r.roleKey,
    }));

    this.graphCache.set(familyId, {
      userPersonId,
      persons: personNodes,
      relationships: edges,
      auraRoles,
      loadedAt: Date.now(),
    });

    this.logger.debug?.(
      `PersonalizationService: loaded graph for family ${familyId} — ${personNodes.length} persons, ${edges.length} edges, ${auraRoles.length} AURA roles`,
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
        auraRoleMatch: 0.5,
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
      auraRoles: cached.auraRoles,
    };

    return computeCloseness(input);
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
