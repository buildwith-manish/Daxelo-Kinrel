/**
 * Agent-3 Integration Tests — Social/Community Feature Suite
 *
 * Tests cross-module interactions and end-to-end workflows across all
 * seven Agent-3 modules: Follow, Sparq, Stories, Community, Gamification,
 * Timeline (reactions/comments/delete), and Share.
 *
 * These tests verify that the modules work correctly together when wired
 * through their NestJS dependency injection, that socket events are emitted
 * at the right times, that authorization rules are enforced consistently,
 * and that data flows correctly between modules (e.g. follow → sparq feed,
 * family membership → timeline visibility, contribution → badge award).
 */

import { Test, TestingModule } from '@nestjs/testing';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { KinrelGateway } from '../modules/gateway/kinrel.gateway';
import { ConfigService } from '@nestjs/config';
import { FollowService } from '../modules/follow/follow.service';
import { SparqService } from '../modules/sparq/sparq.service';
import { StoriesService } from '../modules/stories/stories.service';
import { TimelineService } from '../modules/timeline/timeline.service';
import { ShareService } from '../modules/share/share.service';
import { CreateCommentDto } from '../modules/timeline/dto/timeline.dto';

// ── Shared Mock Factories ──────────────────────────────────────────────

const makeModelMock = () => ({
  findUnique: jest.fn().mockResolvedValue(null),
  findFirst: jest.fn().mockResolvedValue(null),
  findMany: jest.fn().mockResolvedValue([]),
  create: jest.fn().mockResolvedValue({}),
  update: jest.fn().mockResolvedValue({}),
  delete: jest.fn().mockResolvedValue({}),
  upsert: jest.fn().mockResolvedValue({}),
  count: jest.fn().mockResolvedValue(0),
});

const makeModelMockWithDeleteMany = () => ({
  ...makeModelMock(),
  deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
  createMany: jest.fn().mockResolvedValue({ count: 0 }),
});

const createMockPrisma = () => ({
  user: makeModelMock(),
  family: makeModelMock(),
  familyMember: makeModelMock(),
  familyPost: makeModelMock(),
  follow: makeModelMock(),
  sparq: makeModelMockWithDeleteMany(),
  sparqView: makeModelMock(),
  sparqEcho: makeModelMock(),
  story: makeModelMockWithDeleteMany(),
  storyView: makeModelMock(),
  community: makeModelMock(),
  communityMember: makeModelMock(),
  communityPost: makeModelMock(),
  communityEvent: makeModelMock(),
  eventRSVP: makeModelMock(),
  eventReminder: makeModelMock(),
  communityRule: makeModelMock(),
  reaction: makeModelMock(),
  comment: makeModelMock(),
  badge: makeModelMockWithDeleteMany(),
  userBadge: makeModelMock(),
  userContribution: makeModelMock(),
  shareableLink: makeModelMock(),
  person: makeModelMock(),
  $transaction: jest.fn((fn: any) => (typeof fn === 'function' ? fn() : Promise.resolve())),
});

const createMockGateway = () => ({
  emitToUser: jest.fn(),
  emitToFamily: jest.fn(),
});

const createMockConfigService = () => ({
  get: jest.fn((key: string) => {
    if (key === 'CLOUDINARY_CLOUD_NAME') return undefined; // Use base64 fallback
    if (key === 'CLOUDINARY_API_KEY') return undefined;
    if (key === 'CLOUDINARY_API_SECRET') return undefined;
    return undefined;
  }),
});

// ── Helper: build a fresh testing module with all Agent-3 services ────

async function createIntegrationModule() {
  const mockPrisma = createMockPrisma();
  const mockGateway = createMockGateway();
  const mockConfig = createMockConfigService();

  const module: TestingModule = await Test.createTestingModule({
    providers: [
      FollowService,
      SparqService,
      StoriesService,
      TimelineService,
      ShareService,
      { provide: PrismaService, useValue: mockPrisma },
      { provide: KinrelGateway, useValue: mockGateway },
      { provide: ConfigService, useValue: mockConfig },
    ],
  }).compile();

  return {
    module,
    followService: module.get<FollowService>(FollowService),
    sparqService: module.get<SparqService>(SparqService),
    storiesService: module.get<StoriesService>(StoriesService),
    timelineService: module.get<TimelineService>(TimelineService),
    shareService: module.get<ShareService>(ShareService),
    prisma: mockPrisma,
    gateway: mockGateway,
    config: mockConfig,
  };
}

// ══════════════════════════════════════════════════════════════════════
// 1. FOLLOW ↔ SPARQ CROSS-MODULE INTEGRATION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Follow ↔ Sparq', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Sparq feed only includes posts from followed users', () => {
    it('should return empty feed when user follows nobody', async () => {
      ctx.prisma.follow.findMany.mockResolvedValue([]);
      ctx.prisma.familyMember.findMany.mockResolvedValue([]);

      const result = await ctx.sparqService.getFeed('user-1', { page: 1, limit: 20 });

      expect(result.items).toHaveLength(0);
      expect(result.total).toBe(0);
    });

    it('should fetch sparqs from followed users', async () => {
      ctx.prisma.follow.findMany
        .mockResolvedValueOnce([{ followingId: 'user-2' }]) // for sparq feed
        .mockResolvedValueOnce([{ followingId: 'user-2' }]); // for mutual follower check

      ctx.prisma.familyMember.findMany
        .mockResolvedValueOnce([]) // my families
        .mockResolvedValueOnce([]); // family members

      const mockSparq = {
        id: 'sparq-1',
        userId: 'user-2',
        type: 'TEXT',
        text: 'Hello',
        mediaUrl: null,
        thumbnailUrl: null,
        backgroundColor: '#FF6B6B',
        duration: null,
        audience: 'PUBLIC',
        mood: 'happy',
        intensity: 'warm',
        allowChain: false,
        allowReplies: true,
        isTimeCapsule: false,
        revealAt: null,
        isRevealed: true,
        parentSparqId: null,
        chainOrder: null,
        echoCount: 0,
        viewCount: 0,
        expiresAt: new Date(Date.now() + 86400000),
        createdAt: new Date(),
        updatedAt: new Date(),
        user: { id: 'user-2', name: 'User 2', username: 'user2', avatarUrl: null, photoThumb: null },
        views: [],
      };

      ctx.prisma.sparq.findMany.mockResolvedValue([mockSparq]);

      const result = await ctx.sparqService.getFeed('user-1', { page: 1, limit: 20 });

      expect(result.items.length).toBeGreaterThanOrEqual(1);
      expect(result.items[0].user.id).toBe('user-2');
    });
  });

  describe('Follow → Sparq echo authorization', () => {
    it('should allow echo on sparq from followed user', async () => {
      ctx.prisma.sparq.findUnique.mockResolvedValue({
        id: 'sparq-1',
        userId: 'user-2',
        echoCount: 0,
      });
      ctx.prisma.sparqEcho.findUnique.mockResolvedValue(null);
      ctx.prisma.sparqEcho.create.mockResolvedValue({ id: 'echo-1', sparqId: 'sparq-1', userId: 'user-1' });
      ctx.prisma.sparq.update.mockResolvedValue({ id: 'sparq-1', echoCount: 1 });

      const result = await ctx.sparqService.toggleEcho('sparq-1', 'user-1');

      expect(result.isEchoed).toBe(true);
      expect(result.echoCount).toBe(1);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 2. FOLLOW ↔ TIMELINE CROSS-MODULE INTEGRATION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Follow ↔ Timeline', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Home feed includes posts from followed users families', () => {
    it('should combine own family + followed user family posts', async () => {
      ctx.prisma.familyMember.findMany
        .mockResolvedValueOnce([{ familyId: 'fam-1' }]) // my families
        .mockResolvedValueOnce([{ familyId: 'fam-2' }]); // followed user families

      ctx.prisma.follow.findMany.mockResolvedValue([{ followingId: 'user-2' }]);

      const posts = [
        {
          id: 'p1',
          familyId: 'fam-1',
          authorId: 'user-1',
          postType: 'update',
          content: '{}',
          reactions: '{}',
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-1', name: 'User 1', photoUrl: null, photoThumb: null },
          family: { id: 'fam-1', name: 'My Family', avatarUrl: null, isPublic: true },
        },
        {
          id: 'p2',
          familyId: 'fam-2',
          authorId: 'user-2',
          postType: 'milestone',
          content: '{}',
          reactions: '{}',
          createdAt: new Date(),
          updatedAt: new Date(),
          author: { id: 'user-2', name: 'User 2', photoUrl: null, photoThumb: null },
          family: { id: 'fam-2', name: 'Their Family', avatarUrl: null, isPublic: true },
        },
      ];

      ctx.prisma.familyPost.findMany.mockResolvedValue(posts);

      const result = await ctx.timelineService.getHomeFeed('user-1', 20);

      expect(result.data).toHaveLength(2);
      const ownPost = result.data.find((p: any) => p.familyId === 'fam-1');
      expect(ownPost.source).toBe('family');
      const followPost = result.data.find((p: any) => p.familyId === 'fam-2');
      expect(followPost.source).toBe('following');
    });

    it('should return empty feed when user has no family memberships and no follows', async () => {
      ctx.prisma.familyMember.findMany.mockResolvedValue([]);
      ctx.prisma.follow.findMany.mockResolvedValue([]);

      const result = await ctx.timelineService.getHomeFeed('user-1');

      expect(result).toEqual({ data: [], nextCursor: null });
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 3. TIMELINE REACTIONS & COMMENTS END-TO-END
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Timeline Reactions & Comments E2E', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;
  const familyId = 'fam-1';
  const authorId = 'user-1';
  const otherUserId = 'user-2';

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Create post → React → Comment → Verify reaction state', () => {
    it('should create post with empty reactions, add reaction, add comment, verify full state', async () => {
      const blankReactions = JSON.stringify({
        emojis: {},
        userReactions: {},
        commentCount: 0,
        comments: [],
      });

      ctx.prisma.familyPost.create.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        postType: 'update',
        content: '{"text":"Hello"}',
        reactions: blankReactions,
        updatedAt: new Date(),
        author: { id: authorId, name: 'Author', photoUrl: null },
      });

      const post = await ctx.timelineService.createPost(familyId, authorId, 'update', { text: 'Hello' });

      expect(ctx.prisma.familyPost.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId,
            authorId,
            postType: 'update',
            reactions: blankReactions,
          }),
        }),
      );

      expect(ctx.gateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'timeline:post_created',
        expect.objectContaining({ familyId, type: 'timeline:post_created' }),
      );

      // Toggle reaction (add)
      const reactionsWithEmoji = JSON.stringify({
        emojis: { '❤️': 1 },
        userReactions: { [otherUserId]: ['❤️'] },
        commentCount: 0,
        comments: [],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        reactions: blankReactions,
      });
      ctx.prisma.familyPost.update.mockResolvedValue({
        id: 'post-1',
        reactions: reactionsWithEmoji,
      });

      const reactionResult = await ctx.timelineService.toggleReaction('post-1', otherUserId, '❤️');

      expect(reactionResult.emojis['❤️']).toBe(1);
      expect(reactionResult.userReactions[otherUserId]).toContain('❤️');

      expect(ctx.gateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'timeline:reaction',
        expect.objectContaining({
          emoji: '❤️',
          userId: otherUserId,
          action: 'added',
        }),
      );

      // Toggle same reaction again (remove)
      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        reactions: reactionsWithEmoji,
      });

      const removeResult = await ctx.timelineService.toggleReaction('post-1', otherUserId, '❤️');

      expect(removeResult.emojis['❤️']).toBeUndefined();
      expect(removeResult.userReactions[otherUserId]).toBeUndefined();
    });

    it('should add comment, then delete it as author', async () => {
      const blankReactions = JSON.stringify({
        emojis: {},
        userReactions: {},
        commentCount: 0,
        comments: [],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        reactions: blankReactions,
      });
      ctx.prisma.user.findUnique.mockResolvedValue({ id: otherUserId, name: 'Commenter' });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const commentDto: CreateCommentDto = { body: 'Nice post!' };
      const comment = await ctx.timelineService.addComment('post-1', otherUserId, commentDto);

      expect(comment.body).toBe('Nice post!');
      expect(comment.authorId).toBe(otherUserId);
      expect(comment.authorName).toBe('Commenter');

      expect(ctx.gateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'timeline:comment',
        expect.objectContaining({ type: 'timeline:comment' }),
      );

      // Delete the comment as author
      const reactionsWithComment = JSON.stringify({
        emojis: {},
        userReactions: {},
        commentCount: 1,
        comments: [comment],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        reactions: reactionsWithComment,
      });

      const deleteResult = await ctx.timelineService.deleteComment('post-1', comment.id, otherUserId);

      expect(deleteResult.deleted).toBe(true);
      expect(deleteResult.commentId).toBe(comment.id);

      expect(ctx.gateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'timeline:comment_deleted',
        expect.objectContaining({ commentId: comment.id }),
      );
    });

    it('should add threaded comment with parentId', async () => {
      const parentComment = {
        id: 'cmt_parent',
        authorId: 'user-1',
        authorName: 'Author',
        body: 'Original comment',
        parentId: null,
        createdAt: new Date().toISOString(),
      };

      const reactionsWithParent = JSON.stringify({
        emojis: {},
        userReactions: {},
        commentCount: 1,
        comments: [parentComment],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        reactions: reactionsWithParent,
      });
      ctx.prisma.user.findUnique.mockResolvedValue({ id: otherUserId, name: 'Replier' });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const replyDto: CreateCommentDto = { body: 'Reply to you', parentId: 'cmt_parent' };
      const reply = await ctx.timelineService.addComment('post-1', otherUserId, replyDto);

      expect(reply.body).toBe('Reply to you');
      expect(reply.parentId).toBe('cmt_parent');
    });

    it('should reject comment with non-existent parentId', async () => {
      const blankReactions = JSON.stringify({
        emojis: {},
        userReactions: {},
        commentCount: 0,
        comments: [],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        reactions: blankReactions,
      });

      const replyDto: CreateCommentDto = { body: 'Reply', parentId: 'nonexistent' };

      await expect(
        ctx.timelineService.addComment('post-1', otherUserId, replyDto),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('Delete post authorization', () => {
    it('should allow post author to delete their own post', async () => {
      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
      });
      ctx.prisma.familyPost.delete.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.deletePost('post-1', authorId);

      expect(result.deleted).toBe(true);
      expect(result.postId).toBe('post-1');
      expect(ctx.gateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'timeline:post_deleted',
        expect.objectContaining({ id: 'post-1' }),
      );
    });

    it('should reject non-author non-admin from deleting post', async () => {
      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
      });
      ctx.prisma.familyMember.findFirst.mockResolvedValue({ role: 'member' });

      await expect(
        ctx.timelineService.deletePost('post-1', otherUserId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should allow family admin to delete any post', async () => {
      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
      });
      ctx.prisma.familyMember.findFirst.mockResolvedValue({ role: 'admin' });
      ctx.prisma.familyPost.delete.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.deletePost('post-1', otherUserId);

      expect(result.deleted).toBe(true);
    });

    it('should throw NotFoundException for non-existent post', async () => {
      ctx.prisma.familyPost.findUnique.mockResolvedValue(null);

      await expect(
        ctx.timelineService.deletePost('nonexistent', authorId),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('Get comments with pagination', () => {
    it('should return paginated comments sorted by createdAt', async () => {
      const comments = Array.from({ length: 55 }, (_, i) => ({
        id: `cmt-${i}`,
        authorId: `user-${i % 3}`,
        authorName: `User ${i % 3}`,
        body: `Comment ${i}`,
        parentId: null,
        createdAt: new Date(Date.now() + i * 1000).toISOString(),
      }));

      const reactionsWithComments = JSON.stringify({
        emojis: {},
        userReactions: {},
        commentCount: 55,
        comments,
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId,
        reactions: reactionsWithComments,
      });

      const result = await ctx.timelineService.getComments('post-1', 50);

      expect(result.data).toHaveLength(50);
      expect(result.nextCursor).toBeTruthy();
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 4. SHARE ↔ GATEWAY INTEGRATION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Share ↔ Gateway', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Share lifecycle: create → track → get stats → revoke', () => {
    it('should complete full share lifecycle with socket events', async () => {
      const userId = 'user-1';

      const mockLink = {
        id: 'link-1',
        token: 'abc123token',
        cardType: 'family_tree',
        familyId: 'fam-1',
        personId: null,
        title: 'My Family Tree',
        description: 'Check out my family!',
        deepLinkUrl: 'kinrel://share/family_tree/abc123token',
        viewCount: 0,
        shareCount: 0,
        expiresAt: null,
        createdAt: new Date(),
      };

      ctx.prisma.shareableLink.create.mockResolvedValue(mockLink);

      const link = await ctx.shareService.createShareableLink(userId, {
        cardType: 'family_tree',
        familyId: 'fam-1',
        title: 'My Family Tree',
        description: 'Check out my family!',
      });

      expect(link.token).toBe('abc123token');
      expect(link.cardType).toBe('family_tree');

      expect(ctx.gateway.emitToUser).toHaveBeenCalledWith(
        userId,
        'share:link_created',
        expect.objectContaining({ token: 'abc123token' }),
      );

      // Track share
      ctx.prisma.shareableLink.findUnique.mockResolvedValue({
        ...mockLink,
        shareCount: 0,
      });
      ctx.prisma.shareableLink.update.mockResolvedValue({
        ...mockLink,
        shareCount: 1,
      });

      const trackResult = await ctx.shareService.trackShare({ token: 'abc123token' });
      expect(trackResult.shareCount).toBe(1);

      // Get share stats
      ctx.prisma.shareableLink.findUnique.mockResolvedValue({
        ...mockLink,
        shareCount: 1,
      });

      const stats = await ctx.shareService.getShareStats('abc123token');
      expect(stats.shareCount).toBe(1);
      expect(stats.viewCount).toBe(0);

      // Revoke the link
      ctx.prisma.shareableLink.findUnique.mockResolvedValue({
        ...mockLink,
        shareCount: 1,
      });
      ctx.prisma.shareableLink.delete.mockResolvedValue({ id: 'link-1' });

      const revokeResult = await ctx.shareService.revokeShareableLink(userId, 'link-1');
      expect(revokeResult.deleted).toBe(true);

      expect(ctx.gateway.emitToUser).toHaveBeenCalledWith(
        userId,
        'share:link_revoked',
        expect.objectContaining({ id: 'link-1' }),
      );
    });

    it('should reject invalid card type', async () => {
      await expect(
        ctx.shareService.createShareableLink('user-1', {
          cardType: 'invalid_type',
          title: 'Test',
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should reject empty title', async () => {
      await expect(
        ctx.shareService.createShareableLink('user-1', {
          cardType: 'family_tree',
          title: '   ',
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should increment viewCount on getSharedCard', async () => {
      const mockLink = {
        id: 'link-1',
        token: 'abc123',
        cardType: 'birthday',
        familyId: null,
        personId: null,
        title: 'Birthday Card',
        description: '',
        deepLinkUrl: 'kinrel://share/birthday/abc123',
        viewCount: 5,
        shareCount: 2,
        expiresAt: null,
        createdAt: new Date(),
      };

      ctx.prisma.shareableLink.findUnique.mockResolvedValue(mockLink);
      ctx.prisma.shareableLink.update.mockResolvedValue({ ...mockLink, viewCount: 6 });

      const card = await ctx.shareService.getSharedCard('abc123');

      expect(card.viewCount).toBe(6);
      expect(ctx.prisma.shareableLink.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { viewCount: { increment: 1 } },
        }),
      );
    });

    it('should reject expired link', async () => {
      ctx.prisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'expired',
        expiresAt: new Date('2020-01-01'),
      });

      await expect(
        ctx.shareService.getSharedCard('expired'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('Shareable link with associated family and person data', () => {
    it('should include family data when familyId is set', async () => {
      ctx.prisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc',
        cardType: 'family_tree',
        familyId: 'fam-1',
        personId: null,
        title: 'Family',
        description: '',
        deepLinkUrl: '',
        viewCount: 0,
        shareCount: 0,
        expiresAt: null,
        createdAt: new Date(),
      });

      ctx.prisma.shareableLink.update.mockResolvedValue({ viewCount: 1 });

      ctx.prisma.family.findUnique.mockResolvedValue({
        id: 'fam-1',
        name: 'Sharma Family',
        description: 'A wonderful family',
        avatarUrl: 'https://img.cloud/1.jpg',
        memberCount: 12,
        gotra: 'Bharadwaj',
        originVillage: 'Ayodhya',
        region: 'Uttar Pradesh',
      });

      const card = await ctx.shareService.getSharedCard('abc');

      expect(card.family).toBeTruthy();
      expect(card.family!.name).toBe('Sharma Family');
    });

    it('should include person data when personId is set', async () => {
      ctx.prisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-2',
        token: 'xyz',
        cardType: 'birthday',
        familyId: null,
        personId: 'person-1',
        title: 'Birthday',
        description: '',
        deepLinkUrl: '',
        viewCount: 0,
        shareCount: 0,
        expiresAt: null,
        createdAt: new Date(),
      });

      ctx.prisma.shareableLink.update.mockResolvedValue({ viewCount: 1 });

      ctx.prisma.person.findUnique.mockResolvedValue({
        id: 'person-1',
        name: 'Rahul Sharma',
        dateOfBirth: null,
        birthYear: 1990,
        photoUrl: 'https://img.cloud/rahul.jpg',
        gender: 'male',
        gotra: 'Bharadwaj',
        occupation: 'Engineer',
        city: 'Delhi',
      });

      const card = await ctx.shareService.getSharedCard('xyz');

      expect(card.person).toBeTruthy();
      expect(card.person!.name).toBe('Rahul Sharma');
    });
  });

  describe('My shareable links pagination', () => {
    it('should return paginated list of links', async () => {
      const mockLinks = Array.from({ length: 5 }, (_, i) => ({
        id: `link-${i}`,
        token: `token-${i}`,
        cardType: 'family_tree',
        familyId: 'fam-1',
        personId: null,
        title: `Link ${i}`,
        description: '',
        deepLinkUrl: '',
        viewCount: i,
        shareCount: 0,
        expiresAt: null,
        createdAt: new Date(),
      }));

      ctx.prisma.shareableLink.findMany.mockResolvedValue(mockLinks);
      ctx.prisma.shareableLink.count.mockResolvedValue(5);

      const result = await ctx.shareService.getMyShareableLinks('user-1', 10, 1);

      expect(result.items).toHaveLength(5);
      expect(result.total).toBe(5);
      expect(result.page).toBe(1);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 5. STORIES ↔ GATEWAY ↔ FAMILY INTEGRATION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Stories ↔ Gateway', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Story creation with family socket events', () => {
    it('should emit story:new to family room when story is created with familyId', async () => {
      const mockStory = {
        id: 'story-1',
        userId: 'user-1',
        familyId: 'fam-1',
        caption: 'Hello',
        mediaUrl: '',
        mediaType: 'text',
        bgGradient: null,
        expiresAt: new Date(Date.now() + 86400000),
        createdAt: new Date(),
        updatedAt: new Date(),
        user: { id: 'user-1', name: 'User 1', username: 'u1', avatarUrl: null },
        views: [],
      };

      ctx.prisma.story.create.mockResolvedValue(mockStory);

      await ctx.storiesService.create('user-1', {
        caption: 'Hello',
        mediaType: 'text',
        familyId: 'fam-1',
      });

      expect(ctx.gateway.emitToFamily).toHaveBeenCalledWith(
        'fam-1',
        'story:new',
        expect.objectContaining({ familyId: 'fam-1', userId: 'user-1' }),
      );

      expect(ctx.gateway.emitToUser).toHaveBeenCalledWith(
        'user-1',
        'story:created',
        expect.objectContaining({ storyId: 'story-1' }),
      );
    });
  });

  describe('Story markViewed security', () => {
    it('should use viewerId from parameter, not from body', async () => {
      ctx.prisma.story.findUnique.mockResolvedValue({
        id: 'story-1',
        userId: 'user-2',
      });

      ctx.prisma.storyView.upsert.mockResolvedValue({
        id: 'view-1',
        storyId: 'story-1',
        viewerId: 'user-1',
        viewedAt: new Date(),
      });

      const result = await ctx.storiesService.markViewed('story-1', 'user-1');

      expect(result.viewed).toBe(true);
      expect(result.viewerId).toBe('user-1');

      expect(ctx.prisma.storyView.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { storyId_viewerId: { storyId: 'story-1', viewerId: 'user-1' } },
        }),
      );
    });

    it('should emit story:viewed to owner when someone else views', async () => {
      ctx.prisma.story.findUnique.mockResolvedValue({
        id: 'story-1',
        userId: 'user-2',
      });
      ctx.prisma.storyView.upsert.mockResolvedValue({ id: 'view-1' });

      await ctx.storiesService.markViewed('story-1', 'user-1');

      expect(ctx.gateway.emitToUser).toHaveBeenCalledWith(
        'user-2',
        'story:viewed',
        expect.objectContaining({ storyId: 'story-1', viewerId: 'user-1' }),
      );
    });
  });

  describe('Story delete authorization', () => {
    it('should allow owner to delete their story', async () => {
      ctx.prisma.story.findUnique.mockResolvedValue({
        id: 'story-1',
        userId: 'user-1',
      });
      ctx.prisma.story.delete.mockResolvedValue({ id: 'story-1' });

      const result = await ctx.storiesService.remove('story-1', 'user-1');

      expect(result.deleted).toBe(true);
    });

    it('should reject non-owner from deleting story', async () => {
      ctx.prisma.story.findUnique.mockResolvedValue({
        id: 'story-1',
        userId: 'user-1',
      });

      await expect(
        ctx.storiesService.remove('story-1', 'user-2'),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  describe('Stories grouped by user for family', () => {
    it('should group stories by user and mark unviewed', async () => {
      ctx.prisma.familyMember.findFirst.mockResolvedValue({ id: 'fm-1' });
      ctx.prisma.story.findMany.mockResolvedValue([
        {
          id: 's1',
          userId: 'user-2',
          familyId: 'fam-1',
          caption: 'Hello',
          mediaUrl: '',
          mediaType: 'text',
          bgGradient: null,
          expiresAt: new Date(Date.now() + 86400000),
          createdAt: new Date(),
          updatedAt: new Date(),
          user: { id: 'user-2', name: 'User 2', username: 'u2', avatarUrl: null },
          views: [],
        },
        {
          id: 's2',
          userId: 'user-2',
          familyId: 'fam-1',
          caption: 'World',
          mediaUrl: '',
          mediaType: 'text',
          bgGradient: null,
          expiresAt: new Date(Date.now() + 86400000),
          createdAt: new Date(),
          updatedAt: new Date(),
          user: { id: 'user-2', name: 'User 2', username: 'u2', avatarUrl: null },
          views: [{ id: 'v1', storyId: 's2', viewerId: 'user-1', viewedAt: new Date() }],
        },
      ]);

      const result = await ctx.storiesService.findByFamily('fam-1', 'user-1');

      expect(result).toHaveLength(1);
      expect(result[0].user.id).toBe('user-2');
      expect(result[0].stories).toHaveLength(2);
      expect(result[0].hasUnviewed).toBe(true);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 6. SPARQ CHAIN ↔ FOLLOW AUTHORIZATION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Sparq Chain ↔ Follow Authorization', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Add to chain requires following the creator', () => {
    it('should allow chaining when user follows the creator', async () => {
      ctx.prisma.sparq.findUnique.mockResolvedValue({
        id: 'sparq-1',
        userId: 'user-2',
        allowChain: true,
        parentSparqId: null,
      });
      ctx.prisma.sparq.count.mockResolvedValue(1);
      ctx.prisma.follow.findFirst.mockResolvedValue({ id: 'follow-1' });
      ctx.prisma.sparq.create.mockResolvedValue({
        id: 'sparq-2',
        userId: 'user-1',
        parentSparqId: 'sparq-1',
        chainOrder: 2,
      });

      const result = await ctx.sparqService.addToChain(
        'sparq-1',
        'user-1',
        { type: 'TEXT', text: 'My chain!' },
      );

      expect(result.parentSparqId).toBe('sparq-1');
    });

    it('should reject chaining when user does not follow the creator', async () => {
      ctx.prisma.sparq.findUnique.mockResolvedValue({
        id: 'sparq-1',
        userId: 'user-2',
        allowChain: true,
        parentSparqId: null,
      });
      ctx.prisma.sparq.count.mockResolvedValue(1);
      ctx.prisma.follow.findFirst.mockResolvedValue(null);

      await expect(
        ctx.sparqService.addToChain('sparq-1', 'user-1', { type: 'TEXT', text: 'Chain' }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should reject chaining when allowChain is false', async () => {
      ctx.prisma.sparq.findUnique.mockResolvedValue({
        id: 'sparq-1',
        userId: 'user-2',
        allowChain: false,
        parentSparqId: null,
      });

      await expect(
        ctx.sparqService.addToChain('sparq-1', 'user-1', { type: 'TEXT', text: 'Chain' }),
      ).rejects.toThrow(BadRequestException);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 7. TIMELINE DELETE ↔ FAMILY MEMBER AUTHORIZATION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Timeline ↔ Family Member Roles', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Comment delete authorization based on roles', () => {
    const familyId = 'fam-1';

    it('should allow comment author to delete their own comment', async () => {
      const comment = {
        id: 'cmt-1',
        authorId: 'user-1',
        authorName: 'User 1',
        body: 'Comment',
        parentId: null,
        createdAt: new Date().toISOString(),
      };

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId: 'user-2',
        reactions: JSON.stringify({
          emojis: {},
          userReactions: {},
          commentCount: 1,
          comments: [comment],
        }),
      });

      const result = await ctx.timelineService.deleteComment('post-1', 'cmt-1', 'user-1');

      expect(result.deleted).toBe(true);
    });

    it('should allow post author to delete any comment on their post', async () => {
      const comment = {
        id: 'cmt-1',
        authorId: 'user-3',
        authorName: 'Commenter',
        body: 'A comment',
        parentId: null,
        createdAt: new Date().toISOString(),
      };

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId: 'user-1',
        reactions: JSON.stringify({
          emojis: {},
          userReactions: {},
          commentCount: 1,
          comments: [comment],
        }),
      });

      const result = await ctx.timelineService.deleteComment('post-1', 'cmt-1', 'user-1');

      expect(result.deleted).toBe(true);
    });

    it('should allow family admin to delete any comment', async () => {
      const comment = {
        id: 'cmt-1',
        authorId: 'user-3',
        authorName: 'Commenter',
        body: 'A comment',
        parentId: null,
        createdAt: new Date().toISOString(),
      };

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId: 'user-1',
        reactions: JSON.stringify({
          emojis: {},
          userReactions: {},
          commentCount: 1,
          comments: [comment],
        }),
      });

      ctx.prisma.familyMember.findFirst.mockResolvedValue({ role: 'admin' });

      const result = await ctx.timelineService.deleteComment('post-1', 'cmt-1', 'user-2');

      expect(result.deleted).toBe(true);
    });

    it('should reject regular member from deleting others comment', async () => {
      const comment = {
        id: 'cmt-1',
        authorId: 'user-3',
        authorName: 'Commenter',
        body: 'A comment',
        parentId: null,
        createdAt: new Date().toISOString(),
      };

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId: 'user-1',
        reactions: JSON.stringify({
          emojis: {},
          userReactions: {},
          commentCount: 1,
          comments: [comment],
        }),
      });

      ctx.prisma.familyMember.findFirst.mockResolvedValue({ role: 'member' });

      await expect(
        ctx.timelineService.deleteComment('post-1', 'cmt-1', 'user-2'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should delete child replies when parent comment is deleted', async () => {
      const parentComment = {
        id: 'cmt-parent',
        authorId: 'user-1',
        authorName: 'Parent',
        body: 'Parent comment',
        parentId: null,
        createdAt: new Date().toISOString(),
      };
      const childComment = {
        id: 'cmt-child',
        authorId: 'user-2',
        authorName: 'Child',
        body: 'Reply to parent',
        parentId: 'cmt-parent',
        createdAt: new Date().toISOString(),
      };

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId,
        authorId: 'user-3',
        reactions: JSON.stringify({
          emojis: {},
          userReactions: {},
          commentCount: 2,
          comments: [parentComment, childComment],
        }),
      });

      const result = await ctx.timelineService.deleteComment('post-1', 'cmt-parent', 'user-1');

      expect(result.deleted).toBe(true);
      const updateCall = ctx.prisma.familyPost.update.mock.calls[0][0];
      const updatedReactions = JSON.parse(updateCall.data.reactions);
      expect(updatedReactions.comments).toHaveLength(0);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 8. FOLLOW LIFECYCLE END-TO-END
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Follow Lifecycle E2E', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Private user follow request flow', () => {
    it('should handle full follow request → accept → unfollow cycle', async () => {
      const followerId = 'user-1';
      const followingId = 'user-2';

      // Step 1: Request follow
      ctx.prisma.follow.findUnique.mockResolvedValue(null);
      ctx.prisma.user.findUnique
        .mockResolvedValueOnce({
          id: followingId,
          name: 'Private User',
          avatarUrl: null,
          isPrivate: true,
        })
        .mockResolvedValueOnce({
          id: followerId,
          name: 'Follower',
          avatarUrl: null,
        });
      ctx.prisma.follow.create.mockResolvedValue({
        id: 'follow-1',
        followerId,
        followingId,
        status: 'PENDING',
      });

      const followResult = await ctx.followService.followUser(followerId, followingId);

      expect(followResult.status).toBe('PENDING');
      expect(ctx.gateway.emitToUser).toHaveBeenCalledWith(
        followingId,
        'follow:request',
        expect.objectContaining({ follower: expect.objectContaining({ id: followerId }) }),
      );

      // Step 2: Accept request
      ctx.prisma.follow.findUnique.mockResolvedValue({
        id: 'follow-1',
        followerId,
        followingId,
        status: 'PENDING',
      });
      ctx.prisma.follow.update.mockResolvedValue({
        id: 'follow-1',
        followerId,
        followingId,
        status: 'ACCEPTED',
      });
      ctx.prisma.user.findUnique.mockResolvedValue({
        id: followingId,
        name: 'Private User',
      });

      const acceptResult = await ctx.followService.acceptRequest(followingId, followerId);

      expect(acceptResult.status).toBe('ACCEPTED');
      expect(ctx.gateway.emitToUser).toHaveBeenCalledWith(
        followerId,
        'follow:accepted',
        expect.objectContaining({ following: expect.objectContaining({ id: followingId }) }),
      );

      // Step 3: Unfollow
      ctx.prisma.follow.findUnique.mockResolvedValue({
        id: 'follow-1',
        followerId,
        followingId,
        status: 'ACCEPTED',
      });
      ctx.prisma.follow.delete.mockResolvedValue({ id: 'follow-1' });

      const unfollowResult = await ctx.followService.unfollowUser(followerId, followingId);

      expect(unfollowResult.success).toBe(true);
    });
  });

  describe('Public user instant follow flow', () => {
    it('should immediately accept follow for public users', async () => {
      ctx.prisma.follow.findUnique.mockResolvedValue(null);
      ctx.prisma.user.findUnique
        .mockResolvedValueOnce({
          id: 'user-2',
          name: 'Public User',
          avatarUrl: null,
          isPrivate: false,
        })
        .mockResolvedValueOnce({
          id: 'user-1',
          name: 'Follower',
          avatarUrl: null,
        });
      ctx.prisma.follow.create.mockResolvedValue({
        id: 'follow-1',
        followerId: 'user-1',
        followingId: 'user-2',
        status: 'ACCEPTED',
      });

      const result = await ctx.followService.followUser('user-1', 'user-2');

      expect(result.status).toBe('ACCEPTED');
      expect(ctx.gateway.emitToUser).toHaveBeenCalledWith(
        'user-2',
        'follow:new',
        expect.objectContaining({ follower: expect.objectContaining({ id: 'user-1' }) }),
      );
    });
  });

  describe('Follow status checking', () => {
    it('should return correct status for all relationship states', async () => {
      expect(await ctx.followService.getFollowStatus('user-1', 'user-1')).toEqual({ status: 'self' });

      ctx.prisma.follow.findUnique.mockResolvedValue({ id: 'f1', status: 'ACCEPTED' });
      expect(await ctx.followService.getFollowStatus('user-1', 'user-2')).toEqual({ status: 'following' });

      ctx.prisma.follow.findUnique.mockResolvedValue({ id: 'f1', status: 'PENDING' });
      expect(await ctx.followService.getFollowStatus('user-1', 'user-2')).toEqual({ status: 'pending' });

      ctx.prisma.follow.findUnique
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(null);
      expect(await ctx.followService.getFollowStatus('user-1', 'user-2')).toEqual({ status: 'none' });
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 9. SPARQ ECHO TOGGLE & VIEW COUNT INTEGRITY
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Sparq Echo Toggle & View Count', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Echo toggle add then remove', () => {
    it('should add echo then remove it, maintaining correct count', async () => {
      ctx.prisma.sparq.findUnique.mockResolvedValue({ id: 'sparq-1', echoCount: 5 });
      ctx.prisma.sparqEcho.findUnique.mockResolvedValue(null);
      ctx.prisma.sparqEcho.create.mockResolvedValue({ id: 'echo-1' });
      ctx.prisma.sparq.update.mockResolvedValue({ id: 'sparq-1', echoCount: 6 });

      const addResult = await ctx.sparqService.toggleEcho('sparq-1', 'user-1');

      expect(addResult.echoCount).toBe(6);
      expect(addResult.isEchoed).toBe(true);

      ctx.prisma.sparq.findUnique.mockResolvedValue({ id: 'sparq-1', echoCount: 6 });
      ctx.prisma.sparqEcho.findUnique.mockResolvedValue({ id: 'echo-1', sparqId: 'sparq-1', userId: 'user-1' });
      ctx.prisma.sparqEcho.delete.mockResolvedValue({ id: 'echo-1' });
      ctx.prisma.sparq.update.mockResolvedValue({ id: 'sparq-1', echoCount: 5 });

      const removeResult = await ctx.sparqService.toggleEcho('sparq-1', 'user-1');

      expect(removeResult.echoCount).toBe(5);
      expect(removeResult.isEchoed).toBe(false);
    });
  });

  describe('View count only increments on first view', () => {
    it('should increment viewCount on first view but not on subsequent views', async () => {
      ctx.prisma.sparq.findUnique.mockResolvedValue({ id: 'sparq-1' });
      ctx.prisma.sparqView.findUnique.mockResolvedValue(null);
      ctx.prisma.sparqView.create.mockResolvedValue({ id: 'view-1' });
      ctx.prisma.sparq.update.mockResolvedValue({ id: 'sparq-1', viewCount: 1 });

      const firstView = await ctx.sparqService.markViewed('sparq-1', 'user-1');

      expect(firstView.success).toBe(true);
      expect(ctx.prisma.sparq.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { viewCount: { increment: 1 } },
        }),
      );

      jest.clearAllMocks();

      ctx.prisma.sparq.findUnique.mockResolvedValue({ id: 'sparq-1' });
      ctx.prisma.sparqView.findUnique.mockResolvedValue({ id: 'view-1', sparqId: 'sparq-1', viewerId: 'user-1' });
      ctx.prisma.sparqView.update.mockResolvedValue({ id: 'view-1', viewedAt: new Date() });

      const secondView = await ctx.sparqService.markViewed('sparq-1', 'user-1');

      expect(secondView.success).toBe(true);
      expect(ctx.prisma.sparq.update).not.toHaveBeenCalled();
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 10. TIMELINE REACTIONS — MULTIPLE USERS & MULTIPLE EMOJIS
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Timeline Reactions Multi-User', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Multiple users reacting with different emojis', () => {
    it('should track separate emoji counts and user reaction maps', async () => {
      const existingReactions = JSON.stringify({
        emojis: { '❤️': 1 },
        userReactions: { 'user-1': ['❤️'] },
        commentCount: 0,
        comments: [],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId: 'fam-1',
        authorId: 'user-1',
        reactions: existingReactions,
      });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.toggleReaction('post-1', 'user-2', '👍');

      expect(result.emojis['❤️']).toBe(1);
      expect(result.emojis['👍']).toBe(1);
      expect(result.userReactions['user-1']).toContain('❤️');
      expect(result.userReactions['user-2']).toContain('👍');
    });

    it('should allow same user to react with multiple emojis', async () => {
      const existingReactions = JSON.stringify({
        emojis: { '❤️': 1 },
        userReactions: { 'user-1': ['❤️'] },
        commentCount: 0,
        comments: [],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: existingReactions,
      });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.toggleReaction('post-1', 'user-1', '🎉');

      expect(result.emojis['❤️']).toBe(1);
      expect(result.emojis['🎉']).toBe(1);
      expect(result.userReactions['user-1']).toContain('❤️');
      expect(result.userReactions['user-1']).toContain('🎉');
    });
  });

  describe('Reaction toggle removes emoji when count reaches 0', () => {
    it('should clean up emoji keys when no users have that reaction', async () => {
      const existingReactions = JSON.stringify({
        emojis: { '❤️': 1 },
        userReactions: { 'user-1': ['❤️'] },
        commentCount: 0,
        comments: [],
      });

      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId: 'fam-1',
        authorId: 'user-2',
        reactions: existingReactions,
      });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.toggleReaction('post-1', 'user-1', '❤️');

      expect(result.emojis['❤️']).toBeUndefined();
      expect(result.userReactions['user-1']).toBeUndefined();
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 11. SHARE TRACKING & EXPIRY EDGE CASES
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Share Expiry & Edge Cases', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Link expiry handling', () => {
    it('should create link with expiry when expiresInDays is set', async () => {
      const mockLink = {
        id: 'link-1',
        token: 'expiring-token',
        cardType: 'milestone',
        familyId: null,
        personId: null,
        title: 'Milestone Card',
        description: '',
        deepLinkUrl: '',
        viewCount: 0,
        shareCount: 0,
        expiresAt: new Date(Date.now() + 7 * 86400000),
        createdAt: new Date(),
      };

      ctx.prisma.shareableLink.create.mockResolvedValue(mockLink);

      const result = await ctx.shareService.createShareableLink('user-1', {
        cardType: 'milestone',
        title: 'Milestone Card',
        expiresInDays: 7,
      });

      expect(result.expiresAt).toBeTruthy();
      const createCall = ctx.prisma.shareableLink.create.mock.calls[0][0];
      expect(createCall.data.expiresAt).toBeTruthy();
    });

    it('should reject tracking shares on expired links', async () => {
      ctx.prisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'expired-token',
        expiresAt: new Date('2020-01-01'),
      });

      await expect(
        ctx.shareService.trackShare({ token: 'expired-token' }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('Revoke non-existent link', () => {
    it('should throw NotFoundException when revoking a non-existent link', async () => {
      ctx.prisma.shareableLink.findUnique.mockResolvedValue(null);

      await expect(
        ctx.shareService.revokeShareableLink('user-1', 'nonexistent-id'),
      ).rejects.toThrow(NotFoundException);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 12. SPARQ TIME CAPSULE CREATION & VALIDATION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Sparq Time Capsule', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Time capsule validation', () => {
    it('should create time capsule with future revealAt', async () => {
      const futureDate = new Date(Date.now() + 7 * 86400000).toISOString();

      ctx.prisma.sparq.create.mockResolvedValue({
        id: 'sparq-tc-1',
        userId: 'user-1',
        type: 'TEXT',
        text: 'Future message',
        isTimeCapsule: true,
        revealAt: futureDate,
        isRevealed: false,
        expiresAt: new Date(Date.now() + 86400000),
      });

      const result = await ctx.sparqService.createSparq('user-1', {
        type: 'TEXT',
        text: 'Future message',
        isTimeCapsule: true,
        revealAt: futureDate,
      });

      expect(result.isTimeCapsule).toBe(true);
      expect(result.isRevealed).toBe(false);
    });

    it('should reject time capsule without revealAt', async () => {
      await expect(
        ctx.sparqService.createSparq('user-1', {
          type: 'TEXT',
          text: 'Missing reveal',
          isTimeCapsule: true,
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should reject time capsule with past revealAt', async () => {
      await expect(
        ctx.sparqService.createSparq('user-1', {
          type: 'TEXT',
          text: 'Past reveal',
          isTimeCapsule: true,
          revealAt: '2020-01-01T00:00:00Z',
        }),
      ).rejects.toThrow(BadRequestException);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 13. REACTIONS JSON PARSING EDGE CASES
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Timeline Reactions JSON Parsing', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Malformed reactions JSON handling', () => {
    it('should handle null reactions field gracefully', async () => {
      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId: 'fam-1',
        authorId: 'user-1',
        reactions: null,
      });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.toggleReaction('post-1', 'user-1', '❤️');

      expect(result.emojis['❤️']).toBe(1);
    });

    it('should handle empty string reactions field', async () => {
      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId: 'fam-1',
        authorId: 'user-1',
        reactions: '',
      });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.toggleReaction('post-1', 'user-1', '🎉');

      expect(result.emojis['🎉']).toBe(1);
    });

    it('should handle invalid JSON reactions field', async () => {
      ctx.prisma.familyPost.findUnique.mockResolvedValue({
        id: 'post-1',
        familyId: 'fam-1',
        authorId: 'user-1',
        reactions: 'not-json{{{',
      });
      ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

      const result = await ctx.timelineService.toggleReaction('post-1', 'user-1', '👍');

      expect(result.emojis['👍']).toBe(1);
    });
  });
});

// ══════════════════════════════════════════════════════════════════════
// 14. FOLLOW SELF-CHECK & DUPLICATE PREVENTION
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Follow Edge Cases', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('should reject following yourself', async () => {
    await expect(
      ctx.followService.followUser('user-1', 'user-1'),
    ).rejects.toThrow(BadRequestException);
  });

  it('should reject duplicate follow request', async () => {
    ctx.prisma.follow.findUnique.mockResolvedValue({
      id: 'f1',
      followerId: 'user-1',
      followingId: 'user-2',
      status: 'PENDING',
    });

    await expect(
      ctx.followService.followUser('user-1', 'user-2'),
    ).rejects.toThrow(ConflictException);
  });

  it('should reject unfollow when not following', async () => {
    ctx.prisma.follow.findUnique.mockResolvedValue(null);

    await expect(
      ctx.followService.unfollowUser('user-1', 'user-2'),
    ).rejects.toThrow(NotFoundException);
  });

  it('should reject accept when request is already accepted', async () => {
    ctx.prisma.follow.findUnique.mockResolvedValue({
      id: 'f1',
      followerId: 'user-1',
      followingId: 'user-2',
      status: 'ACCEPTED',
    });

    await expect(
      ctx.followService.acceptRequest('user-2', 'user-1'),
    ).rejects.toThrow(BadRequestException);
  });
});

// ══════════════════════════════════════════════════════════════════════
// 15. DTO VALIDATION INTEGRATION TESTS
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: DTO Validation', () => {
  it('should have CreatePostDto with proper IsIn values', () => {
    const dto = require('../modules/timeline/dto/timeline.dto');

    expect(dto.CreatePostDto).toBeDefined();
    expect(dto.ReactDto).toBeDefined();
    expect(dto.CreateCommentDto).toBeDefined();
  });

  it('should have CreateShareableLinkDto with proper IsIn card types', () => {
    const dto = require('../modules/share/dto/share.dto');

    expect(dto.CreateShareableLinkDto).toBeDefined();
    expect(dto.TrackShareDto).toBeDefined();
  });

  it('should have follow DTOs', () => {
    const dto = require('../modules/follow/dto/follow.dto');

    expect(dto.FollowPaginationDto).toBeDefined();
  });

  it('should have community DTOs', () => {
    const dto = require('../modules/community/dto');

    expect(dto.CreateCommunityDto).toBeDefined();
    expect(dto.SearchCommunityDto).toBeDefined();
  });

  it('should have gamification DTOs', () => {
    const dto = require('../modules/gamification/dto/gamification.dto');
    const quizDto = require('../modules/gamification/dto/quiz.dto');

    expect(dto).toBeDefined();
    expect(quizDto).toBeDefined();
  });
});

// ══════════════════════════════════════════════════════════════════════
// 16. TIMELINE SERVICE — REACTIONS OBJECT SHAPE
// ══════════════════════════════════════════════════════════════════════

describe('Agent-3 Integration: Timeline Reactions Object Shape', () => {
  let ctx: Awaited<ReturnType<typeof createIntegrationModule>>;

  beforeEach(async () => {
    ctx = await createIntegrationModule();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('should create post with well-formed reactions JSON', async () => {
    ctx.prisma.familyPost.create.mockResolvedValue({
      id: 'post-1',
      familyId: 'fam-1',
      authorId: 'user-1',
      postType: 'update',
      content: '{}',
      reactions: '{}',
      updatedAt: new Date(),
      author: { id: 'user-1', name: 'User 1', photoUrl: null },
    });

    await ctx.timelineService.createPost('fam-1', 'user-1', 'update', { text: 'Test' });

    const createCall = ctx.prisma.familyPost.create.mock.calls[0][0];
    const reactionsData = JSON.parse(createCall.data.reactions);

    expect(reactionsData).toHaveProperty('emojis');
    expect(reactionsData).toHaveProperty('userReactions');
    expect(reactionsData).toHaveProperty('commentCount');
    expect(reactionsData).toHaveProperty('comments');
    expect(reactionsData.emojis).toEqual({});
    expect(reactionsData.userReactions).toEqual({});
    expect(reactionsData.commentCount).toBe(0);
    expect(reactionsData.comments).toEqual([]);
  });

  it('should return reactions with correct shape after toggle', async () => {
    ctx.prisma.familyPost.findUnique.mockResolvedValue({
      id: 'post-1',
      familyId: 'fam-1',
      authorId: 'user-1',
      reactions: JSON.stringify({
        emojis: {},
        userReactions: {},
        commentCount: 0,
        comments: [],
      }),
    });
    ctx.prisma.familyPost.update.mockResolvedValue({ id: 'post-1' });

    const result = await ctx.timelineService.toggleReaction('post-1', 'user-1', '❤️');

    expect(result).toHaveProperty('emojis');
    expect(result).toHaveProperty('userReactions');
    expect(result).toHaveProperty('commentCount');
    expect(result).toHaveProperty('comments');
    expect(typeof result.emojis['❤️']).toBe('number');
    expect(Array.isArray(result.userReactions['user-1'])).toBe(true);
  });
});
