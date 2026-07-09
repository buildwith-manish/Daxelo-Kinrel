// =============================================================================
// Track C v2.0 — AURA Search
// search.service.ts
// =============================================================================
// Universal cross-entity search across constitution, decisions, memory,
// timeline events, and meeting artifacts. Section 6.6 + 5.9.
//
// Uses Postgres tsvector (generated column on SearchIndex) + GIN index.
// Mirrored to Drift on the client for offline search.
// =============================================================================

import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FamilyMembershipService } from '../common/family-membership.service';

export type SearchEntityType =
  | 'constitution_article'
  | 'constitution_clause'
  | 'decision'
  | 'memory'
  | 'timeline_event'
  | 'meeting_artifact';

@Injectable()
export class SearchService {
  private readonly logger = new Logger(SearchService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly membership: FamilyMembershipService,
  ) {}

  /**
   * Universal search. Uses Postgres full-text search via raw SQL (Prisma
   * doesn't support tsvector queries directly).
   *
   * Ranking: ts_rank_cd on tsvector + boostedScore (recency + family weight).
   */
  async search(params: {
    familyId: string;
    userId: string;
    query: string;
    entityType?: SearchEntityType;
    limit?: number;
  }) {
    if (!params.query?.trim()) {
      throw new BadRequestException('query must be non-empty');
    }
    await this.membership.requireMember(params.userId, params.familyId);

    const limit = Math.min(Math.max(params.limit ?? 20, 1), 100);
    const sanitizedQuery = this.sanitizeTsQuery(params.query);

    // Use Prisma.$queryRaw for the tsvector query
    const entityTypeFilter = params.entityType ? `AND "entityType" = '${params.entityType.replace(/'/g, "''")}'` : '';
    const results: any[] = await this.prisma.$queryRawUnsafe(
      `
      SELECT
        "id",
        "entityType",
        "entityId",
        "title",
        "body",
        "keywords",
        "boostedScore",
        ts_rank_cd(search_tsvector, query) AS rank
      FROM public."SearchIndex",
           plainto_tsquery('english', $1) query
      WHERE "familyId" = $2
        ${entityTypeFilter}
        AND search_tsvector @@ query
      ORDER BY rank * "boostedScore" DESC
      LIMIT $3
      `,
      sanitizedQuery,
      params.familyId,
      limit,
    );

    return {
      query: params.query,
      count: results.length,
      items: results,
    };
  }

  /**
   * Suggest (autocomplete). Returns up to 10 titles matching the prefix.
   */
  async suggest(params: { familyId: string; userId: string; q: string }) {
    if (!params.q?.trim() || params.q.length < 2) return { suggestions: [] };
    await this.membership.requireMember(params.userId, params.familyId);

    const prefix = `${params.q.toLowerCase()}%`;
    const results: any[] = await this.prisma.$queryRawUnsafe(
      `
      SELECT DISTINCT ON ("title") "title", "entityType"
      FROM public."SearchIndex"
      WHERE "familyId" = $1
        AND LOWER("title") LIKE $2
      ORDER BY "title", "boostedScore" DESC
      LIMIT 10
      `,
      params.familyId,
      prefix,
    );

    return { suggestions: results.map((r) => r.title) };
  }

  /**
   * Upsert a search index entry for an entity. Called by entity services
   * when an entity is created or updated.
   */
  async upsertIndex(params: {
    familyId: string;
    entityType: SearchEntityType;
    entityId: string;
    title: string;
    body: string;
    keywords?: string[];
    boostedScore?: number;
  }) {
    const score = params.boostedScore ?? this.computeBoostedScore(params.entityType);
    return this.prisma.searchIndex.upsert({
      where: {
        familyId_entityType_entityId: {
          familyId: params.familyId,
          entityType: params.entityType,
          entityId: params.entityId,
        },
      },
      create: {
        familyId: params.familyId,
        entityType: params.entityType,
        entityId: params.entityId,
        title: params.title,
        body: params.body,
        keywords: params.keywords ?? [],
        boostedScore: score,
      },
      update: {
        title: params.title,
        body: params.body,
        keywords: params.keywords ?? [],
        boostedScore: score,
      },
    });
  }

  /**
   * Remove a search index entry. Called when an entity is deleted.
   */
  async removeIndex(familyId: string, entityType: SearchEntityType, entityId: string) {
    return this.prisma.searchIndex.deleteMany({
      where: { familyId, entityType, entityId },
    });
  }

  /**
   * Reindex all entities for a family. Admin-only; triggered by the controller
   * which enqueues a pg-boss job.
   */
  async reindexFamily(familyId: string): Promise<{ reindexed: number }> {
    let count = 0;

    // Decisions
    const decisions = await this.prisma.familyDecision.findMany({
      where: { familyId },
      select: { id: true, title: true, description: true, type: true, status: true, createdAt: true },
    });
    for (const d of decisions) {
      await this.upsertIndex({
        familyId,
        entityType: 'decision',
        entityId: d.id,
        title: d.title,
        body: `${d.title}\n${d.description ?? ''}\nType: ${d.type}\nStatus: ${d.status}`,
        keywords: [d.type, d.status],
        boostedScore: this.recencyBoost(d.createdAt) * 2.0,
      });
      count++;
    }

    // Decision memory
    const memories = await this.prisma.decisionMemory.findMany({
      where: { familyId },
      select: { id: true, decisionId: true, summaryText: true, keyTakeaways: true, searchKeywords: true },
    });
    for (const m of memories) {
      await this.upsertIndex({
        familyId,
        entityType: 'memory',
        entityId: m.decisionId,
        title: `Memory: ${m.summaryText.slice(0, 80)}`,
        body: `${m.summaryText}\n${m.keyTakeaways.join('\n')}`,
        keywords: m.searchKeywords,
        boostedScore: 1.5,
      });
      count++;
    }

    // Timeline events (read-only mirror)
    const events = await this.prisma.aURATimelineEvent.findMany({
      where: { familyId },
      select: { id: true, title: true, description: true, kind: true, occurredAt: true },
      take: 5000, // cap to avoid runaway reindex
    });
    for (const e of events) {
      await this.upsertIndex({
        familyId,
        entityType: 'timeline_event',
        entityId: e.id,
        title: e.title,
        body: `${e.title}\n${e.description ?? ''}\nKind: ${e.kind}`,
        keywords: [e.kind],
        boostedScore: this.recencyBoost(e.occurredAt),
      });
      count++;
    }

    // Constitution articles + clauses
    const articles = await this.prisma.constitutionArticle.findMany({
      where: { familyId },
      include: { clauses: true },
    });
    for (const a of articles) {
      await this.upsertIndex({
        familyId,
        entityType: 'constitution_article',
        entityId: a.id,
        title: a.title,
        body: `${a.title}\n${a.intent ?? ''}\n${a.clauses.map((c) => c.text).join('\n')}`,
        keywords: ['constitution'],
        boostedScore: 1.2,
      });
      count++;
      for (const c of a.clauses) {
        await this.upsertIndex({
          familyId,
          entityType: 'constitution_clause',
          entityId: c.id,
          title: `Clause: ${c.text.slice(0, 80)}`,
          body: c.text,
          keywords: ['constitution', 'clause'],
          boostedScore: 1.0,
        });
        count++;
      }
    }

    // Meeting artifacts
    const artifacts = await this.prisma.meetingArtifact.findMany({
      where: { familyId },
      select: { id: true, title: true, draftMinutesMd: true, heldAt: true },
    });
    for (const a of artifacts) {
      await this.upsertIndex({
        familyId,
        entityType: 'meeting_artifact',
        entityId: a.id,
        title: `Meeting: ${a.title}`,
        body: `${a.title}\n${a.draftMinutesMd.slice(0, 2000)}`,
        keywords: ['meeting', 'minutes'],
        boostedScore: this.recencyBoost(a.heldAt) * 1.5,
      });
      count++;
    }

    return { reindexed: count };
  }

  private computeBoostedScore(entityType: SearchEntityType): number {
    switch (entityType) {
      case 'decision': return 2.0;
      case 'memory': return 1.5;
      case 'meeting_artifact': return 1.5;
      case 'constitution_article': return 1.2;
      case 'constitution_clause': return 1.0;
      case 'timeline_event': return 1.0;
    }
  }

  private recencyBoost(date: Date): number {
    // Boost recent items: linear decay over 365 days
    const ageDays = (Date.now() - date.getTime()) / (24 * 60 * 60 * 1000);
    return Math.max(0.5, 1.0 - ageDays / 365);
  }

  private sanitizeTsQuery(q: string): string {
    // Strip special characters that could break the query
    return q.replace(/[&|!():*]/g, ' ').trim();
  }
}
