// =============================================================================
// Track C v2.0 - Kinrel Search
// search.service.ts
// =============================================================================
// Universal cross-entity search across constitution, decisions, memory,
// timeline events, and meeting artifacts. Section 6.6 + 5.9.
//
// Uses Postgres tsvector (generated column on SearchIndex) + GIN index.
// Mirrored to Drift on the client for offline search.
//
// v3 (ML spec item #3 - Semantic search rerank):
//   After the existing tsvector query returns the top-N keyword matches,
//   we rerank them by cosine similarity between the query's all-MiniLM-L6-v2
//   embedding and each result's precomputed embedding. This surfaces
//   semantically related but keyword-mismatched results above exact-keyword
//   but semantically-unrelated ones.
//
//   We do NOT replace keyword search - we rerank its results. This is
//   lower-risk than a pure semantic search (no recall regression on exact
//   queries) and uses the existing SearchIndex infrastructure.
//
//   If the embedding model is unavailable (load failure, memory pressure),
//   we silently fall back to keyword-only ranking - the search still works,
//   just without the semantic boost.
// =============================================================================

import { Injectable, BadRequestException, Logger, OnModuleDestroy } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FamilyMembershipService } from '../common/family-membership.service';
import { EmbeddingService } from './embedding.service';

export type SearchEntityType =
  | 'constitution_article'
  | 'constitution_clause'
  | 'decision'
  | 'memory'
  | 'timeline_event'
  | 'meeting_artifact';

// How many keyword results to fetch before reranking. The semantic rerank
// only looks at the top-N keyword matches - too few and we miss semantic
// hits that didn't rank highly on keywords alone; too many and the embedding
// fetch becomes expensive. 50 is a reasonable middle ground.
const KEYWORD_POOL_SIZE = 50;
// How many final results to return after reranking.
const FINAL_LIMIT_DEFAULT = 20;

@Injectable()
export class SearchService implements OnModuleDestroy {
  private readonly logger = new Logger(SearchService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly membership: FamilyMembershipService,
    private readonly embeddingService: EmbeddingService,
  ) {}

  async onModuleDestroy() {
    await this.embeddingService.dispose();
  }

  /**
   * Universal search. Uses Postgres full-text search via raw SQL (Prisma
   * doesn't support tsvector queries directly).
   *
   * Ranking (v3):
   *   1. Fetch top KEYWORD_POOL_SIZE keyword matches via ts_rank_cd * boostedScore.
   *   2. Embed the query and fetch the precomputed embedding for each result.
   *   3. Compute cosine similarity (query_embed, result_embed) for each.
   *   4. Final score = 0.5 * keyword_rank_normalized + 0.5 * semantic_sim.
   *   5. Sort by final score DESC, take the top `limit`.
   *
   * If the embedding model is unavailable, skip step 2-4 and return the
   * keyword-ranked results directly (legacy behavior).
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

    const finalLimit = Math.min(Math.max(params.limit ?? FINAL_LIMIT_DEFAULT, 1), 100);
    const poolSize = Math.max(finalLimit, KEYWORD_POOL_SIZE);
    const sanitizedQuery = this.sanitizeTsQuery(params.query);

    // ?? Step 1: keyword pass (existing behavior) ??????????????????????
    const entityTypeFilter = params.entityType ? `AND "entityType" = '${params.entityType.replace(/'/g, "''")}'` : '';
    const keywordResults: any[] = await this.prisma.$queryRawUnsafe(
      `
      WITH search_results AS (
        SELECT
          "id",
          "entityType",
          "entityId",
          "title",
          "body",
          "keywords",
          "boostedScore",
          ts_rank_cd(search_tsvector, query) AS rank_score
        FROM public."SearchIndex",
             plainto_tsquery('english', $1) query
        WHERE "familyId" = $2
          ${entityTypeFilter}
          AND search_tsvector @@ query
      )
      SELECT * FROM search_results
      ORDER BY rank_score * "boostedScore" DESC
      LIMIT $3
      `,
      sanitizedQuery,
      params.familyId,
      poolSize,
    );

    if (keywordResults.length === 0) {
      return {
        query: params.query,
        count: 0,
        items: [],
        reranked: false,
      };
    }

    // ?? Step 2: semantic rerank ???????????????????????????????????????
    // Try to embed the query. If the model is unavailable, return the
    // keyword results as-is.
    const queryEmbedding = await this.embeddingService.embed(params.query);
    if (!queryEmbedding) {
      // Fall back to keyword-only ranking
      this.logger.debug?.('Semantic rerank skipped - embedding model unavailable');
      return {
        query: params.query,
        count: Math.min(keywordResults.length, finalLimit),
        items: keywordResults.slice(0, finalLimit).map((r) => ({
          ...r,
          semanticScore: null,
          finalScore: null,
        })),
        reranked: false,
      };
    }

    // Fetch embeddings for all keyword results in one query. We fetch by
    // (entityType, entityId) tuples - Prisma doesn't support composite IN
    // queries, so we fetch by familyId + entityType IN (...) and filter
    // client-side. For typical search (one family, <=50 results) this is fine.
    const entityTypes = Array.from(new Set(keywordResults.map((r) => r.entityType)));
    const entityIds = keywordResults.map((r) => r.entityId);

    const embeddings = await this.prisma.searchEmbedding.findMany({
      where: {
        familyId: params.familyId,
        entityType: { in: entityTypes },
        entityId: { in: entityIds },
      },
      select: { entityType: true, entityId: true, embedding: true },
    });

    // Build a lookup map: `${entityType}|${entityId}` -> number[]
    const embeddingMap = new Map<string, number[]>();
    for (const e of embeddings) {
      try {
        const vec = JSON.parse(e.embedding);
        if (Array.isArray(vec) && vec.length === queryEmbedding.length) {
          embeddingMap.set(`${e.entityType}|${e.entityId}`, vec);
        }
      } catch {
        // malformed embedding row - skip
      }
    }

    // ?? Step 3: rerank by semantic similarity ?????????????????????????
    // Normalize the keyword rank scores to [0, 1] so they can be combined
    // with the [0, 1] cosine similarity without one dominating the other.
    const maxRank = Math.max(...keywordResults.map((r) => Number(r.rank_score) || 0), 1e-9);
    const reranked = keywordResults.map((r) => {
      const keywordNorm = (Number(r.rank_score) || 0) / maxRank;
      const vec = embeddingMap.get(`${r.entityType}|${r.entityId}`);
      const semanticScore = vec
        ? EmbeddingService.cosineSimilarity(queryEmbedding, vec)
        : 0; // no embedding available - neutral semantic score
      // Blend: 50% keyword, 50% semantic. The blend weights are intentionally
      // equal so neither signal dominates - the keyword pass already filtered
      // to relevant items, the semantic pass just reorders them.
      const finalScore = 0.5 * keywordNorm + 0.5 * semanticScore;
      return {
        ...r,
        semanticScore,
        finalScore,
      };
    });

    reranked.sort((a, b) => (b.finalScore ?? 0) - (a.finalScore ?? 0));

    return {
      query: params.query,
      count: Math.min(reranked.length, finalLimit),
      items: reranked.slice(0, finalLimit),
      reranked: true,
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
   * when an entity is created or updated. Also computes and stores a
   * semantic embedding of the entity's title+body for the v3 semantic
   * rerank pass. If the embedding model is unavailable, the SearchIndex
   * row is still upserted (keyword-only search continues to work).
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
    const result = await this.prisma.searchIndex.upsert({
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

    // Best-effort semantic embedding - don't block the upsert on model load
    // failures. We compute the embedding from title + body so it captures
    // both the headline and the substantive content.
    this.upsertEmbedding(params.familyId, params.entityType, params.entityId, `${params.title}\n${params.body}`)
      .catch((err) => {
        this.logger.debug?.(
          `Embedding upsert failed for ${params.entityType}/${params.entityId}: ${(err as Error).message}`,
        );
      });

    return result;
  }

  /**
   * Compute and store a semantic embedding for a search entity. Idempotent
   * (upsert by familyId+entityType+entityId). Skipped silently if the
   * embedding model is unavailable.
   */
  async upsertEmbedding(
    familyId: string,
    entityType: SearchEntityType,
    entityId: string,
    text: string,
  ): Promise<void> {
    const vec = await this.embeddingService.embed(text);
    if (!vec) return; // model unavailable - skip
    await this.prisma.searchEmbedding.upsert({
      where: {
        familyId_entityType_entityId: { familyId, entityType, entityId },
      },
      create: {
        familyId,
        entityType,
        entityId,
        embedding: JSON.stringify(vec),
      },
      update: {
        embedding: JSON.stringify(vec),
      },
    });
  }

  /**
   * Remove a search index entry + its embedding. Called when an entity is deleted.
   */
  async removeIndex(familyId: string, entityType: SearchEntityType, entityId: string) {
    await Promise.all([
      this.prisma.searchIndex.deleteMany({
        where: { familyId, entityType, entityId },
      }),
      this.prisma.searchEmbedding.deleteMany({
        where: { familyId, entityType, entityId },
      }),
    ]);
    return;
  }

  /**
   * Reindex all entities for a family. Admin-only; triggered by the controller
   * which enqueues a pg-boss job.
   */
  async reindexFamily(familyId: string, userId?: string): Promise<{ reindexed: number }> {
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
        body: `${m.summaryText}\n${(m.keyTakeaways as string[]).join('\n')}`,
        keywords: (m.searchKeywords as string[]),
        boostedScore: 1.5,
      });
      count++;
    }

    // Timeline events (read-only mirror)
    const events = await this.prisma.kinrelTimelineEvent.findMany({
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
