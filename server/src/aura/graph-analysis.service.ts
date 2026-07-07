// server/src/aura/graph-analysis.service.ts
//
// AURA — NestJS Graph Analysis Service
//
// This is the NestJS wrapper around the pure computation in graph-metrics.ts.
// It loads the family's Person + Relationship rows from Prisma, converts them
// to GraphNode[] + GraphEdge[], and calls computeGraphMetrics().
//
// All algorithm logic lives in graph-metrics.ts (which has zero NestJS
// dependencies) so it can be unit-tested in isolation.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  GraphNode,
  GraphEdge,
  GraphMetrics,
  computeGraphMetrics,
} from './graph-metrics';

@Injectable()
export class GraphAnalysisService {
  private readonly logger = new Logger(GraphAnalysisService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ── PUBLIC ENTRY POINT ─────────────────────────────────────

  async computeMetrics(familyId: string): Promise<GraphMetrics> {
    this.logger.log(`Computing graph metrics for family ${familyId}`);

    const [nodes, edges, family] = await Promise.all([
      this.loadNodes(familyId),
      this.loadEdges(familyId),
      this.loadFamilyPrimaryLanguage(familyId),
    ]);

    if (nodes.length === 0) {
      this.logger.warn(`Family ${familyId} has 0 members — returning empty metrics`);
      return computeGraphMetrics([], [], family?.primaryLanguage ?? 'en');
    }

    return computeGraphMetrics(nodes, edges, family?.primaryLanguage ?? 'en');
  }

  // ── PRIVATE: Data Loaders ──────────────────────────────────

  private async loadNodes(familyId: string): Promise<GraphNode[]> {
    const persons = await this.prisma.person.findMany({
      where: {
        familyId,
        deletedAt: null, // only active (non-deleted) persons
      },
      select: { id: true },
    });
    return persons.map((p) => ({ id: p.id }));
  }

  private async loadEdges(familyId: string): Promise<GraphEdge[]> {
    const relationships = await this.prisma.relationship.findMany({
      where: {
        familyId,
        isActive: true, // only active relationships
      },
      select: {
        fromPersonId: true,
        toPersonId: true,
        relationshipType: true,
        direction: true,
      },
    });

    return relationships.map((r) => ({
      fromId: r.fromPersonId,
      toId: r.toPersonId,
      relationshipType: r.relationshipType,
      direction: r.direction,
    }));
  }

  private async loadFamilyPrimaryLanguage(
    familyId: string,
  ): Promise<{ primaryLanguage: string } | null> {
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { primaryLanguage: true },
    });
    return family;
  }

  // ── PUBLIC: Pure computation accessor (for testing) ────────
  //
  // Exposed as a public method so unit tests can call the pure computation
  // without going through Prisma. In production, computeMetrics() is the
  // entry point.

  computeMetricsFromGraph(
    nodes: GraphNode[],
    edges: GraphEdge[],
    familyPrimaryLanguage: string = 'en',
  ): GraphMetrics {
    return computeGraphMetrics(nodes, edges, familyPrimaryLanguage);
  }
}
