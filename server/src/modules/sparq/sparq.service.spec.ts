import { Test, TestingModule } from '@nestjs/testing';
import { SparqService } from './sparq.service';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { ConfigService } from '@nestjs/config';
import {
  NotFoundException,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';

describe('SparqService', () => {
  let service: SparqService;
  let prisma: PrismaService;
  let gateway: KinrelGateway;

  const mockPrisma = {
    follow: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
    },
    familyMember: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
    },
    sparq: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      deleteMany: jest.fn(),
      count: jest.fn(),
    },
    sparqView: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    sparqEcho: {
      findUnique: jest.fn(),
      create: jest.fn(),
      delete: jest.fn(),
    },
  };

  const mockGateway = {
    emitToUser: jest.fn(),
  };

  const mockConfigService = {
    get: jest.fn().mockReturnValue(undefined), // No Cloudinary config by default
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SparqService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: KinrelGateway, useValue: mockGateway },
        { provide: ConfigService, useValue: mockConfigService },
      ],
    }).compile();

    service = module.get<SparqService>(SparqService);
    prisma = module.get<PrismaService>(PrismaService);
    gateway = module.get<KinrelGateway>(KinrelGateway);

    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ─── getFeed ───────────────────────────────────────────────────────
  describe('getFeed', () => {
    const userId = 'user-1';

    it('should return empty if no follows and no families', async () => {
      mockPrisma.follow.findMany.mockResolvedValue([]);
      mockPrisma.familyMember.findMany.mockResolvedValue([]);

      const result = await service.getFeed(userId, { page: 1, limit: 20 });

      expect(result.items).toEqual([]);
      expect(result.total).toBe(0);
    });

    it('should group by user with unseen first', async () => {
      // User follows user-2 and user-3
      mockPrisma.follow.findMany
        .mockResolvedValueOnce([
          { followingId: 'user-2' },
          { followingId: 'user-3' },
        ]) // for getFeed
        .mockResolvedValueOnce([]) // mutual followers
        .mockResolvedValueOnce([]) // mutual forward
        .mockResolvedValueOnce([]); // mutual reverse

      mockPrisma.familyMember.findMany
        .mockResolvedValueOnce([{ familyId: 'fam-1' }]) // family memberships
        .mockResolvedValueOnce([{ userId: 'user-2' }, { userId: 'user-3' }]); // family member records

      const now = new Date();
      const futureDate = new Date(now.getTime() + 86400000);

      // user-2's sparq: unseen (no views)
      // user-3's sparq: seen (has views)
      mockPrisma.sparq.findMany.mockResolvedValue([
        {
          id: 's1',
          userId: 'user-3',
          expiresAt: futureDate,
          audience: 'PUBLIC',
          createdAt: new Date(now.getTime() - 1000),
          isTimeCapsule: false,
          isRevealed: true,
          views: [{ id: 'v1' }], // seen
          user: { id: 'user-3', name: 'User 3', username: 'u3', avatarUrl: null, photoThumb: null },
        },
        {
          id: 's2',
          userId: 'user-2',
          expiresAt: futureDate,
          audience: 'PUBLIC',
          createdAt: new Date(now.getTime() - 2000),
          isTimeCapsule: false,
          isRevealed: true,
          views: [], // unseen
          user: { id: 'user-2', name: 'User 2', username: 'u2', avatarUrl: null, photoThumb: null },
        },
      ]);

      const result = await service.getFeed(userId, { page: 1, limit: 20 });

      expect(result.items.length).toBeGreaterThan(0);
      // Unseen (allSeen=false) should come first
      const unseenIndex = result.items.findIndex((g: any) => !g.allSeen);
      const seenIndex = result.items.findIndex((g: any) => g.allSeen);
      if (unseenIndex !== -1 && seenIndex !== -1) {
        expect(unseenIndex).toBeLessThan(seenIndex);
      }
    });
  });

  // ─── createSparq ───────────────────────────────────────────────────
  describe('createSparq', () => {
    const userId = 'user-1';

    it('should set 24h expiry', async () => {
      const beforeCreate = Date.now();
      mockPrisma.sparq.create.mockImplementation(({ data }) =>
        Promise.resolve({ id: 's1', ...data }),
      );

      const result = await service.createSparq(userId, {
        type: 'TEXT',
        text: 'Hello!',
      });

      const expiresAt = new Date(result.expiresAt).getTime();
      const expectedExpiry = beforeCreate + 24 * 60 * 60 * 1000;
      // Allow 2-second tolerance
      expect(expiresAt).toBeGreaterThanOrEqual(expectedExpiry - 2000);
      expect(expiresAt).toBeLessThanOrEqual(expectedExpiry + 2000);
    });

    it('should require media for IMAGE type', async () => {
      await expect(
        service.createSparq(userId, { type: 'IMAGE' }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createSparq(userId, { type: 'IMAGE' }),
      ).rejects.toThrow('Media file is required for type IMAGE');
    });

    it('should require media for VIDEO type', async () => {
      await expect(
        service.createSparq(userId, { type: 'VIDEO' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should require media for VOICE type', async () => {
      await expect(
        service.createSparq(userId, { type: 'VOICE' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should validate time capsule — revealAt required', async () => {
      await expect(
        service.createSparq(userId, {
          type: 'TEXT',
          isTimeCapsule: true,
        }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createSparq(userId, {
          type: 'TEXT',
          isTimeCapsule: true,
        }),
      ).rejects.toThrow('revealAt is required for Time Capsule Sparqs');
    });

    it('should validate time capsule — revealAt must be future', async () => {
      const pastDate = new Date(Date.now() - 86400000).toISOString();
      await expect(
        service.createSparq(userId, {
          type: 'TEXT',
          isTimeCapsule: true,
          revealAt: pastDate,
        }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createSparq(userId, {
          type: 'TEXT',
          isTimeCapsule: true,
          revealAt: pastDate,
        }),
      ).rejects.toThrow('revealAt must be a future timestamp');
    });

    it('should create sparq successfully with valid TEXT input', async () => {
      mockPrisma.sparq.create.mockResolvedValue({
        id: 's1',
        userId,
        type: 'TEXT',
        text: 'Hello!',
      });

      const result = await service.createSparq(userId, {
        type: 'TEXT',
        text: 'Hello!',
      });

      expect(result.id).toBe('s1');
      expect(mockPrisma.sparq.create).toHaveBeenCalled();
    });
  });

  // ─── toggleEcho ────────────────────────────────────────────────────
  describe('toggleEcho', () => {
    const sparqId = 's1';
    const userId = 'user-1';

    it('should throw NotFoundException if sparq not found', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue(null);

      await expect(service.toggleEcho(sparqId, userId)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should add echo if not existing', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: sparqId,
        echoCount: 5,
      });
      mockPrisma.sparqEcho.findUnique.mockResolvedValue(null);
      mockPrisma.sparqEcho.create.mockResolvedValue({ id: 'e1', sparqId, userId });
      mockPrisma.sparq.update.mockResolvedValue({ id: sparqId, echoCount: 6 });

      const result = await service.toggleEcho(sparqId, userId);

      expect(result.isEchoed).toBe(true);
      expect(result.echoCount).toBe(6);
      expect(mockPrisma.sparq.update).toHaveBeenCalledWith({
        where: { id: sparqId },
        data: { echoCount: { increment: 1 } },
      });
    });

    it('should remove echo if existing', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: sparqId,
        echoCount: 5,
      });
      mockPrisma.sparqEcho.findUnique.mockResolvedValue({
        id: 'e1',
        sparqId,
        userId,
      });
      mockPrisma.sparqEcho.delete.mockResolvedValue({ id: 'e1' });
      mockPrisma.sparq.update.mockResolvedValue({ id: sparqId, echoCount: 4 });

      const result = await service.toggleEcho(sparqId, userId);

      expect(result.isEchoed).toBe(false);
      expect(result.echoCount).toBe(4);
      expect(mockPrisma.sparq.update).toHaveBeenCalledWith({
        where: { id: sparqId },
        data: { echoCount: { decrement: 1 } },
      });
    });
  });

  // ─── getChain ──────────────────────────────────────────────────────
  describe('getChain', () => {
    it('should throw NotFoundException if sparq not found', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue(null);

      await expect(service.getChain('s1')).rejects.toThrow(NotFoundException);
    });

    it('should find root and return ordered chain', async () => {
      // A child sparq whose parent is the root
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: 's2',
        parentSparqId: 's1',
      });

      const chain = [
        { id: 's1', parentSparqId: null, chainOrder: 1 },
        { id: 's2', parentSparqId: 's1', chainOrder: 2 },
      ];
      mockPrisma.sparq.findMany.mockResolvedValue(chain);

      const result = await service.getChain('s2');

      expect(mockPrisma.sparq.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            OR: [{ id: 's1' }, { parentSparqId: 's1' }],
          },
          orderBy: { chainOrder: 'asc' },
        }),
      );
      expect(result).toEqual(chain);
    });

    it('should use sparqId as root if no parent', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: 's1',
        parentSparqId: null,
      });

      const chain = [{ id: 's1', parentSparqId: null, chainOrder: 1 }];
      mockPrisma.sparq.findMany.mockResolvedValue(chain);

      const result = await service.getChain('s1');

      expect(mockPrisma.sparq.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            OR: [{ id: 's1' }, { parentSparqId: 's1' }],
          },
        }),
      );
    });
  });

  // ─── markViewed ────────────────────────────────────────────────────
  describe('markViewed', () => {
    const sparqId = 's1';
    const viewerId = 'user-1';

    it('should throw NotFoundException if sparq not found', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue(null);

      await expect(service.markViewed(sparqId, viewerId)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should increment viewCount on first view only', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({ id: sparqId });
      mockPrisma.sparqView.findUnique.mockResolvedValue(null);
      mockPrisma.sparqView.create.mockResolvedValue({ id: 'v1' });
      mockPrisma.sparq.update.mockResolvedValue({ id: sparqId, viewCount: 1 });

      const result = await service.markViewed(sparqId, viewerId);

      expect(mockPrisma.sparqView.create).toHaveBeenCalledWith({
        data: { sparqId, viewerId },
      });
      expect(mockPrisma.sparq.update).toHaveBeenCalledWith({
        where: { id: sparqId },
        data: { viewCount: { increment: 1 } },
      });
      expect(result).toEqual({ success: true });
    });

    it('should not increment viewCount on repeat view', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({ id: sparqId });
      mockPrisma.sparqView.findUnique.mockResolvedValue({
        id: 'v1',
        sparqId,
        viewerId,
      });
      mockPrisma.sparqView.update.mockResolvedValue({ id: 'v1' });

      const result = await service.markViewed(sparqId, viewerId);

      expect(mockPrisma.sparqView.update).toHaveBeenCalledWith({
        where: { id: 'v1' },
        data: { viewedAt: expect.any(Date) },
      });
      expect(mockPrisma.sparq.update).not.toHaveBeenCalled();
      expect(result).toEqual({ success: true });
    });
  });

  // ─── getViewers ────────────────────────────────────────────────────
  describe('getViewers', () => {
    const sparqId = 's1';

    it('should throw NotFoundException if sparq not found', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue(null);

      await expect(service.getViewers(sparqId, 'user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw ForbiddenException if not creator', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: sparqId,
        userId: 'user-2',
      });

      await expect(service.getViewers(sparqId, 'user-1')).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should return viewers if creator', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: sparqId,
        userId: 'user-1',
      });
      mockPrisma.sparqView.findMany.mockResolvedValue([
        {
          id: 'v1',
          sparqId,
          viewerId: 'user-2',
          viewedAt: new Date(),
          viewer: {
            id: 'user-2',
            name: 'Viewer 1',
            username: 'viewer1',
            avatarUrl: null,
            photoThumb: null,
          },
        },
      ]);

      const result = await service.getViewers(sparqId, 'user-1');

      expect(result).toHaveLength(1);
      expect(result[0]).toMatchObject({
        id: 'user-2',
        name: 'Viewer 1',
      });
    });
  });

  // ─── deleteSparq ───────────────────────────────────────────────────
  describe('deleteSparq', () => {
    it('should throw NotFoundException if sparq not found', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue(null);

      await expect(service.deleteSparq('s1', 'user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw ForbiddenException if not owner', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: 's1',
        userId: 'user-2',
      });

      await expect(service.deleteSparq('s1', 'user-1')).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should delete if owner', async () => {
      mockPrisma.sparq.findUnique.mockResolvedValue({
        id: 's1',
        userId: 'user-1',
      });
      mockPrisma.sparq.delete.mockResolvedValue({ id: 's1' });

      const result = await service.deleteSparq('s1', 'user-1');

      expect(mockPrisma.sparq.delete).toHaveBeenCalledWith({
        where: { id: 's1' },
      });
      expect(result).toEqual({ success: true });
    });
  });

  // ─── cleanupExpiredSparqs ──────────────────────────────────────────
  describe('cleanupExpiredSparqs', () => {
    it('should delete expired sparqs', async () => {
      mockPrisma.sparq.deleteMany.mockResolvedValue({ count: 3 });

      await service.cleanupExpiredSparqs();

      expect(mockPrisma.sparq.deleteMany).toHaveBeenCalledWith({
        where: { expiresAt: { lte: expect.any(Date) } },
      });
    });

    it('should handle zero expired sparqs gracefully', async () => {
      mockPrisma.sparq.deleteMany.mockResolvedValue({ count: 0 });

      await service.cleanupExpiredSparqs();

      expect(mockPrisma.sparq.deleteMany).toHaveBeenCalled();
    });
  });

  // ─── revealTimeCapsuleSparqs ───────────────────────────────────────
  describe('revealTimeCapsuleSparqs', () => {
    it('should reveal time capsules past their revealAt', async () => {
      const sparq1 = { id: 's1', userId: 'user-1', isTimeCapsule: true, isRevealed: false, revealAt: new Date() };
      mockPrisma.sparq.findMany.mockResolvedValue([sparq1]);
      mockPrisma.sparq.update.mockResolvedValue({ ...sparq1, isRevealed: true });

      await service.revealTimeCapsuleSparqs();

      expect(mockPrisma.sparq.findMany).toHaveBeenCalledWith({
        where: {
          isTimeCapsule: true,
          isRevealed: false,
          revealAt: { lte: expect.any(Date) },
        },
      });
      expect(mockPrisma.sparq.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: { isRevealed: true },
      });
      expect(gateway.emitToUser).toHaveBeenCalledWith(
        'user-1',
        'sparq:timecapsule-revealed',
        { sparqId: 's1' },
      );
    });

    it('should do nothing if no time capsules to reveal', async () => {
      mockPrisma.sparq.findMany.mockResolvedValue([]);

      await service.revealTimeCapsuleSparqs();

      expect(mockPrisma.sparq.update).not.toHaveBeenCalled();
      expect(gateway.emitToUser).not.toHaveBeenCalled();
    });
  });
});
