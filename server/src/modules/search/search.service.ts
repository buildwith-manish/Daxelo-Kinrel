import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CacheService } from '../../common/cache/cache.service';
import { SearchQueryDto, SearchType } from './dto/search-query.dto';

/**
 * SearchResult — A single search result item.
 */
export interface SearchResultItem {
  id: string;
  type: 'user' | 'family';
  name: string;
  username: string | null;
  avatarUrl: string | null;
  bio: string | null;
  extra?: Record<string, unknown>;
  similarity?: number;
}

/**
 * SearchResponse — Paginated search results.
 */
export interface SearchResponse {
  results: SearchResultItem[];
  total: number;
  limit: number;
  offset: number;
  query: string;
  type: string;
}

@Injectable()
export class SearchService {
  private readonly logger = new Logger(SearchService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly cacheService: CacheService,
  ) {}

  /**
   * Unified search across users and families.
   *
   * For SQLite (dev): uses LIKE for case-insensitive search.
   * For PostgreSQL (prod): would use ILIKE + pg_trgm for fuzzy matching.
   *
   * Searches:
   *  - Users by username, displayName (name), bio
   *  - Families by name, kinFamilyId, gotra
   */
  async search(dto: SearchQueryDto): Promise<SearchResponse> {
    const { q, type } = dto;
    const limit = dto.limit ?? 20;
    const offset = dto.offset ?? 0;
    const query = q.trim();

    // Check cache first
    const cacheKey = `search:${query}:${type}:${limit}:${offset}`;
    const cached = this.cacheService.get<SearchResponse>(cacheKey);
    if (cached.hit && cached.value) {
      return cached.value;
    }

    const results: SearchResultItem[] = [];
    let total = 0;

    // ── Search Users ──
    if (type === SearchType.ALL || type === SearchType.USERS) {
      const [users, userCount] = await Promise.all([
        this.prisma.user.findMany({
          where: {
            OR: [
              { username: { contains: query } },
              { name: { contains: query } },
              { bio: { contains: query } },
            ],
            profileVisibility: { not: 'private' },
          },
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            photoThumb: true,
            bio: true,
            profileVisibility: true,
          },
          take: type === SearchType.USERS ? limit : Math.ceil(limit / 2),
          skip: type === SearchType.USERS ? offset : 0,
          orderBy: { createdAt: 'desc' },
        }),
        this.prisma.user.count({
          where: {
            OR: [
              { username: { contains: query } },
              { name: { contains: query } },
              { bio: { contains: query } },
            ],
            profileVisibility: { not: 'private' },
          },
        }),
      ]);

      for (const user of users) {
        results.push({
          id: user.id,
          type: 'user',
          name: user.name || 'Unknown',
          username: user.username,
          avatarUrl: user.photoThumb || user.avatarUrl,
          bio: user.bio,
        });
      }

      total += userCount;
    }

    // ── Search Families ──
    if (type === SearchType.ALL || type === SearchType.FAMILIES) {
      const [families, familyCount] = await Promise.all([
        this.prisma.family.findMany({
          where: {
            OR: [
              { name: { contains: query } },
              { kinFamilyId: { contains: query } },
              { gotra: { contains: query } },
            ],
            privacyMode: { not: 'private' },
          },
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            gotra: true,
            kinFamilyId: true,
            memberCount: true,
          },
          take: type === SearchType.FAMILIES ? limit : Math.ceil(limit / 2),
          skip: type === SearchType.FAMILIES ? offset : 0,
          orderBy: { memberCount: 'desc' },
        }),
        this.prisma.family.count({
          where: {
            OR: [
              { name: { contains: query } },
              { kinFamilyId: { contains: query } },
              { gotra: { contains: query } },
            ],
            privacyMode: { not: 'private' },
          },
        }),
      ]);

      for (const family of families) {
        results.push({
          id: family.id,
          type: 'family',
          name: family.name,
          username: family.username,
          avatarUrl: family.avatarUrl,
          bio: null,
          extra: {
            kinFamilyId: family.kinFamilyId,
            gotra: family.gotra,
            memberCount: family.memberCount,
          },
        });
      }

      total += familyCount;
    }

    // Sort results: exact username match first, then by name similarity
    results.sort((a, b) => {
      const aExact = a.username?.toLowerCase() === query.toLowerCase() ? 0 : 1;
      const bExact = b.username?.toLowerCase() === query.toLowerCase() ? 0 : 1;
      if (aExact !== bExact) return aExact - bExact;

      const aStartsWith = a.name.toLowerCase().startsWith(query.toLowerCase()) ? 0 : 1;
      const bStartsWith = b.name.toLowerCase().startsWith(query.toLowerCase()) ? 0 : 1;
      return aStartsWith - bStartsWith;
    });

    // Apply pagination to combined results for 'all' type
    const paginatedResults =
      type === SearchType.ALL
        ? results.slice(offset, offset + limit)
        : results;

    const response: SearchResponse = {
      results: paginatedResults,
      total,
      limit,
      offset,
      query,
      type: type ?? SearchType.ALL,
    };

    // Cache for 30 seconds (short TTL for search results)
    this.cacheService.set(cacheKey, response, 30);

    return response;
  }
}
