import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { KbQueryDto, KbSearchDto, KbHelpfulDto } from './dto/kb-query.dto';

@Injectable()
export class KnowledgeBaseService {
  private readonly logger = new Logger(KnowledgeBaseService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ── List Articles ─────────────────────────────────────────────────

  async listArticles(query: KbQueryDto) {
    const lang = query.lang ?? 'en';
    const page = query.page ?? 1;
    const limit = query.limit ?? 20;

    // Single article by slug
    if (query.slug) {
      const article = await this.prisma.kBArticle.findUnique({ where: { slug: query.slug } });
      if (!article || article.status !== 'published') {
        throw new NotFoundException('Article not found');
      }

      // Increment views
      await this.prisma.kBArticle.update({
        where: { id: article.id },
        data: { views: { increment: 1 } },
      });

      const parsed = this.parseArticle(article, lang);
      return {
        article: {
          ...parsed,
          views: article.views + 1,
          helpfulYes: article.helpfulYes,
          helpfulNo: article.helpfulNo,
          publishedAt: article.publishedAt,
        },
      };
    }

    // List articles
    const where: Record<string, unknown> = { status: 'published' };
    if (query.category) where.category = query.category;

    const [articles, total] = await Promise.all([
      this.prisma.kBArticle.findMany({
        where,
        orderBy: [{ featured: 'desc' }, { sortOrder: 'asc' }, { views: 'desc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.kBArticle.count({ where }),
    ]);

    const localizedArticles = articles.map((a) => {
      const parsed = this.parseArticle(a, lang);
      return {
        ...parsed,
        featured: a.featured,
        views: a.views,
        helpfulYes: a.helpfulYes,
        helpfulNo: a.helpfulNo,
        publishedAt: a.publishedAt,
      };
    });

    return { articles: localizedArticles, total, page, limit };
  }

  // ── Mark Helpful ──────────────────────────────────────────────────

  async markHelpful(dto: KbHelpfulDto) {
    if (!dto.slug || typeof dto.helpful !== 'boolean') {
      throw new BadRequestException('slug and helpful (boolean) required');
    }

    const article = await this.prisma.kBArticle.findUnique({ where: { slug: dto.slug } });
    if (!article) throw new NotFoundException('Article not found');

    await this.prisma.kBArticle.update({
      where: { slug: dto.slug },
      data: dto.helpful ? { helpfulYes: { increment: 1 } } : { helpfulNo: { increment: 1 } },
    });

    return { success: true };
  }

  // ── Search ────────────────────────────────────────────────────────

  async search(query: KbSearchDto) {
    const q = query.q;
    const lang = query.lang ?? 'en';
    const category = query.category;
    const limit = query.limit ?? 10;

    const where: Record<string, unknown> = { status: 'published' };
    if (category) where.category = category;

    const allArticles = await this.prisma.kBArticle.findMany({
      where,
      orderBy: { views: 'desc' },
    });

    const searchTerm = q.toLowerCase();
    const results = allArticles
      .map((article) => {
        let title = '';
        let excerpt = '';
        let content = '';

        try {
          const titleObj = JSON.parse(article.title as string);
          const excerptObj = JSON.parse(article.excerpt as string);
          const contentObj = JSON.parse(article.content as string);
          title = titleObj[lang] || titleObj['en'] || '';
          excerpt = excerptObj[lang] || excerptObj['en'] || '';
          content = contentObj[lang] || contentObj['en'] || '';
        } catch {
          title = String(article.title);
          excerpt = String(article.excerpt);
          content = String(article.content);
        }

        const titleMatch = title.toLowerCase().includes(searchTerm) ? 10 : 0;
        const excerptMatch = excerpt.toLowerCase().includes(searchTerm) ? 5 : 0;
        const contentMatch = content.toLowerCase().includes(searchTerm) ? 2 : 0;
        const tagMatch = (() => {
          try {
            const tags: string[] = JSON.parse(article.tags as string);
            return tags.some((t) => t.toLowerCase().includes(searchTerm)) ? 3 : 0;
          } catch {
            return 0;
          }
        })();

        const rank = titleMatch + excerptMatch + contentMatch + tagMatch;
        return { id: article.id, slug: article.slug, category: article.category, title, excerpt, rank };
      })
      .filter((r) => r.rank > 0)
      .sort((a, b) => b.rank - a.rank)
      .slice(0, limit);

    // Log search
    await this.prisma.kBSearchLog.create({
      data: { query: q, language: lang, resultsCount: results.length },
    });

    // Update search appearances
    if (results.length > 0) {
      await this.prisma.kBArticle.updateMany({
        where: { id: { in: results.map((r) => r.id) } },
        data: { searchAppearances: { increment: 1 } },
      });
    }

    return { results, query: q, language: lang };
  }

  // ── KB Analytics ──────────────────────────────────────────────────

  async getAnalytics(days: number) {
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const topArticles = await this.prisma.kBArticle.findMany({
      where: { status: 'published' },
      orderBy: { views: 'desc' },
      take: 20,
      select: {
        id: true,
        slug: true,
        title: true,
        views: true,
        helpfulYes: true,
        helpfulNo: true,
        category: true,
      },
    });

    const failedSearchesRaw = await this.prisma.kBSearchLog.findMany({
      where: { ledToTicket: true, createdAt: { gte: since } },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { query: true, language: true, createdAt: true },
    });

    const failedSearchCounts: Record<string, number> = {};
    for (const s of failedSearchesRaw) {
      const key = s.query.toLowerCase();
      failedSearchCounts[key] = (failedSearchCounts[key] ?? 0) + 1;
    }
    const failedSearches = Object.entries(failedSearchCounts)
      .map(([query, count]) => ({ query, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 20);

    const noResultSearches = await this.prisma.kBSearchLog.findMany({
      where: { resultsCount: 0, createdAt: { gte: since } },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { query: true, language: true },
    });

    const noResultCounts: Record<string, { query: string; count: number; languages: Set<string> }> = {};
    for (const s of noResultSearches) {
      const key = s.query.toLowerCase();
      if (!noResultCounts[key]) noResultCounts[key] = { query: key, count: 0, languages: new Set() };
      noResultCounts[key].count++;
      noResultCounts[key].languages.add(s.language);
    }

    const contentGaps = Object.values(noResultCounts)
      .map(({ query, count, languages }) => ({ query, count, languages: Array.from(languages) }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 20);

    const unhelpfulArticles = topArticles
      .filter((a) => a.views > 50 && a.helpfulYes + a.helpfulNo > 0)
      .map((a) => ({
        ...a,
        helpfulnessScore: Math.round((a.helpfulYes / (a.helpfulYes + a.helpfulNo)) * 100) / 100,
      }))
      .sort((a, b) => a.helpfulnessScore - b.helpfulnessScore)
      .slice(0, 10);

    const articlesWithTitles = topArticles.map((a) => {
      let title = '';
      try {
        const t = JSON.parse(a.title as string);
        title = t['en'] || '';
      } catch {
        title = String(a.title);
      }
      return { ...a, title };
    });

    const [totalSearches, totalArticles] = await Promise.all([
      this.prisma.kBSearchLog.count({ where: { createdAt: { gte: since } } }),
      this.prisma.kBArticle.count({ where: { status: 'published' } }),
    ]);

    return {
      days,
      topArticles: articlesWithTitles,
      failedSearches,
      contentGaps,
      unhelpfulArticles,
      totalSearches,
      totalArticles,
    };
  }

  // ── SLA Report ────────────────────────────────────────────────────

  async getSlaReport(month: string) {
    // Parse month (YYYY-MM)
    const [year, mon] = month.split('-').map(Number);
    if (!year || !mon) {
      throw new BadRequestException('Invalid month format. Use YYYY-MM');
    }

    const startDate = new Date(year, mon - 1, 1);
    const endDate = new Date(year, mon, 1);

    const [
      totalTickets,
      resolvedTickets,
      breachedTickets,
      avgFirstResponseMinutes,
      avgResolutionMinutes,
      tierBreakdown,
    ] = await Promise.all([
      this.prisma.supportTicket.count({
        where: { createdAt: { gte: startDate, lt: endDate } },
      }),
      this.prisma.supportTicket.count({
        where: {
          status: { in: ['resolved', 'closed'] },
          resolvedAt: { gte: startDate, lt: endDate },
        },
      }),
      this.prisma.supportTicket.count({
        where: { slaBreached: true, createdAt: { gte: startDate, lt: endDate } },
      }),
      // Avg first response — use a simpler query since aggregate on DateTime isn't directly supported
      this.prisma.supportTicket.count({
        where: {
          firstResponseAt: { not: null },
          createdAt: { gte: startDate, lt: endDate },
        },
      }),
      // Avg resolution time in hours
      0,
      // Tier breakdown
      this.prisma.supportTicket.groupBy({
        by: ['slaTier'],
        _count: { id: true },
        where: { createdAt: { gte: startDate, lt: endDate } },
      }),
    ]);

    const resolutionRate = totalTickets > 0 ? Math.round((resolvedTickets / totalTickets) * 100) : 0;
    const breachRate = totalTickets > 0 ? Math.round((breachedTickets / totalTickets) * 100) : 0;

    return {
      month,
      overview: {
        totalTickets,
        resolvedTickets,
        resolutionRate,
        breachedTickets,
        breachRate,
      },
      tierBreakdown: tierBreakdown.map((t) => ({
        tier: t.slaTier,
        count: t._count.id,
      })),
      period: { start: startDate.toISOString(), end: endDate.toISOString() },
    };
  }

  // ── Helper: Parse Article ─────────────────────────────────────────

  private parseArticle(article: any, lang: string) {
    let title = '';
    let content = '';
    let excerpt = '';

    try {
      const t = JSON.parse(article.title as string);
      const c = JSON.parse(article.content as string);
      const e = JSON.parse(article.excerpt as string);
      title = t[lang] || t['en'] || '';
      content = c[lang] || c['en'] || '';
      excerpt = e[lang] || e['en'] || '';
    } catch {
      title = String(article.title);
      content = String(article.content);
      excerpt = String(article.excerpt);
    }

    let tags: string[] = [];
    try {
      tags = JSON.parse(article.tags as string);
    } catch {}

    return {
      id: article.id,
      slug: article.slug,
      category: article.category,
      subcategory: article.subcategory,
      title,
      content,
      excerpt,
      tags,
    };
  }
}
