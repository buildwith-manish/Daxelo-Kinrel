import { Test, TestingModule } from '@nestjs/testing';
import { StoriesService } from './stories.service';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { ConfigService } from '@nestjs/config';
import {
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';

describe('StoriesService', () => {
  let service: StoriesService;
  let prisma: PrismaService;

  const mockPrisma = {
    story: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      delete: jest.fn(),
      deleteMany: jest.fn(),
    },
    storyView: {
      upsert: jest.fn(),
    },
    familyMember: {
      findFirst: jest.fn(),
    },
  };

  const mockGateway = {
    emitToUser: jest.fn(),
    emitToFamily: jest.fn(),
  };

  const mockConfigService = {
    get: jest.fn().mockReturnValue('default-value'),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StoriesService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: KinrelGateway, useValue: mockGateway },
        { provide: ConfigService, useValue: mockConfigService },
      ],
    }).compile();

    service = module.get<StoriesService>(StoriesService);
    prisma = module.get<PrismaService>(PrismaService);

    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ─── create ────────────────────────────────────────────────────────
  describe('create', () => {
    it('should create story with user ID', async () => {
      const futureDate = new Date(Date.now() + 86400000).toISOString();
      const storyData = {
        id: 'story-1',
        userId: 'user-1',
        familyId: null,
        caption: 'Test story',
        mediaUrl: '',
        mediaType: 'text',
        bgGradient: null,
        expiresAt: futureDate,
        createdAt: new Date(),
        updatedAt: new Date(),
        user: { id: 'user-1', name: 'User 1', username: 'user1', avatarUrl: null },
      };

      mockPrisma.story.create.mockResolvedValue(storyData);

      const result = await service.create('user-1', {
        caption: 'Test story',
        mediaType: 'text',
        expiresAt: futureDate,
      });

      expect(mockPrisma.story.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          userId: 'user-1',
          caption: 'Test story',
          mediaType: 'text',
        }),
        include: {
          user: {
            select: {
              id: true,
              name: true,
              username: true,
              avatarUrl: true,
            },
          },
        },
      });
      expect(result.id).toBe('story-1');
    });

    it('should create story with default 24h expiry', async () => {
      const customExpiry = new Date(Date.now() + 7200000).toISOString();
      const storyData = {
        id: 'story-2',
        userId: 'user-1',
        familyId: null,
        caption: null,
        mediaUrl: '',
        mediaType: 'text',
        bgGradient: null,
        expiresAt: customExpiry,
        createdAt: new Date(),
        updatedAt: new Date(),
        user: { id: 'user-1', name: 'User 1', username: 'user1', avatarUrl: null },
      };

      mockPrisma.story.create.mockResolvedValue(storyData);

      await service.create('user-1', {
        expiresAt: customExpiry,
      });

      // Service always sets expiresAt to now + 24h
      expect(mockPrisma.story.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            // expiresAt is set to now + 24h by the service, not from dto
            expiresAt: expect.any(Date),
          }),
        }),
      );
    });
  });

  // ─── Task 2b: audience + thumbnailUrl ──────────────────────────────
  describe('create — audience / thumbnailUrl (task 2b)', () => {
    const base = {
      id: 'story-9', userId: 'user-1', familyId: null, caption: null,
      mediaUrl: '', mediaType: 'text', bgGradient: null,
      audience: 'PUBLIC', thumbnailUrl: null,
      expiresAt: new Date(), createdAt: new Date(), updatedAt: new Date(),
    };

    it('persists audience from the DTO and defaults to PUBLIC', async () => {
      mockPrisma.story.create.mockResolvedValue({ ...base, audience: 'FAMILY_ONLY' });
      await service.create('user-1', { audience: 'FAMILY_ONLY' } as any);
      expect(mockPrisma.story.create.mock.calls[0][0].data.audience).toBe('FAMILY_ONLY');

      mockPrisma.story.create.mockClear();
      mockPrisma.story.create.mockResolvedValue(base);
      await service.create('user-1', {} as any);
      expect(mockPrisma.story.create.mock.calls[0][0].data.audience).toBe('PUBLIC');
    });

    it('persists and returns the uploaded thumbnailUrl', async () => {
      (service as any).uploadMediaToCloudinary = jest
        .fn()
        .mockResolvedValue({ mediaUrl: 'https://m/1.jpg', thumbnailUrl: 'https://m/1_t.jpg' });
      mockPrisma.story.create.mockResolvedValue({
        ...base, mediaUrl: 'https://m/1.jpg', mediaType: 'image', thumbnailUrl: 'https://m/1_t.jpg',
      });
      const file = { size: 10, mimetype: 'image/jpeg', buffer: Buffer.from('x') } as any;

      const result = await service.create('user-1', {} as any, file);

      expect(mockPrisma.story.create.mock.calls[0][0].data.thumbnailUrl).toBe('https://m/1_t.jpg');
      expect(result.thumbnailUrl).toBe('https://m/1_t.jpg');
      expect(result.audience).toBe('PUBLIC');
    });

    it('stores thumbnailUrl null for text stories', async () => {
      mockPrisma.story.create.mockResolvedValue(base);
      await service.create('user-1', {} as any);
      expect(mockPrisma.story.create.mock.calls[0][0].data.thumbnailUrl).toBeNull();
    });
  });

  describe('findByFamily — audience filter (task 2b)', () => {
    it('family member: no audience restriction (sees PUBLIC + FAMILY_ONLY)', async () => {
      mockPrisma.familyMember.findFirst.mockResolvedValue({ id: 'fm1' });
      mockPrisma.story.findMany.mockResolvedValue([]);
      await service.findByFamily('fam-1', 'viewer-1');
      const where = mockPrisma.story.findMany.mock.calls[0][0].where;
      expect(where.familyId).toBe('fam-1');
      expect(where).not.toHaveProperty('audience');
    });

    it('non-member: PUBLIC only', async () => {
      mockPrisma.familyMember.findFirst.mockResolvedValue(null);
      mockPrisma.story.findMany.mockResolvedValue([]);
      await service.findByFamily('fam-1', 'outsider');
      expect(mockPrisma.story.findMany.mock.calls[0][0].where.audience).toBe('PUBLIC');
    });

    it('no user id: PUBLIC only', async () => {
      mockPrisma.story.findMany.mockResolvedValue([]);
      await service.findByFamily('fam-1');
      expect(mockPrisma.story.findMany.mock.calls[0][0].where.audience).toBe('PUBLIC');
    });
  });

  // ─── findByFamily ──────────────────────────────────────────────────
  describe('findByFamily', () => {
    it('should return only non-expired stories grouped by user with hasUnviewed flag', async () => {
      const now = new Date();
      const futureDate = new Date(now.getTime() + 86400000);

      const stories = [
        {
          id: 's1',
          userId: 'user-1',
          familyId: 'fam-1',
          caption: 'Story 1',
          mediaUrl: '',
          mediaType: 'text',
          bgGradient: null,
          expiresAt: futureDate,
          createdAt: now,
          updatedAt: now,
          user: { id: 'user-1', name: 'User 1', username: 'u1', avatarUrl: null },
          views: [{ id: 'v1', viewerId: 'viewer-1', viewedAt: now }],
        },
        {
          id: 's2',
          userId: 'user-1',
          familyId: 'fam-1',
          caption: 'Story 2',
          mediaUrl: '',
          mediaType: 'image',
          bgGradient: null,
          expiresAt: futureDate,
          createdAt: now,
          updatedAt: now,
          user: { id: 'user-1', name: 'User 1', username: 'u1', avatarUrl: null },
          views: [],
        },
        {
          id: 's3',
          userId: 'user-2',
          familyId: 'fam-1',
          caption: 'Story 3',
          mediaUrl: '',
          mediaType: 'text',
          bgGradient: null,
          expiresAt: futureDate,
          createdAt: now,
          updatedAt: now,
          user: { id: 'user-2', name: 'User 2', username: 'u2', avatarUrl: null },
          views: [],
        },
      ];

      mockPrisma.familyMember.findFirst.mockResolvedValue({ id: 'fm1' });
      mockPrisma.story.findMany.mockResolvedValue(stories);

      const result = await service.findByFamily('fam-1', 'viewer-1');

      expect(result).toHaveLength(2);
      const user1Group = result.find((g: any) => g.user.id === 'user-1');
      const user2Group = result.find((g: any) => g.user.id === 'user-2');

      expect(user1Group!.stories).toHaveLength(2);
      expect(user1Group!.hasUnviewed).toBe(true);
      expect(user2Group!.hasUnviewed).toBe(true);
    });
  });

  // ─── findByUser ────────────────────────────────────────────────────
  describe('findByUser', () => {
    it('should return only non-expired stories for a user', async () => {
      const now = new Date();
      const futureDate = new Date(now.getTime() + 86400000);

      const stories = [
        {
          id: 's1',
          userId: 'user-1',
          familyId: null,
          caption: 'Story 1',
          mediaUrl: '',
          mediaType: 'text',
          bgGradient: null,
          expiresAt: futureDate,
          createdAt: now,
          updatedAt: now,
          user: { id: 'user-1', name: 'User 1', username: 'u1', avatarUrl: null },
          views: [],
        },
      ];

      mockPrisma.story.findMany.mockResolvedValue(stories);

      const result = await service.findByUser('user-1');

      expect(result).toHaveLength(1);
      expect(mockPrisma.story.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            userId: 'user-1',
            expiresAt: { gt: expect.any(Date) },
          },
        }),
      );
    });
  });

  // ─── markViewed ────────────────────────────────────────────────────
  describe('markViewed', () => {
    it('should upsert StoryView', async () => {
      mockPrisma.story.findUnique.mockResolvedValue({
        id: 's1',
        userId: 'user-1',
      });
      mockPrisma.storyView.upsert.mockResolvedValue({
        id: 'v1',
        storyId: 's1',
        viewerId: 'viewer-1',
      });

      const result = await service.markViewed('s1', 'viewer-1');

      expect(mockPrisma.storyView.upsert).toHaveBeenCalledWith({
        where: { storyId_viewerId: { storyId: 's1', viewerId: 'viewer-1' } },
        create: { storyId: 's1', viewerId: 'viewer-1' },
        update: { viewedAt: expect.any(Date) },
      });
      expect(result).toEqual({ viewed: true, storyId: 's1', viewerId: 'viewer-1' });
    });

    it('should throw NotFoundException if story not found', async () => {
      mockPrisma.story.findUnique.mockResolvedValue(null);

      await expect(service.markViewed('nonexistent', 'viewer-1')).rejects.toThrow(
        NotFoundException,
      );
      await expect(service.markViewed('nonexistent', 'viewer-1')).rejects.toThrow(
        'Story not found',
      );
    });
  });

  // ─── remove ────────────────────────────────────────────────────────
  describe('remove', () => {
    it('should throw ForbiddenException if not owner', async () => {
      mockPrisma.story.findUnique.mockResolvedValue({
        id: 's1',
        userId: 'user-2',
      });

      await expect(service.remove('s1', 'user-1')).rejects.toThrow(
        ForbiddenException,
      );
      await expect(service.remove('s1', 'user-1')).rejects.toThrow(
        'You can only delete your own stories',
      );
    });

    it('should throw NotFoundException if not found', async () => {
      mockPrisma.story.findUnique.mockResolvedValue(null);

      await expect(service.remove('nonexistent', 'user-1')).rejects.toThrow(
        NotFoundException,
      );
      await expect(service.remove('nonexistent', 'user-1')).rejects.toThrow(
        'Story not found',
      );
    });

    it('should delete if owner', async () => {
      mockPrisma.story.findUnique.mockResolvedValue({
        id: 's1',
        userId: 'user-1',
      });
      mockPrisma.story.delete.mockResolvedValue({ id: 's1' });

      const result = await service.remove('s1', 'user-1');

      expect(mockPrisma.story.delete).toHaveBeenCalledWith({ where: { id: 's1' } });
      expect(result).toEqual({ deleted: true, storyId: 's1' });
    });
  });
});
