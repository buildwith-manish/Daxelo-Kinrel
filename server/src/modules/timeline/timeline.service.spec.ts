import { Test, TestingModule } from '@nestjs/testing';
import { TimelineService } from './timeline.service';
import { PrismaService } from '../../prisma/prisma.service';

describe('TimelineService', () => {
  let service: TimelineService;
  let prisma: PrismaService;

  const mockPrisma = {
    familyPost: {
      findMany: jest.fn(),
      create: jest.fn(),
    },
    familyMember: {
      findMany: jest.fn(),
    },
    follow: {
      findMany: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        TimelineService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<TimelineService>(TimelineService);
    prisma = module.get<PrismaService>(PrismaService);

    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ─── getTimeline ───────────────────────────────────────────────────
  describe('getTimeline', () => {
    it('should return paginated posts with cursor', async () => {
      const posts = Array.from({ length: 21 }, (_, i) => ({
        id: `post-${i}`,
        familyId: 'fam-1',
        authorId: 'user-1',
        postType: 'update',
        content: 'Hello',
        reactions: {},
        createdAt: new Date(),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      }));

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await service.getTimeline('fam-1', 20);

      expect(result.data).toHaveLength(20);
      expect(result.nextCursor).toBe('post-19');
      expect(mockPrisma.familyPost.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam-1' },
          take: 21, // limit + 1
          skip: 0, // no cursor
        }),
      );
    });

    it('should return null nextCursor when no more pages', async () => {
      const posts = Array.from({ length: 5 }, (_, i) => ({
        id: `post-${i}`,
        familyId: 'fam-1',
        authorId: 'user-1',
        postType: 'update',
        content: 'Hello',
        reactions: {},
        createdAt: new Date(),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      }));

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await service.getTimeline('fam-1', 20);

      expect(result.data).toHaveLength(5);
      expect(result.nextCursor).toBeNull();
    });

    it('should apply cursor-based pagination with skip', async () => {
      const posts = Array.from({ length: 5 }, (_, i) => ({
        id: `post-${i}`,
        familyId: 'fam-1',
        authorId: 'user-1',
        postType: 'update',
        content: 'Hello',
        reactions: {},
        createdAt: new Date(),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      }));

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      await service.getTimeline('fam-1', 20, 'cursor-123');

      expect(mockPrisma.familyPost.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 1, // cursor present
          cursor: { id: 'cursor-123' },
        }),
      );
    });
  });

  // ─── getHomeFeed ───────────────────────────────────────────────────
  describe('getHomeFeed', () => {
    const userId = 'user-1';

    it('should return empty if no families', async () => {
      mockPrisma.familyMember.findMany.mockResolvedValue([]);
      mockPrisma.follow.findMany.mockResolvedValue([]);

      const result = await service.getHomeFeed(userId);

      expect(result).toEqual({ data: [], nextCursor: null });
    });

    it('should combine family + followed users families, tag source correctly', async () => {
      // User is member of fam-1
      mockPrisma.familyMember.findMany
        .mockResolvedValueOnce([{ familyId: 'fam-1' }]) // my families
        .mockResolvedValueOnce([{ familyId: 'fam-2' }]); // followed user families

      // User follows user-2 who is in fam-2
      mockPrisma.follow.findMany.mockResolvedValue([
        { followingId: 'user-2' },
      ]);

      const posts = [
        {
          id: 'p1',
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: 'My family post',
          reactions: {},
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-1', name: 'User 1', photoUrl: null, photoThumb: null },
          family: { id: 'fam-1', name: 'Family 1', avatarUrl: null, isPublic: true },
        },
        {
          id: 'p2',
          familyId: 'fam-2',
          authorId: 'user-2',
          postType: 'update',
          content: 'Followed user post',
          reactions: {},
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-2', name: 'User 2', photoUrl: null, photoThumb: null },
          family: { id: 'fam-2', name: 'Family 2', avatarUrl: null, isPublic: true },
        },
      ];

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await service.getHomeFeed(userId, 20);

      expect(result.data).toHaveLength(2);
      // fam-1 is user's own family → source: 'family'
      const fam1Post = result.data.find((p: any) => p.familyId === 'fam-1')!;
      expect(fam1Post.source).toBe('family');

      // fam-2 is from followed user → source: 'following'
      const fam2Post = result.data.find((p: any) => p.familyId === 'fam-2')!;
      expect(fam2Post.source).toBe('following');
    });

    it('should handle no followed users gracefully', async () => {
      mockPrisma.familyMember.findMany.mockResolvedValue([{ familyId: 'fam-1' }]);
      mockPrisma.follow.findMany.mockResolvedValue([]);

      const posts = [
        {
          id: 'p1',
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: 'Post',
          reactions: {},
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-1', name: 'User 1', photoUrl: null, photoThumb: null },
          family: { id: 'fam-1', name: 'Family 1', avatarUrl: null, isPublic: true },
        },
      ];

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await service.getHomeFeed(userId, 20);

      expect(result.data).toHaveLength(1);
      expect(result.data[0].source).toBe('family');
    });
  });

  // ─── createPost ────────────────────────────────────────────────────
  describe('createPost', () => {
    it('should create with JSON.stringify content', async () => {
      const content = { text: 'Hello', media: ['img.jpg'] };
      mockPrisma.familyPost.create.mockResolvedValue({
        id: 'p1',
        familyId: 'fam-1',
        authorId: 'user-1',
        postType: 'update',
        content: JSON.stringify(content),
      });

      const result = await service.createPost('fam-1', 'user-1', 'update', content);

      expect(mockPrisma.familyPost.create).toHaveBeenCalledWith({
        data: {
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: JSON.stringify(content),
        },
      });
      expect(result.content).toBe(JSON.stringify(content));
    });
  });
});
