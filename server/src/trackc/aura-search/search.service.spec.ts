// =============================================================================
// Track C v2.0 — SearchService Tests
// =============================================================================
// Exercises search() (query validation + raw SQL + family scoping),
// reindexFamily() (multi-entity rebuild), and the upsertIndex idempotency
// that prevents duplicate SearchIndex rows.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { SearchService } from './search.service';
import { BadRequestException } from '@nestjs/common';

describe('SearchService', () => {
  let prisma: any;
  let membership: any;
  let service: SearchService;

  beforeEach(() => {
    prisma = new PrismaService();
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).create.mockResolvedValue({});
        (m as any).update.mockResolvedValue({});
        (m as any).upsert.mockResolvedValue({});
        (m as any).count.mockResolvedValue(0);
        (m as any).deleteMany.mockResolvedValue({ count: 0 });
      }
    }
    prisma.$queryRawUnsafe = jest.fn().mockResolvedValue([]);
    prisma.$queryRaw = jest.fn().mockResolvedValue([]);

    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1', role: 'member' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
    };

    service = new SearchService(prisma as any, membership as any);
  });

  // ── search() ─────────────────────────────────────────────────────────
  describe('search()', () => {
    it('throws BadRequestException for an empty query', async () => {
      await expect(
        service.search({ familyId: 'fam_1', userId: 'u_1', query: '   ' }),
      ).rejects.toThrow(BadRequestException);

      // Must reject BEFORE the membership check (cheap-fail)
      expect(membership.requireMember).not.toHaveBeenCalled();
    });

    it('returns results matching the query (raw SQL path)', async () => {
      const mockResults = [
        { id: 's_1', entityType: 'decision', entityId: 'd_1', title: 'Vacation', rank_score: 0.9 },
        { id: 's_2', entityType: 'memory', entityId: 'mem_1', title: 'Vacation memory', rank_score: 0.7 },
      ];
      prisma.$queryRawUnsafe.mockResolvedValueOnce(mockResults);

      const result = await service.search({
        familyId: 'fam_1',
        userId: 'u_1',
        query: 'vacation',
      });

      expect(result.count).toBe(2);
      expect(result.items).toEqual(mockResults);
      expect(result.query).toBe('vacation');
      // The raw query must include the familyId parameter (family scoping)
      expect(prisma.$queryRawUnsafe).toHaveBeenCalledWith(
        expect.any(String),
        'vacation',         // sanitized query
        'fam_1',            // familyId
        expect.any(Number), // limit
      );
    });

    it('scopes results to the requesting family (familyId in WHERE clause)', async () => {
      prisma.$queryRawUnsafe.mockResolvedValueOnce([]);
      await service.search({
        familyId: 'fam_other',
        userId: 'u_1',
        query: 'test',
      });

      // Verify the SQL passed to $queryRawUnsafe includes the familyId filter
      const sqlArg = prisma.$queryRawUnsafe.mock.calls[0][0] as string;
      expect(sqlArg).toContain('"familyId" = $2');
      // And the familyId was passed as the 2nd parameter
      expect(prisma.$queryRawUnsafe.mock.calls[0][2]).toBe('fam_other');
    });

    it('caps the limit at 100 (server-side maximum)', async () => {
      prisma.$queryRawUnsafe.mockResolvedValueOnce([]);
      await service.search({
        familyId: 'fam_1',
        userId: 'u_1',
        query: 'test',
        limit: 99999,
      });
      // The 3rd argument to $queryRawUnsafe is the limit
      expect(prisma.$queryRawUnsafe.mock.calls[0][3]).toBe(100);
    });

    it('strips ts-query special characters before sending to the DB', async () => {
      prisma.$queryRawUnsafe.mockResolvedValueOnce([]);
      await service.search({
        familyId: 'fam_1',
        userId: 'u_1',
        query: 'foo&bar|baz!:test*',
      });
      // The sanitized query is the 2nd positional arg. The sanitizer replaces
      // ts-query special chars (& | ! ( ) : *) with spaces, then trims edges.
      expect(prisma.$queryRawUnsafe.mock.calls[0][1]).toBe('foo bar baz  test');
    });

    it('rejects when the user is not a member of the family', async () => {
      membership.requireMember.mockRejectedValueOnce(new Error('not a member'));
      await expect(
        service.search({ familyId: 'fam_1', userId: 'outsider', query: 'test' }),
      ).rejects.toThrow('not a member');
    });
  });

  // ── suggest() ────────────────────────────────────────────────────────
  describe('suggest()', () => {
    it('returns empty suggestions for short queries (<2 chars)', async () => {
      const result = await service.suggest({ familyId: 'fam_1', userId: 'u_1', q: 'a' });
      expect(result.suggestions).toEqual([]);
      expect(prisma.$queryRawUnsafe).not.toHaveBeenCalled();
    });

    it('returns title suggestions matching the prefix', async () => {
      prisma.$queryRawUnsafe.mockResolvedValueOnce([
        { title: 'Vacation plan', entityType: 'decision' },
        { title: 'Vacation budget', entityType: 'memory' },
      ]);
      const result = await service.suggest({ familyId: 'fam_1', userId: 'u_1', q: 'vac' });
      expect(result.suggestions).toEqual(['Vacation plan', 'Vacation budget']);
    });
  });

  // ── upsertIndex() ────────────────────────────────────────────────────
  describe('upsertIndex()', () => {
    it('upserts a SearchIndex row keyed by (familyId, entityType, entityId)', async () => {
      prisma.searchIndex.upsert.mockResolvedValueOnce({ id: 'idx_1' });

      await service.upsertIndex({
        familyId: 'fam_1',
        entityType: 'decision',
        entityId: 'd_1',
        title: 'My decision',
        body: 'body text',
        keywords: ['vote'],
      });

      expect(prisma.searchIndex.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            familyId_entityType_entityId: {
              familyId: 'fam_1',
              entityType: 'decision',
              entityId: 'd_1',
            },
          },
        }),
      );
    });

    it('applies a per-entity-type boostedScore when none is provided', async () => {
      prisma.searchIndex.upsert.mockResolvedValueOnce({ id: 'idx_1' });

      await service.upsertIndex({
        familyId: 'fam_1',
        entityType: 'decision',
        entityId: 'd_1',
        title: 't',
        body: 'b',
      });

      const call = prisma.searchIndex.upsert.mock.calls[0][0];
      // decision has a boosted score of 2.0 per the service's computeBoostedScore
      expect(call.create.boostedScore).toBe(2.0);
    });
  });

  // ── removeIndex() ────────────────────────────────────────────────────
  describe('removeIndex()', () => {
    it('deletes by (familyId, entityType, entityId) tuple', async () => {
      prisma.searchIndex.deleteMany.mockResolvedValueOnce({ count: 1 });

      const result = await service.removeIndex('fam_1', 'decision', 'd_1');

      expect(result.count).toBe(1);
      expect(prisma.searchIndex.deleteMany).toHaveBeenCalledWith({
        where: { familyId: 'fam_1', entityType: 'decision', entityId: 'd_1' },
      });
    });
  });

  // ── reindexFamily() ──────────────────────────────────────────────────
  describe('reindexFamily()', () => {
    it('rebuilds the SearchIndex for the family across all entity types', async () => {
      // Decisions
      prisma.familyDecision.findMany.mockResolvedValueOnce([
        {
          id: 'd_1',
          title: 'Decision 1',
          description: 'desc',
          type: 'simple_vote',
          status: 'open',
          createdAt: new Date(),
        },
      ]);
      // Decision memory
      prisma.decisionMemory.findMany.mockResolvedValueOnce([
        {
          id: 'mem_1',
          decisionId: 'd_1',
          summaryText: 'A summary',
          keyTakeaways: ['takeaway 1'],
          searchKeywords: ['kw'],
        },
      ]);
      // Timeline events
      prisma.aURATimelineEvent.findMany.mockResolvedValueOnce([
        { id: 'ev_1', title: 'Event 1', description: 'desc', kind: 'decision_created', occurredAt: new Date() },
      ]);
      // Constitution articles
      prisma.constitutionArticle.findMany.mockResolvedValueOnce([
        { id: 'a_1', title: 'Article 1', intent: 'i', clauses: [{ id: 'cl_1', text: 'clause' }] },
      ]);
      // Meeting artifacts
      prisma.meetingArtifact.findMany.mockResolvedValueOnce([
        { id: 'art_1', title: 'Meeting 1', draftMinutesMd: 'minutes', heldAt: new Date() },
      ]);

      // All upserts succeed
      prisma.searchIndex.upsert.mockResolvedValue({ id: 'idx' });

      const result = await service.reindexFamily('fam_1');

      // Decisions(1) + memories(1) + events(1) + articles(1) + clauses(1) + artifacts(1) = 6
      expect(result.reindexed).toBe(6);
      // searchIndex.upsert should have been called once per entity
      expect(prisma.searchIndex.upsert).toHaveBeenCalledTimes(6);
    });

    it('is idempotent — reindexing twice produces no duplicate SearchIndex rows (uses upsert)', async () => {
      prisma.familyDecision.findMany.mockResolvedValueOnce([
        { id: 'd_1', title: 'D', description: '', type: 'simple_vote', status: 'open', createdAt: new Date() },
      ]);
      prisma.decisionMemory.findMany.mockResolvedValueOnce([]);
      prisma.aURATimelineEvent.findMany.mockResolvedValueOnce([]);
      prisma.constitutionArticle.findMany.mockResolvedValueOnce([]);
      prisma.meetingArtifact.findMany.mockResolvedValueOnce([]);

      await service.reindexFamily('fam_1');

      // The upsert must use a composite-key where clause so re-running
      // overwrites the existing row instead of creating a new one.
      const upsertCall = prisma.searchIndex.upsert.mock.calls[0][0];
      expect(upsertCall.where.familyId_entityType_entityId).toEqual({
        familyId: 'fam_1',
        entityType: 'decision',
        entityId: 'd_1',
      });
    });

    it('returns 0 reindexed when the family has no entities', async () => {
      prisma.familyDecision.findMany.mockResolvedValueOnce([]);
      prisma.decisionMemory.findMany.mockResolvedValueOnce([]);
      prisma.aURATimelineEvent.findMany.mockResolvedValueOnce([]);
      prisma.constitutionArticle.findMany.mockResolvedValueOnce([]);
      prisma.meetingArtifact.findMany.mockResolvedValueOnce([]);

      const result = await service.reindexFamily('fam_empty');
      expect(result.reindexed).toBe(0);
      expect(prisma.searchIndex.upsert).not.toHaveBeenCalled();
    });
  });
});
