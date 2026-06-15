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
    },
    follow: {
      findMany: jest.fn(),
    },
    user: {
      findUnique: jest.fn(),
    },
  };

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

      const result = await service.getTimeline('fam-1', 20);

      expect(result.data).toHaveLength(20);
      expect(result.nextCursor).toBe('post-19');
      expect(mockPrisma.familyPost.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam-1' },
          take: 21,
          skip: 0,
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
        reactions: '{}',
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
        reactions: '{}',
        createdAt: new Date(),
        updatedAt: new Date(),
        author: { id: 'user-1', name: 'User 1', photoUrl: null },
      }));

      mockPrisma.familyPost.findMany.mockResolvedValue(posts);

      await service.getTimeline('fam-1', 20, 'cursor-123');

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

      const result = await service.toggleReaction(postId, userId, emoji);

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

      const result = await service.toggleReaction(postId, userId, emoji);

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

      const result = await service.toggleReaction(postId, userId, clapEmoji);

      expect(result.emojis[clapEmoji]).toBe(1);
      expect(result.emojis[emoji]).toBe(2);
      expect(result.userReactions[userId]).toContain(clapEmoji);
      expect(result.userReactions[userId]).toContain(emoji);
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.toggleReaction(postId, userId, emoji)).rejects.toThrow(
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

      const result = await service.toggleReaction(postId, userId, emoji);

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

      const result = await service.toggleReaction(postId, userId, emoji);

      expect(result.emojis[emoji]).toBe(1);
      expect(result.userReactions[userId]).toContain(emoji);
    });
  });

  // ─── getComments ───────────────────────────────────────────────────
  describe('getComments', () => {
    const postId = 'post-1';

    it('should return comments from the reactions JSON field', async () => {
      const comments = [
        { id: 'c1', authorId: 'u1', authorName: 'User 1', body: 'Hello', parentId: null, createdAt: '2024-01-01T00:00:00Z' },
        { id: 'c2', authorId: 'u2', authorName: 'User 2', body: 'World', parentId: null, createdAt: '2024-01-01T01:00:00Z' },
      ];
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 2, comments }),
      });

      const result = await service.getComments(postId);

      expect(result.data).toHaveLength(2);
      expect(result.nextCursor).toBeNull();
    });

    it('should paginate comments with limit', async () => {
      const comments = Array.from({ length: 55 }, (_, i) => ({
        id: `c${i}`,
        authorId: 'u1',
        authorName: 'User 1',
        body: `Comment ${i}`,
        parentId: null,
        createdAt: new Date(Date.now() + i * 1000).toISOString(),
      }));
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 55, comments }),
      });

      const result = await service.getComments(postId, 50);

      expect(result.data).toHaveLength(50);
      expect(result.nextCursor).toBe('c49');
    });

    it('should apply cursor-based pagination', async () => {
      const comments = Array.from({ length: 55 }, (_, i) => ({
        id: `c${i}`,
        authorId: 'u1',
        authorName: 'User 1',
        body: `Comment ${i}`,
        parentId: null,
        createdAt: new Date(Date.now() + i * 1000).toISOString(),
      }));
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 55, comments }),
      });

      const result = await service.getComments(postId, 50, 'c49');

      expect(result.data).toHaveLength(5);
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.getComments(postId)).rejects.toThrow(NotFoundException);
    });

    it('should return empty array for post with no comments', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
      });

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

    it('should add a comment and emit socket event', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
      });
      mockPrisma.user.findUnique.mockResolvedValue({ name: 'User 1' });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.addComment(postId, authorId, dto as any);

      expect(result.body).toBe('Great post!');
      expect(result.authorId).toBe(authorId);
      expect(result.authorName).toBe('User 1');
      expect(result.parentId).toBeNull();
      expect(result.id).toBeTruthy();
      expect(mockPrisma.familyPost.update).toHaveBeenCalled();
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:comment',
        expect.objectContaining({ type: 'timeline:comment' }),
      );
    });

    it('should add a reply comment with parentId', async () => {
      const existingComment = {
        id: 'c1',
        authorId: 'u2',
        authorName: 'User 2',
        body: 'Original',
        parentId: null,
        createdAt: '2024-01-01T00:00:00Z',
      };
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 1, comments: [existingComment] }),
      });
      mockPrisma.user.findUnique.mockResolvedValue({ name: 'User 1' });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const replyDto = { body: 'Reply!', parentId: 'c1' };
      const result = await service.addComment(postId, authorId, replyDto as any);

      expect(result.parentId).toBe('c1');
      expect(result.body).toBe('Reply!');
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.addComment(postId, authorId, dto as any)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw NotFoundException if parentId does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
      });
      mockPrisma.user.findUnique.mockResolvedValue({ name: 'User 1' });

      const replyDto = { body: 'Reply!', parentId: 'nonexistent' };
      await expect(service.addComment(postId, authorId, replyDto as any)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should update commentCount correctly', async () => {
      const existingComment = {
        id: 'c1',
        authorId: 'u2',
        authorName: 'User 2',
        body: 'First',
        parentId: null,
        createdAt: '2024-01-01T00:00:00Z',
      };
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 1, comments: [existingComment] }),
      });
      mockPrisma.user.findUnique.mockResolvedValue({ name: 'User 1' });
      mockPrisma.familyPost.update.mockResolvedValue({});

      await service.addComment(postId, authorId, dto as any);

      // Verify the update was called with the correct commentCount
      const updateCall = mockPrisma.familyPost.update.mock.calls[0][0];
      const updatedReactions = JSON.parse(updateCall.data.reactions);
      expect(updatedReactions.commentCount).toBe(2);
      expect(updatedReactions.comments).toHaveLength(2);
    });
  });

  // ─── deleteComment ─────────────────────────────────────────────────
  describe('deleteComment', () => {
    const postId = 'post-1';
    const commentId = 'c1';
    const authorId = 'user-1';
    const otherUserId = 'user-2';

    it('should allow comment author to delete their own comment', async () => {
      const comments = [
        { id: 'c1', authorId, authorName: 'User 1', body: 'My comment', parentId: null, createdAt: '2024-01-01T00:00:00Z' },
      ];
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-3',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 1, comments }),
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.deleteComment(postId, commentId, authorId);

      expect(result.deleted).toBe(true);
      expect(result.commentId).toBe(commentId);
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'timeline:comment_deleted',
        expect.objectContaining({ commentId }),
      );
    });

    it('should allow post author to delete any comment', async () => {
      const comments = [
        { id: 'c1', authorId: otherUserId, authorName: 'User 2', body: 'Their comment', parentId: null, createdAt: '2024-01-01T00:00:00Z' },
      ];
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: authorId,
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 1, comments }),
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.deleteComment(postId, commentId, authorId);

      expect(result.deleted).toBe(true);
    });

    it('should allow family admin to delete any comment', async () => {
      const comments = [
        { id: 'c1', authorId: otherUserId, authorName: 'User 2', body: 'Their comment', parentId: null, createdAt: '2024-01-01T00:00:00Z' },
      ];
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-3',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 1, comments }),
      });
      mockPrisma.familyMember.findFirst.mockResolvedValue({ role: 'admin' });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.deleteComment(postId, commentId, authorId);

      expect(result.deleted).toBe(true);
    });

    it('should forbid non-author non-admin from deleting comment', async () => {
      const comments = [
        { id: 'c1', authorId: otherUserId, authorName: 'User 2', body: 'Their comment', parentId: null, createdAt: '2024-01-01T00:00:00Z' },
      ];
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-3',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 1, comments }),
      });
      mockPrisma.familyMember.findFirst.mockResolvedValue({ role: 'member' });

      await expect(service.deleteComment(postId, commentId, authorId)).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should throw NotFoundException if post does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(service.deleteComment(postId, commentId, authorId)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw NotFoundException if comment does not exist', async () => {
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: authorId,
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
      });

      await expect(service.deleteComment(postId, 'nonexistent', authorId)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should also delete child replies when deleting a parent comment', async () => {
      const comments = [
        { id: 'c1', authorId, authorName: 'User 1', body: 'Parent', parentId: null, createdAt: '2024-01-01T00:00:00Z' },
        { id: 'c2', authorId: otherUserId, authorName: 'User 2', body: 'Reply', parentId: 'c1', createdAt: '2024-01-01T01:00:00Z' },
        { id: 'c3', authorId: 'u3', authorName: 'User 3', body: 'Other', parentId: null, createdAt: '2024-01-01T02:00:00Z' },
      ];
      mockPrisma.familyPost.findUnique.mockResolvedValue({
        id: postId,
        familyId: 'fam-1',
        authorId: 'user-3',
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 3, comments }),
      });
      mockPrisma.familyPost.update.mockResolvedValue({});

      const result = await service.deleteComment(postId, 'c1', authorId);

      expect(result.deleted).toBe(true);
      // Verify update call removes both c1 and c2 (its reply)
      const updateCall = mockPrisma.familyPost.update.mock.calls[0][0];
      const updatedReactions = JSON.parse(updateCall.data.reactions);
      expect(updatedReactions.comments).toHaveLength(1);
      expect(updatedReactions.comments[0].id).toBe('c3');
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
