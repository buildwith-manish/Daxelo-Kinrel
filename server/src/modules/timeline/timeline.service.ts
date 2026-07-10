import { Injectable, ForbiddenException, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { CreateCommentDto } from './dto/timeline.dto';

/** Shape of the reactions JSON stored on FamilyPost */
export interface ReactionsData {
  emojis: Record<string, number>;
  userReactions: Record<string, string[]>;
  commentCount: number;
  comments: CommentData[];
}

/** Shape of a single comment stored in the reactions JSON */
export interface CommentData {
  id: string;
  authorId: string;
  authorName: string;
  body: string;
  parentId: string | null;
  createdAt: string;
}

@Injectable()
export class TimelineService {
  private readonly logger = new Logger(TimelineService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: KinrelGateway,
  ) {}

  // ── Helpers ────────────────────────────────────────────────────────

  /** Parse the reactions JSON field safely, falling back to a blank slate. */
  private parseReactions(raw: string | null | undefined): ReactionsData {
    try {
      const parsed = JSON.parse(raw || '{}');
      return {
        emojis: parsed.emojis ?? {},
        userReactions: parsed.userReactions ?? {},
        commentCount: parsed.commentCount ?? 0,
        comments: parsed.comments ?? [],
      };
    } catch {
      return { emojis: {}, userReactions: {}, commentCount: 0, comments: [] };
    }
  }

  /** Serialize the ReactionsData back to a JSON string for storage. */
  private serializeReactions(data: ReactionsData): string {
    return JSON.stringify(data);
  }

  /** Generate a simple unique ID for inline comments. */
  private generateId(): string {
    return `cmt_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
  }

  // ── Read Operations ───────────────────────────────────────────────

  /** Returns paginated family posts ordered by newest first with cursor-based pagination. */
  private async assertMember(familyId: string, userId: string) {
    const m = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!m) throw new ForbiddenException('Not a member of this family');
    return m;
  }

  async getTimeline(familyId: string, userId: string, limit: number = 20, cursor?: string) {
    await this.assertMember(familyId, userId);
    const posts = await this.prisma.familyPost.findMany({
      where: { familyId },
      orderBy: { createdAt: 'desc' },
      take: limit + 1,
      skip: cursor ? 1 : 0,
      cursor: cursor ? { id: cursor } : undefined,
      select: {
        id: true,
        familyId: true,
        authorId: true,
        postType: true,
        content: true,
        reactions: true,
        createdAt: true,
        updatedAt: true,
        author: { select: { id: true, name: true, photoUrl: true } },
      },
    });

    const hasNextPage = posts.length > limit;
    const data = hasNextPage ? posts.slice(0, -1) : posts;
    const nextCursor = hasNextPage ? data[data.length - 1].id : null;

    return { data, nextCursor };
  }

  /**
   * Returns the home feed — a merged, paginated list of posts from:
   *   1. Families the current user has joined (all their family posts)
   *   2. Families where followed users are members (public families only)
   *
   * Posts are sorted by createdAt descending. Cursor-based pagination.
   */
  async getHomeFeed(userId: string, limit: number = 20, cursor?: string) {
    // ── Step 1: Gather family IDs from memberships ─────────────────────
    const myFamilyMemberships = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const myFamilyIds = myFamilyMemberships.map((m) => m.familyId);

    // ── Step 2: Gather family IDs from followed users' memberships ──────
    const following = await this.prisma.follow.findMany({
      where: { followerId: userId, status: 'ACCEPTED' },
      select: { followingId: true },
    });
    const followedUserIds = following.map((f) => f.followingId);

    let followedFamilyIds: string[] = [];
    if (followedUserIds.length > 0) {
      const followedFamilyMemberships = await this.prisma.familyMember.findMany({
        where: {
          userId: { in: followedUserIds },
          family: { isPublic: true, deletedAt: null },
        },
        select: { familyId: true },
        distinct: ['familyId'],
      });
      followedFamilyIds = followedFamilyMemberships.map((m) => m.familyId);
    }

    // ── Step 3: Combine family IDs (deduplicated) ──────────────────────
    const allFamilyIds = [...new Set([...myFamilyIds, ...followedFamilyIds])];

    if (allFamilyIds.length === 0) {
      return { data: [], nextCursor: null };
    }

    // ── Step 4: Fetch posts from all relevant families ─────────────────
    const whereClause: any = {
      familyId: { in: allFamilyIds },
    };

    if (cursor) {
      whereClause.id = { lt: cursor };
    }

    const posts = await this.prisma.familyPost.findMany({
      where: whereClause,
      orderBy: { createdAt: 'desc' },
      take: limit + 1,
      select: {
        id: true,
        familyId: true,
        authorId: true,
        postType: true,
        content: true,
        reactions: true,
        createdAt: true,
        updatedAt: true,
        author: { select: { id: true, name: true, photoUrl: true, photoThumb: true } },
        family: { select: { id: true, name: true, avatarUrl: true, isPublic: true } },
      },
    });

    const hasNextPage = posts.length > limit;
    const data = hasNextPage ? posts.slice(0, -1) : posts;
    const nextCursor = hasNextPage ? data[data.length - 1].id : null;

    // ── Step 5: Tag posts with source context ──────────────────────────
    const myFamilyIdSet = new Set(myFamilyIds);
    const enrichedData = data.map((post) => ({
      ...post,
      source: myFamilyIdSet.has(post.familyId) ? 'family' : 'following',
    }));

    return { data: enrichedData, nextCursor };
  }

  /** Creates a new post in the family timeline feed. */
  async createPost(familyId: string, authorId: string, postType: string, content: Record<string, any>) {
    const post = await this.prisma.familyPost.create({
      data: {
        familyId,
        userId,
        postType,
        content: JSON.stringify(content),
        reactions: JSON.stringify({ emojis: {}, userReactions: {}, commentCount: 0, comments: [] }),
      },
      include: {
        author: { select: { id: true, name: true, photoUrl: true } },
      },
    });

    // Emit socket event to family room
    this.gateway.emitToFamily(familyId, 'timeline:post_created', {
      id: post.id,
      type: 'timeline:post_created',
      familyId,
      updatedAt: post.updatedAt.toISOString(),
    });

    return post;
  }

  // ── Reaction Toggle ────────────────────────────────────────────────

  /**
   * Toggle a reaction on a post. If the user already reacted with the same
   * emoji, the reaction is removed (un-react). Otherwise it is added.
   * Returns the updated reactions object.
   */
  async toggleReaction(familyId: string, postId: string, userId: string, emoji: string) {
    await this.assertMember(familyId, userId);
    // Verify post exists
    const post = await this.prisma.familyPost.findUnique({ where: { id: postId } });
    if (!post) {
      throw new NotFoundException('Post not found');
    }

    const reactions = this.parseReactions(post.reactions as string);

    // Check if user already has this emoji
    const userEmojis = reactions.userReactions[userId] ?? [];
    const hasEmoji = userEmojis.includes(emoji);

    if (hasEmoji) {
      // Remove reaction
      reactions.userReactions[userId] = userEmojis.filter((e) => e !== emoji);
      if (reactions.userReactions[userId].length === 0) {
        delete reactions.userReactions[userId];
      }
      reactions.emojis[emoji] = Math.max(0, (reactions.emojis[emoji] ?? 1) - 1);
      if (reactions.emojis[emoji] === 0) {
        delete reactions.emojis[emoji];
      }
    } else {
      // Add reaction
      reactions.userReactions[userId] = [...userEmojis, emoji];
      reactions.emojis[emoji] = (reactions.emojis[emoji] ?? 0) + 1;
    }

    // Persist
    await this.prisma.familyPost.update({
      where: { id: postId },
      data: { reactions: this.serializeReactions(reactions) },
    });

    // Emit socket event
    this.gateway.emitToFamily(post.familyId, 'timeline:reaction', {
      id: postId,
      type: 'timeline:reaction',
      familyId: post.familyId,
      emoji,
      userId,
      action: hasEmoji ? 'removed' : 'added',
      updatedAt: new Date().toISOString(),
    });

    return reactions;
  }

  // ── Comments ───────────────────────────────────────────────────────

  /**
   * Get comments for a post.
   * Comments are stored in the reactions JSON field on FamilyPost.
   * TODO (Task-3): Migrate to dedicated Comment rows once schema adds familyPostId.
   */
  async getComments(postId: string, limit: number = 50, cursor?: string) {
    const post = await this.prisma.familyPost.findUnique({ where: { id: postId } });
    if (!post) {
      throw new NotFoundException('Post not found');
    }

    const reactions = this.parseReactions(post.reactions as string);
    let comments = [...reactions.comments].sort(
      (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
    );

    // Cursor-based pagination: skip comments with id <= cursor
    if (cursor) {
      const cursorIdx = comments.findIndex((c) => c.id === cursor);
      if (cursorIdx >= 0) {
        comments = comments.slice(cursorIdx + 1);
      }
    }

    const hasNextPage = comments.length > limit;
    const data = hasNextPage ? comments.slice(0, limit) : comments;
    const nextCursor = hasNextPage ? data[data.length - 1].id : null;

    return { data, nextCursor };
  }

  /**
   * Add a comment to a post.
   * The comment is stored in the reactions JSON field.
   * Author name is resolved from the User table automatically.
   */
  async addComment(
    postId: string,
    authorId: string,
    dto: CreateCommentDto,
  ) {
    const post = await this.prisma.familyPost.findUnique({ where: { id: postId } });
    if (!post) {
      throw new NotFoundException('Post not found');
    }

    // Resolve author name from User table
    const author = await this.prisma.user.findUnique({
      where: { id: authorId },
      select: { name: true },
    });
    const authorName = author?.name ?? 'Unknown';

    // Validate parentId if provided
    const reactions = this.parseReactions(post.reactions as string);
    if (dto.parentId) {
      const parentExists = reactions.comments.some((c) => c.id === dto.parentId);
      if (!parentExists) {
        throw new NotFoundException('Parent comment not found');
      }
    }

    const newComment: CommentData = {
      id: this.generateId(),
      userId,
      authorName,
      body: dto.body,
      parentId: dto.parentId ?? null,
      createdAt: new Date().toISOString(),
    };

    reactions.comments.push(newComment);
    reactions.commentCount = reactions.comments.length;

    await this.prisma.familyPost.update({
      where: { id: postId },
      data: { reactions: this.serializeReactions(reactions) },
    });

    // Emit socket event
    this.gateway.emitToFamily(post.familyId, 'timeline:comment', {
      id: postId,
      type: 'timeline:comment',
      familyId: post.familyId,
      comment: newComment,
      updatedAt: new Date().toISOString(),
    });

    return newComment;
  }

  /**
   * Delete a comment from a post.
   * Only the comment author or a family admin/owner can delete.
   */
  async deleteComment(postId: string, commentId: string, userId: string) {
    const post = await this.prisma.familyPost.findUnique({ where: { id: postId } });
    if (!post) {
      throw new NotFoundException('Post not found');
    }

    const reactions = this.parseReactions(post.reactions as string);
    const comment = reactions.comments.find((c) => c.id === commentId);
    if (!comment) {
      throw new NotFoundException('Comment not found');
    }

    // Authorization: comment author, post author, or family admin/owner
    const isCommentAuthor = comment.authorId === userId;
    const isPostAuthor = post.authorId === userId;
    let isFamilyAdmin = false;

    if (!isCommentAuthor && !isPostAuthor) {
      const membership = await this.prisma.familyMember.findFirst({
        where: { familyId: post.familyId, userId },
      });
      isFamilyAdmin = membership?.role === 'owner' || membership?.role === 'admin';
    }

    if (!isCommentAuthor && !isPostAuthor && !isFamilyAdmin) {
      throw new ForbiddenException('You can only delete your own comments');
    }

    // Remove the comment and any replies to it
    reactions.comments = reactions.comments.filter(
      (c) => c.id !== commentId && c.parentId !== commentId,
    );
    reactions.commentCount = reactions.comments.length;

    await this.prisma.familyPost.update({
      where: { id: postId },
      data: { reactions: this.serializeReactions(reactions) },
    });

    // Emit socket event
    this.gateway.emitToFamily(post.familyId, 'timeline:comment_deleted', {
      id: postId,
      type: 'timeline:comment_deleted',
      familyId: post.familyId,
      commentId,
      updatedAt: new Date().toISOString(),
    });

    return { deleted: true, commentId };
  }

  // ── Delete Post ────────────────────────────────────────────────────

  /**
   * Delete a post. Only the post author or a family admin/owner can delete.
   */
  async deletePost(postId: string, userId: string) {
    const post = await this.prisma.familyPost.findUnique({ where: { id: postId } });
    if (!post) {
      throw new NotFoundException('Post not found');
    }

    // Authorization: post author or family admin/owner
    const isPostAuthor = post.authorId === userId;
    let isFamilyAdmin = false;

    if (!isPostAuthor) {
      const membership = await this.prisma.familyMember.findFirst({
        where: { familyId: post.familyId, userId },
      });
      isFamilyAdmin = membership?.role === 'owner' || membership?.role === 'admin';
    }

    if (!isPostAuthor && !isFamilyAdmin) {
      throw new ForbiddenException('You can only delete your own posts');
    }

    const familyId = post.familyId;

    await this.prisma.familyPost.delete({ where: { id: postId } });

    // Emit socket event
    this.gateway.emitToFamily(familyId, 'timeline:post_deleted', {
      id: postId,
      type: 'timeline:post_deleted',
      familyId,
      updatedAt: new Date().toISOString(),
    });

    return { deleted: true, postId };
  }
}
