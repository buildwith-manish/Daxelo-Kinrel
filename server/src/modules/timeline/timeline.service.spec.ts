import { Test, TestingModule } from '@nestjs/testing';
import { TimelineService } from './timeline.service';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { NotFoundException, ForbiddenException } from '@nestjs/common';

describe('TimelineService', () => {
  let service: TimelineService;
  let prisma: PrismaService;

  const mockGateway = {
    emitToFamily: jest.fn(),
    emitToUser: jest.fn(),
  };

  const mockPrisma = {
    familyPost: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    familyMember: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      // TimelineService.assertMember (timeline.service.ts:63-69) looks up
      // memberships via familyMember.findUnique on the compound key
      // {familyId_userId}; the local mock lacked it entirely.
      findUnique: jest.fn(),
    },
    follow: {
      findMany: jest.fn(),
    },
    user: {
      findUnique: jest.fn(),
    },
    // FamilyPostComment rows replace the comments that used to live in the
    // FamilyPost.reactions JSON (task 4b).
    familyPostComment: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    // Array form only: runs the already-built operations.
    $transaction: jest.fn((ops: Promise<unknown>[]) => Promise.all(ops)),
  };

  /** A FamilyPostComment row as Prisma returns it (createdAt is a Date). */
  const commentRow = (over: Partial<Record<string, any>> = {}) => ({
    id: 'c1',
    authorId: 'u1',
    authorName: 'User 1',
    body: 'Hello',
    parentId: null,
    createdAt: new Date('2024-01-01T00:00:00.000Z'),
    ...over,
  });

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        TimelineService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: KinrelGateway, useValue: mockGateway },
      ],
    }).compile();

    service = module.get<TimelineService>(TimelineService);
    prisma = module.get<PrismaService>(PrismaService);

    jest.clearAllMocks();

    mockPrisma.familyPostComment.count.mockResolvedValue(0);
    mockPrisma.familyPost.update.mockResolvedValue({});

    // Default: the acting user is a member of 'fam-1' so assertMember
    // (timeline.service.ts:63-69) passes for membership-gated reads/writes.
    mockPrisma.familyMember.findUnique.mockResolvedValue({
      id: 'fm-1',
      familyId: 'fam-1',
      userId: 'user-1',
      role: 'member',
    });
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
        reactions: '{}',
        createdAt: new Date(),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      }));

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await service.getTimeline('fam-1', 'user-1', 20);

      expect(result.data).toHaveLength(20);
      expect(result.nextCursor).toBe('post-19');
      expect(mockPrisma.familyPost.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam-1' },
          take: 21,
          skip: 0,
        }),
      );
      // Membership is enforced via the compound key lookup (assertMember).
      expect(mockPrisma.familyMember.findUnique).toHaveBeenCalledWith({
        where: { familyId_userId: { familyId: 'fam-1', userId: 'user-1' } },
      });
    });

    it('should return null nextCursor when no more pages', async () => {
      const posts = Array.from({ length: 5 }, (_, i) => ({
        id: `post-${i}`,
        familyId: 'fam-1',
        authorId: 'user-1',
        postType: 'update',
        content: 'Hello',
        reactions: '{}',
        createdAt: new Date(),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      }));

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await service.getTimeline('fam-1', 'user-1', 20);

      expect(result.data).toHaveLength(5);
      expect(result.nextCursor).toBeNull();
    });

    it('should replace the legacy JSON comment keys with the live comment count', async () => {
      const legacyComment = { id: 'old', authorId: 'u1', authorName: 'U', body: 'x', parentId: null, createdAt: '2024-01-01T00:00:00Z' };
      mockPrisma.familyPost.findMany.mockResolvedValue([
        {
          id: 'post-1',
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: 'Hello',
          reactions: JSON.stringify({ emojis: { '❤️': 1 }, userReactions: { u9: ['❤️'] }, commentCount: 1, comments: [legacyComment] }),
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-1', name: 'User 1', photoUrl: null },
          _count: { comments: 7 },
        },
      ]);

      const result = await service.getTimeline('fam-1', 'user-1', 20);

      expect(mockPrisma.familyPost.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          select: expect.objectContaining({ _count: { select: { comments: true } } }),
        }),
      );
      const post: any = result.data[0];
      expect(post._count).toBeUndefined();
      const reactions = JSON.parse(post.reactions);
      expect(reactions.commentCount).toBe(7);
      expect(reactions.comments).toEqual([]);
      // emoji data is untouched
      expect(reactions.emojis).toEqual({ '❤️': 1 });
      expect(reactions.userReactions).toEqual({ u9: ['❤️'] });
    });

    it('should apply cursor-based pagination with skip', async () => {
      const posts = Array.from({ length: 5 }, (_, i) => ({
        id: `post-${i}`,
        familyId: 'fam-1',
        authorId: 'user-1',
        postType: 'update',
        content: 'Hello',
        reactions: '{}',
        createdAt: new Date(),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      }));

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      await service.getTimeline('fam-1', 'user-1', 20, 'cursor-123');

      expect(mockPrisma.familyPost.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 1,
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
      mockPrisma.familyMember.findMany
        .mockResolvedValueOnce([{ familyId: 'fam-1' }])
        .mockResolvedValueOnce([{ familyId: 'fam-2' }]);

      mockPrisma.follow.findMany.mockResolvedValue([{ followingId: 'user-2' }]);

      const posts = [
        {
          id: 'p1',
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: 'My family post',
          reactions: '{}',
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
          reactions: '{}',
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-2', name: 'User 2', photoUrl: null, photoThumb: null },
          family: { id: 'fam-2', name: 'Family 2', avatarUrl: null, isPublic: true },
        },
      ];

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await service.getHomeFeed(userId, 20);

      expect(result.data).toHaveLength(2);
      const fam1Post = result.data.find((p: any) => p.familyId === 'fam-1')!;
      expect(fam1Post.source).toBe('family');

      const fam2Post = result.data.find((p: any) => p.familyId === 'fam-2')!;
      expect(fam2Post.source).toBe('following');
    });

    it('should expose the live comment count on home-feed posts', async () => {
      mockPrisma.familyMember.findMany.mockResolvedValue([{ familyId: 'fam-1' }]);
      mockPrisma.follow.findMany.mockResolvedValue([]);
      mockPrisma.familyPost.findMany.mockResolvedValue([
        {
          id: 'p1',
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: 'Post',
          reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-1', name: 'User 1', photoUrl: null, photoThumb: null },
          family: { id: 'fam-1', name: 'Family 1', avatarUrl: null, isPublic: true },
          _count: { comments: 3 },
        },
      ]);

      const result = await service.getHomeFeed(userId, 20);

      const post: any = result.data[0];
      expect(post._count).toBeUndefined();
      expect(post.source).toBe('family');
      expect(JSON.parse(post.reactions).commentCount).toBe(3);
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
          reactions: '{}',
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
    it('should create with JSON.stringify content and emit socket event', async () => {
      const content = { text: 'Hello', media: ['img.jpg'] };
      const mockPost = {
        id: 'p1',
        familyId: 'fam-1',
        authorId: 'user-1',
        postType: 'update',
        content: JSON.stringify(content),
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      };

      mockPrisma.familyPost.create.mockResolvedValue(mockPost);

      const result = await service.createPost('fam-1', 'user-1', 'update', content);

      expect(mockPrisma.familyPost.create).toHaveBeenCalledWith({
        data: {
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: JSON.stringify(content),
          reactions: expect.any(String),
        },
        include: {
          author: { select: { id: true, name: true, photoUrl: true } },
        },
      });
      expect(result.content).toBe(JSON.stringify(content));
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:post_created',
        expect.objectContaining({
          id: 'p1',
          type: 'timeline:post_created',
          familyId: 'fam-1',
        }),
      );
    });
  });

  // ─── toggleReaction ────────────────────────────────────────────────
  describe('toggleReaction', () => {
    const postId = 'post-1';
    const userId = 'user-1';
    const emoji = '\u2764\uFE0F';

    it('should add a reaction when user has not reacted', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.toggleReaction('fam-1', postId, userId, emoji);

      expect(result.emojis[emoji]).toBe(1);
      expect(result.userReactions[userId]).toContain(emoji);
      expect(mockPrisma.familyPost.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: postId },
          data: { reactions: expect.any(String) },
        }),
      );
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:reaction',
        expect.objectContaining({ action: 'added', emoji, userId }),
      );
    });

    it('should remove a reaction when user already reacted with same emoji', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: JSON.stringify({
          emojis: { [emoji]: 1 },
          userReactions: { [userId]: [emoji] },
          commentCount: 0,
          comments: [],
        }),
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.toggleReaction('fam-1', postId, userId, emoji);

      expect(result.emojis[emoji]).toBeUndefined();
      expect(result.userReactions[userId]).toBeUndefined();
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:reaction',
        expect.objectContaining({ action: 'removed', emoji, userId }),
      );
    });

    it('should increment emoji count for a new emoji on an existing reaction', async () => {
      const clapEmoji = '\uD83D\uDC4F';
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: JSON.stringify({
          emojis: { [emoji]: 2 },
          userReactions: { 'user-1': [emoji], 'user-2': [emoji] },
          commentCount: 0,
          comments: [],
        }),
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.toggleReaction('fam-1', postId, userId, clapEmoji);

      expect(result.emojis[clapEmoji]).toBe(1);
      expect(result.emojis[emoji]).toBe(2);
      expect(result.userReactions[userId]).toContain(clapEmoji);
      expect(result.userReactions[userId]).toContain(emoji);
    });

    it('should return the live comment count, not the legacy JSON one', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: JSON.stringify({
          emojis: {},
          userReactions: {},
          commentCount: 99,
          comments: [{ id: 'old', authorId: 'u', authorName: 'U', body: 'x', parentId: null, createdAt: '2024-01-01T00:00:00Z' }],
        }),
      });
      mockPrisma.familyPostComment.count.mockResolvedValue(4);

      const result = await service.toggleReaction('fam-1', postId, userId, emoji);

      expect(mockPrisma.familyPostComment.count).toHaveBeenCalledWith({ where: { familyPostId: postId } });
      expect(result.commentCount).toBe(4);
      expect(result.comments).toEqual([]);
      expect(result.emojis[emoji]).toBe(1);
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.toggleReaction('fam-1', postId, userId, emoji)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should handle legacy reactions JSON gracefully', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: JSON.stringify({ heart: 5, comment: 2 }),
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.toggleReaction('fam-1', postId, userId, emoji);

      expect(result.emojis[emoji]).toBe(1);
      expect(result.userReactions[userId]).toContain(emoji);
    });

    it('should handle malformed reactions JSON gracefully', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: 'invalid-json{{{',
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.toggleReaction('fam-1', postId, userId, emoji);

      expect(result.emojis[emoji]).toBe(1);
      expect(result.userReactions[userId]).toContain(emoji);
    });
  });

  // ─── getComments ───────────────────────────────────────────────────
  describe('getComments', () => {
    const postId = 'post-1';

    beforeEach(() => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({ id: postId });
    });

    it('should return comment rows in the CommentData shape (ISO createdAt)', async () => {
      mockPrisma.familyPostComment.findMany.mockResolvedValue([
        commentRow({ id: 'c1', body: 'Hello' }),
        commentRow({ id: 'c2', authorId: 'u2', authorName: 'User 2', body: 'World', parentId: 'c1', createdAt: new Date('2024-01-01T01:00:00.000Z') }),
      ]);

      const result = await service.getComments(postId);

      expect(mockPrisma.familyPostComment.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyPostId: postId },
          orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
          take: 51,
        }),
      );
      expect(result.data).toEqual([
        { id: 'c1', authorId: 'u1', authorName: 'User 1', body: 'Hello', parentId: null, createdAt: '2024-01-01T00:00:00.000Z' },
        { id: 'c2', authorId: 'u2', authorName: 'User 2', body: 'World', parentId: 'c1', createdAt: '2024-01-01T01:00:00.000Z' },
      ]);
      expect(result.nextCursor).toBeNull();
    });

    it('should not read the reactions JSON for comments', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        reactions: JSON.stringify({ commentCount: 1, comments: [{ id: 'legacy', body: 'x' }] }),
      });
      mockPrisma.familyPostComment.findMany.mockResolvedValue([]);

      const result = await service.getComments(postId);

      expect(result.data).toEqual([]);
    });

    it('should paginate with limit: fetch limit+1, return limit, cursor = last returned id', async () => {
      mockPrisma.familyPostComment.findMany.mockResolvedValue(
        Array.from({ length: 51 }, (_, i) => commentRow({ id: `c${i}` })),
      );

      const result = await service.getComments(postId, 50);

      expect(result.data).toHaveLength(50);
      expect(result.nextCursor).toBe('c49');
    });

    it('should start after the cursor comment when it belongs to this post', async () => {
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: 'c49' });
      mockPrisma.familyPostComment.findMany.mockResolvedValue(
        Array.from({ length: 5 }, (_, i) => commentRow({ id: `c${50 + i}` })),
      );

      const result = await service.getComments(postId, 50, 'c49');

      expect(mockPrisma.familyPostComment.findFirst).toHaveBeenCalledWith({
        where: { id: 'c49', familyPostId: postId },
        select: { id: true },
      });
      expect(mockPrisma.familyPostComment.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ cursor: { id: 'c49' }, skip: 1 }),
      );
      expect(result.data).toHaveLength(5);
      expect(result.nextCursor).toBeNull();
    });

    it('should ignore an unknown / foreign cursor and start from the beginning', async () => {
      mockPrisma.familyPostComment.findFirst.mockResolvedValue(null);
      mockPrisma.familyPostComment.findMany.mockResolvedValue([commentRow()]);

      await service.getComments(postId, 50, 'not-on-this-post');

      const args = mockPrisma.familyPostComment.findMany.mock.calls[0][0];
      expect(args.cursor).toBeUndefined();
      expect(args.skip).toBeUndefined();
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.getComments(postId)).rejects.toThrow(NotFoundException);
      expect(mockPrisma.familyPostComment.findMany).not.toHaveBeenCalled();
    });

    it('should return empty array for post with no comments', async () => {
      mockPrisma.familyPostComment.findMany.mockResolvedValue([]);

      const result = await service.getComments(postId);

      expect(result.data).toHaveLength(0);
      expect(result.nextCursor).toBeNull();
    });
  });

  // ─── addComment ────────────────────────────────────────────────────
  describe('addComment', () => {
    const postId = 'post-1';
    const authorId = 'user-1';
    const dto = { body: 'Great post!' };

    beforeEach(() => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({ id: postId, familyId: 'fam-1' });
      mockPrisma.user.findUnique.mockResolvedValue({ name: 'User 1' });
    });

    it('should create a FamilyPostComment row and emit the socket event', async () => {
      mockPrisma.familyPostComment.create.mockResolvedValue(
        commentRow({ id: 'new-1', authorId, authorName: 'User 1', body: 'Great post!' }),
      );

      const result = await service.addComment(postId, authorId, dto as any);

      expect(mockPrisma.familyPostComment.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { familyPostId: postId, authorId, authorName: 'User 1', body: 'Great post!', parentId: null },
        }),
      );
      expect(result).toEqual({
        id: 'new-1',
        authorId,
        authorName: 'User 1',
        body: 'Great post!',
        parentId: null,
        createdAt: '2024-01-01T00:00:00.000Z',
      });
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:comment',
        expect.objectContaining({ type: 'timeline:comment', comment: result }),
      );
    });

    it('should no longer write comments into the reactions JSON', async () => {
      mockPrisma.familyPostComment.create.mockResolvedValue(commentRow());

      await service.addComment(postId, authorId, dto as any);

      for (const call of mockPrisma.familyPost.update.mock.calls) {
        expect(call[0].data.reactions).toBeUndefined();
      }
    });

    it('should bump FamilyPost.updatedAt in the same transaction (delta sync keys off it)', async () => {
      mockPrisma.familyPostComment.create.mockResolvedValue(commentRow());

      await service.addComment(postId, authorId, dto as any);

      expect(mockPrisma.$transaction).toHaveBeenCalledTimes(1);
      expect(mockPrisma.familyPost.update).toHaveBeenCalledWith({
        where: { id: postId },
        data: { updatedAt: expect.any(Date) },
      });
    });

    it('should add a reply when the parent comment is on the same post', async () => {
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: 'c1' });
      mockPrisma.familyPostComment.create.mockResolvedValue(commentRow({ id: 'c2', body: 'Reply!', parentId: 'c1' }));

      const result = await service.addComment(postId, authorId, { body: 'Reply!', parentId: 'c1' } as any);

      expect(mockPrisma.familyPostComment.findFirst).toHaveBeenCalledWith({
        where: { id: 'c1', familyPostId: postId },
        select: { id: true },
      });
      expect(result.parentId).toBe('c1');
      expect(result.body).toBe('Reply!');
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.addComment(postId, authorId, dto as any)).rejects.toThrow(
        NotFoundException,
      );
      expect(mockPrisma.familyPostComment.create).not.toHaveBeenCalled();
    });

    it('should throw NotFoundException if parentId is not a comment on this post', async () => {
      mockPrisma.familyPostComment.findFirst.mockResolvedValue(null);

      await expect(
        service.addComment(postId, authorId, { body: 'Reply!', parentId: 'nonexistent' } as any),
      ).rejects.toThrow(NotFoundException);
      expect(mockPrisma.familyPostComment.create).not.toHaveBeenCalled();
      expect(mockGateway.emitToFamily).not.toHaveBeenCalled();
    });

    it('should fall back to "Unknown" when the author has no User row', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);
      mockPrisma.familyPostComment.create.mockResolvedValue(commentRow({ authorName: 'Unknown' }));

      await service.addComment(postId, authorId, dto as any);

      expect(mockPrisma.familyPostComment.create).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ authorName: 'Unknown' }) }),
      );
    });
  });

  // ─── deleteComment ─────────────────────────────────────────────────
  describe('deleteComment', () => {
    const postId = 'post-1';
    const commentId = 'c1';
    const authorId = 'user-1';
    const otherUserId = 'user-2';

    const post = (over: Record<string, any> = {}) => ({
      id: postId,
      familyId: 'fam-1',
      authorId: 'user-3',
      ...over,
    });

    it('should allow comment author to delete their own comment', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(post());
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: commentId, authorId });
      mockPrisma.familyPostComment.delete.mockResolvedValue({});

      const result = await service.deleteComment(postId, commentId, authorId);

      expect(result.deleted).toBe(true);
      expect(result.commentId).toBe(commentId);
      expect(mockPrisma.familyPostComment.findFirst).toHaveBeenCalledWith({
        where: { id: commentId, familyPostId: postId },
        select: { id: true, authorId: true },
      });
      expect(mockPrisma.familyPostComment.delete).toHaveBeenCalledWith({ where: { id: commentId } });
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:comment_deleted',
        expect.objectContaining({ commentId }),
      );
    });

    it('should bump FamilyPost.updatedAt in the same transaction', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(post());
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: commentId, authorId });
      mockPrisma.familyPostComment.delete.mockResolvedValue({});

      await service.deleteComment(postId, commentId, authorId);

      expect(mockPrisma.$transaction).toHaveBeenCalledTimes(1);
      expect(mockPrisma.familyPost.update).toHaveBeenCalledWith({
        where: { id: postId },
        data: { updatedAt: expect.any(Date) },
      });
    });

    it('should allow post author to delete any comment', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(post({ authorId }));
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: commentId, authorId: otherUserId });
      mockPrisma.familyPostComment.delete.mockResolvedValue({});

      const result = await service.deleteComment(postId, commentId, authorId);

      expect(result.deleted).toBe(true);
    });

    it('should allow family admin to delete any comment', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(post());
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: commentId, authorId: otherUserId });
      mockPrisma.familyMember.findFirst.mockResolvedValue({ role: 'admin' });
      mockPrisma.familyPostComment.delete.mockResolvedValue({});

      const result = await service.deleteComment(postId, commentId, authorId);

      expect(result.deleted).toBe(true);
    });

    it('should forbid non-author non-admin from deleting comment', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(post());
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: commentId, authorId: otherUserId });
      mockPrisma.familyMember.findFirst.mockResolvedValue({ role: 'member' });

      await expect(service.deleteComment(postId, commentId, authorId)).rejects.toThrow(
        ForbiddenException,
      );
      expect(mockPrisma.familyPostComment.delete).not.toHaveBeenCalled();
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.deleteComment(postId, commentId, authorId)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw NotFoundException if comment does not exist on this post', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(post({ authorId }));
      mockPrisma.familyPostComment.findFirst.mockResolvedValue(null);

      await expect(service.deleteComment(postId, 'nonexistent', authorId)).rejects.toThrow(
        NotFoundException,
      );
      expect(mockPrisma.familyPostComment.delete).not.toHaveBeenCalled();
    });

    it('should delete only the parent row; replies go via ON DELETE CASCADE', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(post());
      mockPrisma.familyPostComment.findFirst.mockResolvedValue({ id: 'c1', authorId });
      mockPrisma.familyPostComment.delete.mockResolvedValue({});

      const result = await service.deleteComment(postId, 'c1', authorId);

      expect(result.deleted).toBe(true);
      expect(mockPrisma.familyPostComment.delete).toHaveBeenCalledTimes(1);
      expect(mockPrisma.familyPostComment.delete).toHaveBeenCalledWith({ where: { id: 'c1' } });
    });
  });

  // ─── deletePost ────────────────────────────────────────────────────
  describe('deletePost', () => {
    const postId = 'post-1';
    const authorId = 'user-1';
    const otherUserId = 'user-2';

    it('should allow post author to delete their post', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId,
      });
      mockPrisma.familyPost.delete.mockResolvedValue({ id: postId });

      const result = await service.deletePost(postId, authorId);

      expect(result.deleted).toBe(true);
      expect(result.postId).toBe(postId);
      expect(mockPrisma.familyPost.delete).toHaveBeenCalledWith({ where: { id: postId } });
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:post_deleted',
        expect.objectContaining({ id: postId, type: 'timeline:post_deleted' }),
      );
    });

    it('should allow family owner to delete any post', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: otherUserId,
      });
      mockPrisma.familyMember.findFirst.mockResolvedValue({ role: 'owner' });
      mockPrisma.familyPost.delete.mockResolvedValue({ id: postId });

      const result = await service.deletePost(postId, authorId);

      expect(result.deleted).toBe(true);
    });

    it('should allow family admin to delete any post', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: otherUserId,
      });
      mockPrisma.familyMember.findFirst.mockResolvedValue({ role: 'admin' });
      mockPrisma.familyPost.delete.mockResolvedValue({ id: postId });

      const result = await service.deletePost(postId, authorId);

      expect(result.deleted).toBe(true);
    });

    it('should forbid non-author non-admin from deleting post', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: otherUserId,
      });
      mockPrisma.familyMember.findFirst.mockResolvedValue({ role: 'member' });

      await expect(service.deletePost(postId, authorId)).rejects.toThrow(ForbiddenException);
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.deletePost(postId, authorId)).rejects.toThrow(NotFoundException);
    });
  });
});
