import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ListArticlesDto } from './dto/list-articles.dto';
import { SearchArticlesDto } from './dto/search-articles.dto';
import { FeedbackDto } from './dto/feedback.dto';

/** Safely parse a JSON localisation field; fall back to raw string */
function parseLocalized(raw: string, lang: string): string {
  try {
    const obj = JSON.parse(raw) as Record<string, string>;
    return obj[lang] || obj['en'] || raw;
  } catch {
    return raw;
  }
}

/** Safely parse a JSON array field */
function parseJsonArray<T>(raw: string): T[] {
  try {
    return JSON.parse(raw) as T[];
  } catch {
    return [] as T[];
  }
}

@Injectable()
export class KbService {
  constructor(private prisma: PrismaService) {}

  // ── List / search articles ──────────────────────────────────────────

  async listArticles(dto: ListArticlesDto) {
    const { category, search, lang = 'en', page = 1, limit = 20 } = dto;

    const where: Record<string, unknown> = { status: 'published' };
    if (category) where.category = category;

    if (search) {
      where.OR = [
        { title: { contains: search } },
        { content: { contains: search } },
        { tags: { contains: search } },
      ];
    }

    const [articles, total] = await Promise.all([
      this.prisma.kBArticle.findMany({
        where,
        select: {
          id: true,
          slug: true,
          category: true,
          subcategory: true,
          title: true,
          excerpt: true,
          tags: true,
          featured: true,
          views: true,
          helpfulYes: true,
          helpfulNo: true,
          sortOrder: true,
          publishedAt: true,
          createdAt: true,
        },
        orderBy: [{ featured: 'desc' }, { sortOrder: 'asc' }, { publishedAt: 'desc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.kBArticle.count({ where }),
    ]);

    const localizedArticles = articles.map((a) => ({
      ...a,
      title: parseLocalized(a.title, lang),
      excerpt: parseLocalized(a.excerpt, lang),
      tags: parseJsonArray<string>(a.tags),
    }));

    return {
      articles: localizedArticles,
      pagination: {
        page,
        limit,
        total,
        hasMore: page * limit < total,
      },
    };
  }

  // ── Get article by slug ─────────────────────────────────────────────

  async getArticleBySlug(slug: string, lang = 'en') {
    const article = await this.prisma.kBArticle.findUnique({
      where: { slug },
      include: {
        author: { select: { id: true, name: true } },
        lastEditedBy: { select: { id: true, name: true } },
      },
    });

    if (!article || article.status !== 'published') {
      throw new NotFoundException('Article not found');
    }

    // Increment views
    await this.prisma.kBArticle.update({
      where: { id: article.id },
      data: { views: { increment: 1 } },
    });

    return {
      article: {
        id: article.id,
        slug: article.slug,
        category: article.category,
        subcategory: article.subcategory,
        title: parseLocalized(article.title, lang),
        content: parseLocalized(article.content, lang),
        excerpt: parseLocalized(article.excerpt, lang),
        tags: parseJsonArray<string>(article.tags),
        relatedArticleIds: parseJsonArray<string>(article.relatedArticleIds),
        featured: article.featured,
        views: article.views + 1,
        helpfulYes: article.helpfulYes,
        helpfulNo: article.helpfulNo,
        author: article.author,
        lastEditedBy: article.lastEditedBy,
        publishedAt: article.publishedAt,
        createdAt: article.createdAt,
        updatedAt: article.updatedAt,
      },
    };
  }

  // ── Get article by slug (for feedback) ──────────────────────────────

  async getArticleForFeedback(slug: string, lang = 'en') {
    const article = await this.prisma.kBArticle.findUnique({ where: { slug } });

    if (!article || article.status !== 'published') {
      throw new NotFoundException('Article not found');
    }

    // Increment views
    await this.prisma.kBArticle.update({
      where: { id: article.id },
      data: { views: { increment: 1 } },
    });

    return {
      article: {
        id: article.id,
        slug: article.slug,
        category: article.category,
        subcategory: article.subcategory,
        title: parseLocalized(article.title, lang),
        content: parseLocalized(article.content, lang),
        excerpt: parseLocalized(article.excerpt, lang),
        tags: parseJsonArray<string>(article.tags),
        views: article.views + 1,
        helpfulYes: article.helpfulYes,
        helpfulNo: article.helpfulNo,
        publishedAt: article.publishedAt,
      },
    };
  }

  // ── Helpful / not helpful feedback ──────────────────────────────────

  async submitFeedback(dto: FeedbackDto) {
    const article = await this.prisma.kBArticle.findUnique({ where: { slug: dto.slug } });
    if (!article) {
      throw new NotFoundException('Article not found');
    }

    await this.prisma.kBArticle.update({
      where: { slug: dto.slug },
      data: dto.helpful
        ? { helpfulYes: { increment: 1 } }
        : { helpfulNo: { increment: 1 } },
    });

    return { success: true };
  }

  // ── Search with relevance scoring ───────────────────────────────────

  async searchArticles(dto: SearchArticlesDto, userId?: string) {
    const { q, language = 'en', category, limit = 10 } = dto;

    const where: Record<string, unknown> = { status: 'published' };
    if (category) where.category = category;

    const allArticles = await this.prisma.kBArticle.findMany({
      where,
      orderBy: { views: 'desc' },
    });

    const searchTerm = q.toLowerCase();

    const results = allArticles
      .map((article) => {
        const title = parseLocalized(article.title, language);
        const excerpt = parseLocalized(article.excerpt, language);
        const content = parseLocalized(article.content, language);

        const titleMatch = title.toLowerCase().includes(searchTerm) ? 10 : 0;
        const excerptMatch = excerpt.toLowerCase().includes(searchTerm) ? 5 : 0;
        const contentMatch = content.toLowerCase().includes(searchTerm) ? 2 : 0;
        const tagMatch = (() => {
          try {
            const tags: string[] = JSON.parse(article.tags);
            return tags.some((t) => t.toLowerCase().includes(searchTerm)) ? 3 : 0;
          } catch { return 0; }
        })();

        const rank = titleMatch + excerptMatch + contentMatch + tagMatch;

        return {
          id: article.id,
          slug: article.slug,
          category: article.category,
          title,
          excerpt,
          rank,
        };
      })
      .filter((r) => r.rank > 0)
      .sort((a, b) => b.rank - a.rank)
      .slice(0, limit);

    // Log search
    await this.prisma.kBSearchLog.create({
      data: {
        query: q,
        language,
        resultsCount: results.length,
        userId: userId || null,
      },
    });

    // Update search appearances
    if (results.length > 0) {
      await this.prisma.kBArticle.updateMany({
        where: { id: { in: results.map((r) => r.id) } },
        data: { searchAppearances: { increment: 1 } },
      });
    }

    return { results, query: q, language };
  }
}
