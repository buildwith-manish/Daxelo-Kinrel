import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  ConflictException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { CreateCommunityDto } from './dto/create-community.dto';
import { CreateCommentDto } from './dto/create-comment.dto';
import { RsvpDto } from './dto/rsvp.dto';

@Injectable()
export class CommunityService {
  private readonly logger = new Logger(CommunityService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ═══════════════════════════════════════════════════════════════════
  // Community CRUD
  // ═══════════════════════════════════════════════════════════════════

  async listCommunities(options: { type?: string; q?: string; page?: number; limit?: number }) {
    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(options.limit ?? 20, 100);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = {};
    if (options.type) where.type = options.type;
    if (options.q) {
      where.OR = [
        { name: { contains: options.q } },
        { description: { contains: options.q } },
        { gotraName: { contains: options.q } },
        { villageName: { contains: options.q } },
        { surname: { contains: options.q } },
      ];
    }

    const [communities, total] = await Promise.all([
      this.prisma.community.findMany({
        where,
        skip,
        take: limit,
        orderBy: { memberCount: 'desc' },
        include: { _count: { select: { members: true, posts: true, events: true } } },
      }),
      this.prisma.community.count({ where }),
    ]);

    return {
      communities,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    };
  }

  async createCommunity(dto: CreateCommunityDto) {
    const user = await this.prisma.user.findUnique({ where: { id: dto.creatorId } });
    if (!user) throw new NotFoundException('User not found');
    if (user.role !== 'admin' && user.role !== 'moderator') {
      throw new ForbiddenException('Insufficient permissions. Moderator or admin role required.');
    }

    const slug = dto.name
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .trim();

    const existing = await this.prisma.community.findUnique({ where: { slug } });
    if (existing) throw new ConflictException('A community with this name already exists');

    const community = await this.prisma.community.create({
      data: {
        type: dto.type,
        name: dto.name,
        slug,
        description: dto.description ?? null,
        coverImageUrl: dto.coverImageUrl ?? null,
        iconUrl: dto.iconUrl ?? null,
        isPrivate: dto.isPrivate ?? false,
        gotraName: dto.gotraName ?? null,
        villageName: dto.villageName ?? null,
        surname: dto.surname ?? null,
        region: dto.region ?? null,
        memberCount: 1,
      },
    });

    await this.prisma.communityMember.create({
      data: { communityId: community.id, userId: dto.creatorId, role: 'admin', joinedVia: 'creation' },
    });

    return { community };
  }

  async getCommunity(communityId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
      include: {
        members: { take: 10, orderBy: { joinedAt: 'desc' }, include: { user: { select: { id: true, name: true, email: true } } } },
        rules: { orderBy: { sortOrder: 'asc' } },
        _count: { select: { members: true, posts: true, events: true } },
      },
    });

    if (!community) throw new NotFoundException('Community not found');

    const recentPosts = await this.prisma.communityPost.count({
      where: { communityId, createdAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) } },
    });

    return {
      community,
      stats: {
        totalMembers: community._count.members,
        totalPosts: community._count.posts,
        totalEvents: community._count.events,
        recentPostsThisWeek: recentPosts,
      },
    };
  }

  async updateCommunity(communityId: string, body: Record<string, unknown>) {
    const { userId, name, description, coverImageUrl, iconUrl, isPrivate, isVerified, region } = body;

    if (!userId) throw new BadRequestException('userId is required');

    const membership = await this.prisma.communityMember.findFirst({
      where: { communityId, userId: userId as string, role: 'admin' },
    });
    if (!membership) throw new ForbiddenException('Only community admins can update the community');

    const updateData: Record<string, unknown> = {};
    if (name !== undefined) updateData.name = name;
    if (description !== undefined) updateData.description = description;
    if (coverImageUrl !== undefined) updateData.coverImageUrl = coverImageUrl;
    if (iconUrl !== undefined) updateData.iconUrl = iconUrl;
    if (isPrivate !== undefined) updateData.isPrivate = isPrivate;
    if (region !== undefined) updateData.region = region;

    if (isVerified !== undefined) {
      const user = await this.prisma.user.findUnique({ where: { id: userId as string } });
      if (user?.role === 'admin') updateData.isVerified = isVerified;
    }

    const community = await this.prisma.community.update({
      where: { id: communityId },
      data: updateData,
    });

    return { community };
  }

  async deleteCommunity(communityId: string, userId: string) {
    if (!userId) throw new BadRequestException('userId is required');

    const membership = await this.prisma.communityMember.findFirst({
      where: { communityId, userId, role: 'admin' },
    });
    if (!membership) throw new ForbiddenException('Only community admins can delete the community');

    await this.prisma.community.delete({ where: { id: communityId } });
    return { success: true };
  }

  async joinOrLeave(communityId: string, body: { userId: string; action: string }) {
    const { userId, action } = body;
    if (!userId) throw new BadRequestException('userId is required');

    const community = await this.prisma.community.findUnique({ where: { id: communityId } });
    if (!community) throw new NotFoundException('Community not found');

    if (action === 'leave') {
      const membership = await this.prisma.communityMember.findUnique({
        where: { communityId_userId: { communityId, userId } },
      });
      if (!membership) throw new BadRequestException('Not a member of this community');

      if (membership.role === 'admin') {
        const adminCount = await this.prisma.communityMember.count({ where: { communityId, role: 'admin' } });
        if (adminCount <= 1) throw new BadRequestException('Cannot leave as the last admin. Transfer admin role first.');
      }

      await this.prisma.communityMember.delete({ where: { communityId_userId: { communityId, userId } } });
      await this.prisma.community.update({ where: { id: communityId }, data: { memberCount: { decrement: 1 } } });

      return { success: true, action: 'left' };
    }

    // JOIN
    const existing = await this.prisma.communityMember.findUnique({
      where: { communityId_userId: { communityId, userId } },
    });
    if (existing) {
      if (existing.role === 'banned') throw new ForbiddenException('You have been banned from this community');
      throw new BadRequestException('Already a member of this community');
    }

    let joinVia = 'search';
    if (community.isPrivate) joinVia = 'invitation';

    // Auto-detect gotra/village/surname match
    if (community.gotraName || community.villageName || community.surname) {
      const userFamilies = await this.prisma.familyMember.findMany({
        where: { userId },
        include: { family: true },
      });
      for (const fm of userFamilies) {
        if (community.gotraName && fm.family.gotra === community.gotraName) { joinVia = 'auto_gotra'; break; }
        if (community.villageName && fm.family.originVillage === community.villageName) { joinVia = 'auto_gotra'; break; }
      }
    }

    await this.prisma.communityMember.create({
      data: { communityId, userId, role: 'member', joinedVia: joinVia },
    });
    await this.prisma.community.update({ where: { id: communityId }, data: { memberCount: { increment: 1 } } });

    return { success: true, action: 'joined', joinVia };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Feed
  // ═══════════════════════════════════════════════════════════════════

  async getFeed(options: { userId: string; cursor?: string; limit?: number; types?: string }) {
    const { userId } = options;
    const limit = Math.min(options.limit ?? 30, 100);

    const familyMemberships = await this.prisma.familyMember.findMany({ where: { userId }, select: { familyId: true } });
    const familyIds = familyMemberships.map((m) => m.familyId);

    const communityMemberships = await this.prisma.communityMember.findMany({ where: { userId }, select: { communityId: true } });
    const communityIds = communityMemberships.map((m) => m.communityId);

    // Get community posts
    const postsWhere: Record<string, unknown>[] = [];
    if (communityIds.length > 0) postsWhere.push({ communityId: { in: communityIds } });
    if (familyIds.length > 0) postsWhere.push({ familyId: { in: familyIds } });
    postsWhere.push({ visibility: 'public' });

    const posts = await this.prisma.communityPost.findMany({
      where: {
        OR: postsWhere,
        isHidden: false,
        ...(options.cursor ? { createdAt: { lt: new Date(options.cursor) } } : {}),
      },
      take: limit,
      orderBy: { createdAt: 'desc' },
      include: {
        author: { select: { id: true, name: true } },
        _count: { select: { reactions: true, comments: true } },
      },
    });

    const items = posts.map((post) => ({
      id: post.id,
      type: post.type,
      title: post.title ?? '',
      body: post.body,
      authorId: post.authorId,
      authorName: post.author.name ?? 'Unknown',
      familyId: post.familyId ?? undefined,
      communityId: post.communityId ?? undefined,
      mediaUrls: JSON.parse(post.mediaUrls || '[]'),
      createdAt: post.createdAt,
      reactionCount: post._count.reactions,
      commentCount: post._count.comments,
    }));

    // Get upcoming events
    const events = await this.prisma.communityEvent.findMany({
      where: {
        OR: [
          { familyId: { in: familyIds } },
          { communityId: { in: communityIds } },
          { visibility: 'public' },
        ],
        startDate: { gte: new Date() },
        isCancelled: false,
      },
      take: 10,
      orderBy: { startDate: 'asc' },
      include: { _count: { select: { rsvps: true } } },
    });

    for (const event of events) {
      items.push({
        id: `event-${event.id}`,
        type: 'event',
        title: event.title,
        body: event.description ?? '',
        authorId: event.creatorId,
        authorName: 'Event',
        familyId: event.familyId ?? undefined,
        communityId: event.communityId ?? undefined,
        mediaUrls: [],
        createdAt: event.createdAt,
        reactionCount: 0,
        commentCount: event._count.rsvps,
      });
    }

    // Sort by createdAt descending
    items.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

    const paginated = items.slice(0, limit);
    const nextCursor = paginated.length > 0 ? paginated[paginated.length - 1].createdAt.toISOString() : null;

    return {
      items: paginated,
      pagination: { nextCursor, hasMore: items.length > limit, count: paginated.length },
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Comments
  // ═══════════════════════════════════════════════════════════════════

  async getComments(postId: string, options: { parentId?: string; page?: number; limit?: number }) {
    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(options.limit ?? 50, 100);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = { postId, isHidden: false };
    if (options.parentId) {
      where.parentId = options.parentId;
    } else {
      where.parentId = null;
    }

    const [comments, total] = await Promise.all([
      this.prisma.comment.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: 'asc' },
        include: { author: { select: { id: true, name: true } } },
      }),
      this.prisma.comment.count({ where }),
    ]);

    return {
      comments,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    };
  }

  async createComment(postId: string, dto: CreateCommentDto) {
    const post = await this.prisma.communityPost.findUnique({ where: { id: postId } });
    if (!post) throw new NotFoundException('Post not found');
    if (post.isLocked) throw new ForbiddenException('This post is locked for new comments');

    if (dto.parentId) {
      const parentComment = await this.prisma.comment.findUnique({ where: { id: dto.parentId } });
      if (!parentComment || parentComment.postId !== postId) throw new NotFoundException('Parent comment not found');
      if (parentComment.parentId) throw new BadRequestException('Only one level of comment nesting is supported');
    }

    const comment = await this.prisma.comment.create({
      data: {
        postId,
        authorId: dto.authorId,
        parentId: dto.parentId ?? null,
        body: dto.body.trim(),
      },
      include: { author: { select: { id: true, name: true } } },
    });

    return { comment };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Reactions
  // ═══════════════════════════════════════════════════════════════════

  async getReactions(postId: string, userId?: string) {
    const reactions = await this.prisma.reaction.findMany({
      where: { postId },
      include: { user: { select: { id: true, name: true } } },
    });

    const aggregated: Record<string, { count: number; users: Array<{ id: string; name: string | null }> }> = {};
    for (const reaction of reactions) {
      if (!aggregated[reaction.emoji]) aggregated[reaction.emoji] = { count: 0, users: [] };
      aggregated[reaction.emoji].count++;
      aggregated[reaction.emoji].users.push({ id: reaction.user.id, name: reaction.user.name });
    }

    let userReactions: string[] = [];
    if (userId) {
      const myReactions = await this.prisma.reaction.findMany({
        where: { postId, userId },
        select: { emoji: true },
      });
      userReactions = myReactions.map((r) => r.emoji);
    }

    return { aggregated, userReactions, totalReactions: reactions.length };
  }

  async toggleReaction(postId: string, body: { userId: string; emoji: string }) {
    const post = await this.prisma.communityPost.findUnique({ where: { id: postId } });
    if (!post) throw new NotFoundException('Post not found');

    const existing = await this.prisma.reaction.findUnique({
      where: { postId_userId_emoji: { postId, userId: body.userId, emoji: body.emoji } },
    });

    if (existing) {
      await this.prisma.reaction.delete({ where: { id: existing.id } });
      return { action: 'removed', emoji: body.emoji };
    } else {
      await this.prisma.reaction.create({ data: { postId, userId: body.userId, emoji: body.emoji } });
      return { action: 'added', emoji: body.emoji };
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Event RSVP
  // ═══════════════════════════════════════════════════════════════════

  async rsvp(eventId: string, dto: RsvpDto) {
    const event = await this.prisma.communityEvent.findUnique({ where: { id: eventId } });
    if (!event) throw new NotFoundException('Event not found');
    if (event.isCancelled) throw new BadRequestException('Cannot RSVP to a cancelled event');

    const existingRSVP = await this.prisma.eventRSVP.findUnique({
      where: { eventId_userId: { eventId, userId: dto.userId } },
    });

    let rsvp;
    if (existingRSVP) {
      rsvp = await this.prisma.eventRSVP.update({
        where: { id: existingRSVP.id },
        data: {
          status: dto.status,
          plusOne: dto.plusOne ?? existingRSVP.plusOne,
          note: dto.note ?? existingRSVP.note,
          respondedAt: new Date(),
        },
      });
    } else {
      rsvp = await this.prisma.eventRSVP.create({
        data: {
          eventId,
          userId: dto.userId,
          status: dto.status,
          plusOne: dto.plusOne ?? false,
          note: dto.note ?? null,
          respondedAt: new Date(),
        },
      });
    }

    const rsvpSummary = await this.prisma.eventRSVP.groupBy({
      by: ['status'],
      where: { eventId },
      _count: { status: true },
    });

    const summary: Record<string, number> = { pending: 0, attending: 0, maybe: 0, declined: 0 };
    for (const row of rsvpSummary) {
      summary[row.status] = row._count.status;
    }

    return { rsvp, summary };
  }
}
