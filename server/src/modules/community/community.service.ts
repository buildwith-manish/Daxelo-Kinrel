import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import {
  CreateCommunityDto,
  UpdateCommunityDto,
  SearchCommunityDto,
  CreateCommunityPostDto,
  UpdateCommunityPostDto,
  CreateCommunityEventDto,
  UpdateCommunityEventDto,
} from './dto';

@Injectable()
export class CommunityService {
  constructor(
    private prisma: PrismaService,
    private gateway: KinrelGateway,
  ) {}

  // ── Community Management ──────────────────────────────────────────────

  /**
   * Search/browse communities with pagination and filtering.
   */
  async search(dto: SearchCommunityDto) {
    const { search, type, page = 1, limit = 20 } = dto;
    const skip = (page - 1) * limit;

    const where: any = {};

    if (type) {
      where.type = type;
    }

    // Only show public communities in browse, or all if user provides search
    if (!search) {
      where.isPrivate = false;
    }

    if (search) {
      where.OR = [
        { name: { contains: search, mode: 'insensitive' } },
        { gotraName: { contains: search, mode: 'insensitive' } },
        { villageName: { contains: search, mode: 'insensitive' } },
        { surname: { contains: search, mode: 'insensitive' } },
        { region: { contains: search, mode: 'insensitive' } },
      ];
    }

    const [communities, total] = await Promise.all([
      this.prisma.community.findMany({
        where,
        skip,
        take: limit,
        orderBy: { memberCount: 'desc' },
      }),
      this.prisma.community.count({ where }),
    ]);

    return {
      data: communities.map((c) => this.formatCommunity(c)),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * Create a new community.
   */
  async create(userId: string, dto: CreateCommunityDto) {
    const slug = this.generateSlug(dto.name);

    const existing = await this.prisma.community.findUnique({
      where: { slug },
    });

    if (existing) {
      throw new ConflictException(
        'A community with a similar name already exists',
      );
    }

    const community = await this.prisma.$transaction(async (tx) => {
      const created = await tx.community.create({
        data: {
          type: dto.type,
          name: dto.name.trim(),
          slug,
          description: dto.description?.trim() || null,
          isPrivate: dto.isPrivate || false,
          gotraName: dto.gotraName?.trim() || null,
          villageName: dto.villageName?.trim() || null,
          surname: dto.surname?.trim() || null,
          region: dto.region?.trim() || null,
          coverImageUrl: dto.coverImageUrl || null,
          iconUrl: dto.iconUrl || null,
          memberCount: 1,
        },
      });

      // Auto-join the creator as admin
      await tx.communityMember.create({
        data: {
          communityId: created.id,
          userId,
          role: 'admin',
        },
      });

      return created;
    });

    return this.formatCommunity(community);
  }

  /**
   * Get community detail.
   */
  async findOne(communityId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
      include: {
        rules: {
          orderBy: { sortOrder: 'asc' },
        },
      },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    return this.formatCommunity(community);
  }

  /**
   * Update a community (admin only).
   */
  async update(communityId: string, userId: string, dto: UpdateCommunityDto) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    // Verify admin
    await this.requireRole(communityId, userId, 'admin');

    // If name changes, validate slug uniqueness
    if (dto.name && dto.name.trim() !== community.name) {
      const newSlug = this.generateSlug(dto.name);
      const existing = await this.prisma.community.findUnique({
        where: { slug: newSlug },
      });
      if (existing && existing.id !== communityId) {
        throw new ConflictException(
          'A community with a similar name already exists',
        );
      }
    }

    const updated = await this.prisma.community.update({
      where: { id: communityId },
      data: {
        ...(dto.type !== undefined && { type: dto.type }),
        ...(dto.name !== undefined && {
          name: dto.name.trim(),
          slug: this.generateSlug(dto.name),
        }),
        ...(dto.description !== undefined && {
          description: dto.description?.trim() || null,
        }),
        ...(dto.isPrivate !== undefined && { isPrivate: dto.isPrivate }),
        ...(dto.gotraName !== undefined && {
          gotraName: dto.gotraName?.trim() || null,
        }),
        ...(dto.villageName !== undefined && {
          villageName: dto.villageName?.trim() || null,
        }),
        ...(dto.surname !== undefined && {
          surname: dto.surname?.trim() || null,
        }),
        ...(dto.region !== undefined && {
          region: dto.region?.trim() || null,
        }),
        ...(dto.coverImageUrl !== undefined && {
          coverImageUrl: dto.coverImageUrl || null,
        }),
        ...(dto.iconUrl !== undefined && {
          iconUrl: dto.iconUrl || null,
        }),
      },
    });

    return this.formatCommunity(updated);
  }

  /**
   * Delete a community (admin only). Cascades remove members, posts, events.
   */
  async delete(communityId: string, userId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    await this.requireRole(communityId, userId, 'admin');

    await this.prisma.community.delete({
      where: { id: communityId },
    });

    return { deleted: true, communityId };
  }

  /**
   * Join a community. For private communities, creates a pending request
   * (using joinedVia='pending' convention) and does NOT increment memberCount.
   */
  async join(communityId: string, userId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    // Check if already a member (including pending)
    const existing = await this.prisma.communityMember.findFirst({
      where: { communityId, userId },
    });

    if (existing) {
      if (existing.joinedVia === 'pending') {
        throw new BadRequestException(
          'You already have a pending join request for this community',
        );
      }
      throw new BadRequestException('You are already a member of this community');
    }

    // For private communities, create a pending request
    if (community.isPrivate) {
      await this.prisma.communityMember.create({
        data: {
          communityId,
          userId,
          role: 'member',
          joinedVia: 'pending',
        },
      });

      // Do NOT increment memberCount for pending joins
      return {
        joined: false,
        pending: true,
        communityId,
        message: 'Join request submitted — waiting for admin approval',
      };
    }

    // Public community — auto-join
    await this.prisma.$transaction(async (tx) => {
      await tx.communityMember.create({
        data: {
          communityId,
          userId,
          role: 'member',
        },
      });

      await tx.community.update({
        where: { id: communityId },
        data: { memberCount: { increment: 1 } },
      });
    });

    this.gateway.emitToUser(userId, 'community:joined', {
      communityId,
      communityName: community.name,
    });

    return { joined: true, communityId, role: 'member' };
  }

  /**
   * Leave a community. Cannot leave if last admin.
   */
  async leave(communityId: string, userId: string) {
    const member = await this.prisma.communityMember.findFirst({
      where: { communityId, userId, joinedVia: { not: 'pending' } },
    });

    if (!member) {
      throw new BadRequestException('You are not a member of this community');
    }

    // If admin, check if they're the last admin
    if (member.role === 'admin') {
      const adminCount = await this.prisma.communityMember.count({
        where: {
          communityId,
          role: 'admin',
          joinedVia: { not: 'pending' },
        },
      });

      if (adminCount <= 1) {
        throw new BadRequestException(
          'You are the last admin — transfer ownership before leaving',
        );
      }
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.communityMember.delete({
        where: { id: member.id },
      });

      await tx.community.update({
        where: { id: communityId },
        data: { memberCount: { decrement: 1 } },
      });
    });

    return { left: true, communityId };
  }

  // ── Members ───────────────────────────────────────────────────────────

  /**
   * List members of a community (paginated, with user profiles).
   */
  async listMembers(
    communityId: string,
    params: { page?: number; limit?: number },
  ) {
    const { page = 1, limit = 20 } = params;
    const skip = (page - 1) * limit;

    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    const where: any = {
      communityId,
      joinedVia: { not: 'pending' },
    };

    const [members, total] = await Promise.all([
      this.prisma.communityMember.findMany({
        where,
        skip,
        take: limit,
        orderBy: [{ role: 'asc' }, { joinedAt: 'asc' }],
        include: {
          user: {
            select: {
              id: true,
              name: true,
              avatarUrl: true,
            },
          },
        },
      }),
      this.prisma.communityMember.count({ where }),
    ]);

    return {
      data: members.map((m: any) => ({
        id: m.id,
        userId: m.userId,
        role: m.role,
        joinedAt: m.joinedAt,
        joinedVia: m.joinedVia,
        user: m.user,
      })),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * Update a member's role (admin only). Cannot demote the last admin.
   */
  async updateMemberRole(
    communityId: string,
    requesterId: string,
    targetUserId: string,
    newRole: string,
  ) {
    await this.requireRole(communityId, requesterId, 'admin');

    const target = await this.prisma.communityMember.findFirst({
      where: { communityId, userId: targetUserId, joinedVia: { not: 'pending' } },
    });

    if (!target) {
      throw new NotFoundException('Member not found in this community');
    }

    // Cannot demote the last admin
    if (target.role === 'admin' && newRole !== 'admin') {
      const adminCount = await this.prisma.communityMember.count({
        where: {
          communityId,
          role: 'admin',
          joinedVia: { not: 'pending' },
        },
      });

      if (adminCount <= 1) {
        throw new BadRequestException(
          'Cannot demote the last admin — transfer ownership first',
        );
      }
    }

    const updated = await this.prisma.communityMember.update({
      where: { id: target.id },
      data: { role: newRole },
    });

    this.gateway.emitToUser(targetUserId, 'community:role-updated', {
      communityId,
      newRole,
    });

    return {
      id: updated.id,
      userId: updated.userId,
      role: updated.role,
    };
  }

  /**
   * Remove/ban a member from a community. Admin/mod can remove. Admin cannot be removed by mod.
   */
  async removeMember(
    communityId: string,
    requesterId: string,
    targetUserId: string,
  ) {
    const requester = await this.getMemberOrThrow(communityId, requesterId);

    if (!['admin', 'moderator'].includes(requester.role)) {
      throw new ForbiddenException('Only admins and moderators can remove members');
    }

    const target = await this.prisma.communityMember.findFirst({
      where: { communityId, userId: targetUserId, joinedVia: { not: 'pending' } },
    });

    if (!target) {
      throw new NotFoundException('Member not found in this community');
    }

    // Mod cannot remove admin
    if (requester.role === 'moderator' && target.role === 'admin') {
      throw new ForbiddenException('Moderators cannot remove admins');
    }

    // Cannot remove yourself (use leave instead)
    if (targetUserId === requesterId) {
      throw new BadRequestException('Use the leave endpoint to leave a community');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.communityMember.delete({
        where: { id: target.id },
      });

      await tx.community.update({
        where: { id: communityId },
        data: { memberCount: { decrement: 1 } },
      });
    });

    this.gateway.emitToUser(targetUserId, 'community:removed', {
      communityId,
    });

    return { removed: true, userId: targetUserId };
  }

  /**
   * Get pending join requests for a private community.
   */
  async getPendingRequests(communityId: string, userId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    await this.requireRole(communityId, userId, 'admin');

    const pending = await this.prisma.communityMember.findMany({
      where: {
        communityId,
        joinedVia: 'pending',
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
          },
        },
      },
      orderBy: { joinedAt: 'asc' },
    });

    return {
      data: pending.map((m: any) => ({
        id: m.id,
        userId: m.userId,
        requestedAt: m.joinedAt,
        user: m.user,
      })),
    };
  }

  /**
   * Approve a join request (admin only). Increments memberCount and removes pending status.
   */
  async approveJoinRequest(
    communityId: string,
    requesterId: string,
    targetUserId: string,
  ) {
    await this.requireRole(communityId, requesterId, 'admin');

    const pending = await this.prisma.communityMember.findFirst({
      where: {
        communityId,
        userId: targetUserId,
        joinedVia: 'pending',
      },
    });

    if (!pending) {
      throw new NotFoundException('No pending join request found for this user');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.communityMember.update({
        where: { id: pending.id },
        data: { joinedVia: 'approved' },
      });

      await tx.community.update({
        where: { id: communityId },
        data: { memberCount: { increment: 1 } },
      });
    });

    this.gateway.emitToUser(targetUserId, 'community:approved', {
      communityId,
    });

    return { approved: true, userId: targetUserId, communityId };
  }

  /**
   * Reject a join request (admin only). Deletes the member record.
   */
  async rejectJoinRequest(
    communityId: string,
    requesterId: string,
    targetUserId: string,
  ) {
    await this.requireRole(communityId, requesterId, 'admin');

    const pending = await this.prisma.communityMember.findFirst({
      where: {
        communityId,
        userId: targetUserId,
        joinedVia: 'pending',
      },
    });

    if (!pending) {
      throw new NotFoundException('No pending join request found for this user');
    }

    await this.prisma.communityMember.delete({
      where: { id: pending.id },
    });

    this.gateway.emitToUser(targetUserId, 'community:rejected', {
      communityId,
    });

    return { rejected: true, userId: targetUserId, communityId };
  }

  // ── Posts ─────────────────────────────────────────────────────────────

  /**
   * Create a post in a community (members only). Increments postCount.
   */
  async createPost(
    communityId: string,
    userId: string,
    dto: CreateCommunityPostDto,
  ) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    // Must be a member
    const member = await this.getMemberOrThrow(communityId, userId);
    if (member.joinedVia === 'pending') {
      throw new ForbiddenException('Your join request is still pending');
    }

    const post = await this.prisma.$transaction(async (tx) => {
      const created = await tx.communityPost.create({
        data: {
          communityId,
          authorId: userId,
          type: dto.type,
          title: dto.title?.trim() || null,
          body: dto.body,
          mediaUrls: JSON.stringify(dto.mediaUrls || []),
          visibility: dto.visibility === 'public' ? 'public' : 'members',
        },
      });

      await tx.community.update({
        where: { id: communityId },
        data: { postCount: { increment: 1 } },
      });

      return created;
    });

    return this.formatPost(post);
  }

  /**
   * List posts in a community (paginated). Members see all; non-members see public only.
   */
  async listPosts(
    communityId: string,
    userId: string,
    params: { page?: number; limit?: number },
  ) {
    const { page = 1, limit = 20 } = params;
    const skip = (page - 1) * limit;

    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    // Check if user is a member
    const membership = await this.prisma.communityMember.findFirst({
      where: {
        communityId,
        userId,
        joinedVia: { not: 'pending' },
      },
    });

    const where: any = {
      communityId,
      isHidden: false,
    };

    // Non-members can only see public posts
    if (!membership) {
      where.visibility = 'public';
    }

    const [posts, total] = await Promise.all([
      this.prisma.communityPost.findMany({
        where,
        skip,
        take: limit,
        orderBy: [{ isPinned: 'desc' }, { createdAt: 'desc' }],
        include: {
          author: {
            select: {
              id: true,
              name: true,
              avatarUrl: true,
            },
          },
        },
      }),
      this.prisma.communityPost.count({ where }),
    ]);

    return {
      data: posts.map((p: any) => ({
        ...this.formatPost(p),
        author: p.author,
      })),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * Get a single post.
   */
  async getPost(communityId: string, userId: string, postId: string) {
    const post = await this.prisma.communityPost.findFirst({
      where: { id: postId, communityId },
      include: {
        author: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
          },
        },
      },
    });

    if (!post) {
      throw new NotFoundException('Post not found');
    }

    // Non-members can only see public posts
    if (post.visibility !== 'public') {
      const membership = await this.prisma.communityMember.findFirst({
        where: {
          communityId,
          userId,
          joinedVia: { not: 'pending' },
        },
      });

      if (!membership) {
        throw new ForbiddenException('You must be a member to view this post');
      }
    }

    return {
      ...this.formatPost(post),
      author: (post as any).author,
    };
  }

  /**
   * Update a post (author or admin/mod).
   */
  async updatePost(
    communityId: string,
    userId: string,
    postId: string,
    dto: UpdateCommunityPostDto,
  ) {
    const post = await this.prisma.communityPost.findFirst({
      where: { id: postId, communityId },
    });

    if (!post) {
      throw new NotFoundException('Post not found');
    }

    // Author can update their own post
    if (post.authorId !== userId) {
      // Otherwise must be admin or moderator
      await this.requireAnyRole(communityId, userId, ['admin', 'moderator']);
    }

    const updated = await this.prisma.communityPost.update({
      where: { id: postId },
      data: {
        ...(dto.title !== undefined && { title: dto.title?.trim() || null }),
        ...(dto.body !== undefined && { body: dto.body }),
        ...(dto.mediaUrls !== undefined && {
          mediaUrls: JSON.stringify(dto.mediaUrls),
        }),
        ...(dto.isPinned !== undefined && { isPinned: dto.isPinned }),
        ...(dto.isLocked !== undefined && { isLocked: dto.isLocked }),
      },
    });

    return this.formatPost(updated);
  }

  /**
   * Delete a post (author or admin/mod). Decrements postCount.
   */
  async deletePost(communityId: string, userId: string, postId: string) {
    const post = await this.prisma.communityPost.findFirst({
      where: { id: postId, communityId },
    });

    if (!post) {
      throw new NotFoundException('Post not found');
    }

    // Author can delete their own post
    if (post.authorId !== userId) {
      // Otherwise must be admin or moderator
      await this.requireAnyRole(communityId, userId, ['admin', 'moderator']);
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.communityPost.delete({
        where: { id: postId },
      });

      await tx.community.update({
        where: { id: communityId },
        data: { postCount: { decrement: 1 } },
      });
    });

    return { deleted: true, postId };
  }

  // ── Events ────────────────────────────────────────────────────────────

  /**
   * Create an event (admin/mod only).
   */
  async createEvent(
    communityId: string,
    userId: string,
    dto: CreateCommunityEventDto,
  ) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    await this.requireAnyRole(communityId, userId, ['admin', 'moderator']);

    const event = await this.prisma.communityEvent.create({
      data: {
        communityId,
        creatorId: userId,
        title: dto.title.trim(),
        description: dto.description?.trim() || null,
        startDate: new Date(dto.startAt),
        endDate: dto.endAt ? new Date(dto.endAt) : null,
        location: dto.location?.trim() || null,
        meetingUrl: dto.meetingLink?.trim() || null,
        coverImageUrl: dto.coverImageUrl?.trim() || null,
        visibility: 'community',
        eventType: 'custom',
      },
    });

    return this.formatEvent(event);
  }

  /**
   * List events in a community with optional filter (upcoming/past).
   */
  async listEvents(communityId: string, filter?: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    const where: any = {
      communityId,
      isCancelled: false,
    };

    const now = new Date();

    if (filter === 'upcoming') {
      where.startDate = { gte: now };
    } else if (filter === 'past') {
      where.startDate = { lt: now };
    }

    const events = await this.prisma.communityEvent.findMany({
      where,
      orderBy: { startDate: filter === 'past' ? 'desc' : 'asc' },
      take: 50,
    });

    return {
      data: events.map((e) => this.formatEvent(e)),
    };
  }

  /**
   * Get event detail.
   */
  async getEvent(communityId: string, eventId: string) {
    const event = await this.prisma.communityEvent.findFirst({
      where: { id: eventId, communityId },
      include: {
        rsvps: {
          include: {
            user: {
              select: {
                id: true,
                name: true,
                avatarUrl: true,
              },
            },
          },
        },
      },
    });

    if (!event) {
      throw new NotFoundException('Event not found');
    }

    const formattedRsvps = (event as any).rsvps?.map((r: any) => ({
      id: r.id,
      userId: r.userId,
      status: r.status,
      user: r.user,
      respondedAt: r.respondedAt,
    })) || [];

    return {
      ...this.formatEvent(event),
      rsvps: formattedRsvps,
    };
  }

  /**
   * Update an event (creator or admin).
   */
  async updateEvent(
    communityId: string,
    userId: string,
    eventId: string,
    dto: UpdateCommunityEventDto,
  ) {
    const event = await this.prisma.communityEvent.findFirst({
      where: { id: eventId, communityId },
    });

    if (!event) {
      throw new NotFoundException('Event not found');
    }

    // Creator can update their own event
    if (event.creatorId !== userId) {
      // Otherwise must be admin
      await this.requireRole(communityId, userId, 'admin');
    }

    const updated = await this.prisma.communityEvent.update({
      where: { id: eventId },
      data: {
        ...(dto.title !== undefined && { title: dto.title.trim() }),
        ...(dto.description !== undefined && {
          description: dto.description?.trim() || null,
        }),
        ...(dto.startAt !== undefined && { startDate: new Date(dto.startAt) }),
        ...(dto.endAt !== undefined && {
          endDate: dto.endAt ? new Date(dto.endAt) : null,
        }),
        ...(dto.location !== undefined && {
          location: dto.location?.trim() || null,
        }),
        ...(dto.meetingLink !== undefined && {
          meetingUrl: dto.meetingLink?.trim() || null,
        }),
        ...(dto.coverImageUrl !== undefined && {
          coverImageUrl: dto.coverImageUrl?.trim() || null,
        }),
      },
    });

    return this.formatEvent(updated);
  }

  /**
   * Delete an event (creator or admin).
   */
  async deleteEvent(communityId: string, userId: string, eventId: string) {
    const event = await this.prisma.communityEvent.findFirst({
      where: { id: eventId, communityId },
    });

    if (!event) {
      throw new NotFoundException('Event not found');
    }

    // Creator can delete their own event
    if (event.creatorId !== userId) {
      // Otherwise must be admin
      await this.requireRole(communityId, userId, 'admin');
    }

    await this.prisma.communityEvent.delete({
      where: { id: eventId },
    });

    return { deleted: true, eventId };
  }

  /**
   * RSVP to an event (members only). Upserts RSVP status.
   */
  async rsvp(
    communityId: string,
    userId: string,
    eventId: string,
    status: string,
  ) {
    const event = await this.prisma.communityEvent.findFirst({
      where: { id: eventId, communityId },
    });

    if (!event) {
      throw new NotFoundException('Event not found');
    }

    // Must be a member
    const member = await this.getMemberOrThrow(communityId, userId);
    if (member.joinedVia === 'pending') {
      throw new ForbiddenException('Your join request is still pending');
    }

    // Map DTO status to schema status
    const statusMap: Record<string, string> = {
      going: 'attending',
      maybe: 'maybe',
      not_going: 'declined',
    };

    const schemaStatus = statusMap[status] || 'pending';

    // Upsert RSVP
    const rsvp = await this.prisma.eventRSVP.upsert({
      where: {
        eventId_userId: { eventId, userId },
      },
      create: {
        eventId,
        userId,
        status: schemaStatus,
        respondedAt: new Date(),
      },
      update: {
        status: schemaStatus,
        respondedAt: new Date(),
      },
    });

    return {
      id: rsvp.id,
      eventId: rsvp.eventId,
      userId: rsvp.userId,
      status: rsvp.status,
      respondedAt: rsvp.respondedAt,
    };
  }

  /**
   * List RSVPs for an event.
   */
  async listRsvps(communityId: string, eventId: string) {
    const event = await this.prisma.communityEvent.findFirst({
      where: { id: eventId, communityId },
    });

    if (!event) {
      throw new NotFoundException('Event not found');
    }

    const rsvps = await this.prisma.eventRSVP.findMany({
      where: { eventId },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
          },
        },
      },
      orderBy: { respondedAt: 'desc' },
    });

    return {
      data: rsvps.map((r: any) => ({
        id: r.id,
        userId: r.userId,
        status: r.status,
        user: r.user,
        respondedAt: r.respondedAt,
      })),
    };
  }

  /**
   * Set a reminder for an event (members only).
   */
  async setReminder(communityId: string, userId: string, eventId: string) {
    const event = await this.prisma.communityEvent.findFirst({
      where: { id: eventId, communityId },
    });

    if (!event) {
      throw new NotFoundException('Event not found');
    }

    // Must be a member
    const member = await this.getMemberOrThrow(communityId, userId);
    if (member.joinedVia === 'pending') {
      throw new ForbiddenException('Your join request is still pending');
    }

    // Remind 1 hour before event
    const remindAt = new Date(event.startDate.getTime() - 60 * 60 * 1000);

    const reminder = await this.prisma.eventReminder.create({
      data: {
        eventId,
        userId,
        remindAt,
      },
    });

    return {
      id: reminder.id,
      eventId,
      userId,
      remindAt: reminder.remindAt,
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /**
   * Require that the user has a specific role in the community.
   */
  private async requireRole(
    communityId: string,
    userId: string,
    requiredRole: string,
  ) {
    const member = await this.prisma.communityMember.findFirst({
      where: {
        communityId,
        userId,
        joinedVia: { not: 'pending' },
      },
    });

    if (!member) {
      throw new ForbiddenException('You are not a member of this community');
    }

    if (member.role !== requiredRole) {
      throw new ForbiddenException(
        `Only ${requiredRole}s can perform this action`,
      );
    }

    return member;
  }

  /**
   * Require that the user has any of the specified roles.
   */
  private async requireAnyRole(
    communityId: string,
    userId: string,
    roles: string[],
  ) {
    const member = await this.prisma.communityMember.findFirst({
      where: {
        communityId,
        userId,
        joinedVia: { not: 'pending' },
      },
    });

    if (!member) {
      throw new ForbiddenException('You are not a member of this community');
    }

    if (!roles.includes(member.role)) {
      throw new ForbiddenException(
        `Only ${roles.join(' or ')}s can perform this action`,
      );
    }

    return member;
  }

  /**
   * Get a community member or throw.
   */
  private async getMemberOrThrow(communityId: string, userId: string) {
    const member = await this.prisma.communityMember.findFirst({
      where: { communityId, userId },
    });

    if (!member) {
      throw new ForbiddenException('You are not a member of this community');
    }

    return member;
  }

  /**
   * Generate a URL-safe slug from a community name.
   */
  private generateSlug(name: string): string {
    return name
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, '')
      .replace(/[\s_]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .substring(0, 80);
  }

  private formatCommunity(community: any) {
    return {
      id: community.id,
      type: community.type,
      name: community.name,
      slug: community.slug,
      description: community.description,
      coverImageUrl: community.coverImageUrl,
      iconUrl: community.iconUrl,
      isVerified: community.isVerified,
      isPrivate: community.isPrivate,
      memberCount: community.memberCount,
      postCount: community.postCount,
      gotraName: community.gotraName,
      villageName: community.villageName,
      surname: community.surname,
      region: community.region,
      rules: community.rules || undefined,
      createdAt: community.createdAt,
      updatedAt: community.updatedAt,
    };
  }

  private formatPost(post: any) {
    return {
      id: post.id,
      communityId: post.communityId,
      authorId: post.authorId,
      type: post.type,
      title: post.title,
      body: post.body,
      mediaUrls: typeof post.mediaUrls === 'string' ? JSON.parse(post.mediaUrls) : post.mediaUrls,
      visibility: post.visibility,
      isPinned: post.isPinned,
      isLocked: post.isLocked,
      createdAt: post.createdAt,
      updatedAt: post.updatedAt,
    };
  }

  private formatEvent(event: any) {
    return {
      id: event.id,
      communityId: event.communityId,
      creatorId: event.creatorId,
      title: event.title,
      description: event.description,
      eventType: event.eventType,
      startDate: event.startDate,
      endDate: event.endDate,
      location: event.location,
      meetingUrl: event.meetingUrl,
      coverImageUrl: event.coverImageUrl,
      visibility: event.visibility,
      isCancelled: event.isCancelled,
      createdAt: event.createdAt,
      updatedAt: event.updatedAt,
    };
  }
}
