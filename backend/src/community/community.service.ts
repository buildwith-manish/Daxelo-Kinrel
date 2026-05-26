import { Injectable, NotFoundException, BadRequestException, ForbiddenException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ListCommunitiesDto } from './dto/list-communities.dto';
import { CreateCommunityDto } from './dto/create-community.dto';
import { UpdateCommunityDto } from './dto/update-community.dto';
import { JoinCommunityDto } from './dto/join-community.dto';
import { CreateEventDto } from './dto/create-event.dto';
import { RsvpDto } from './dto/rsvp.dto';
import { CreateCommentDto } from './dto/create-comment.dto';
import { ToggleReactionDto } from './dto/toggle-reaction.dto';

const MAX_COMMENT_LENGTH = 2000;
const DEFAULT_REMINDER_OFFSETS = [1440, 60, 15]; // 1 day, 1 hour, 15 min

@Injectable()
export class CommunityService {
  constructor(private prisma: PrismaService) {}

  // ── Communities ─────────────────────────────────────────────────────

  async listCommunities(dto: ListCommunitiesDto) {
    const { type, search, page = 1, limit = 20 } = dto;

    const where: Record<string, unknown> = {};
    if (type) where.type = type;
    if (search) {
      where.OR = [
        { name: { contains: search } },
        { description: { contains: search } },
        { gotraName: { contains: search } },
        { villageName: { contains: search } },
        { surname: { contains: search } },
      ];
    }

    const [communities, total] = await Promise.all([
      this.prisma.community.findMany({
        where,
        skip: (page - 1) * limit,
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

  async createCommunity(dto: CreateCommunityDto, userId: string) {
    // Verify user exists and has moderator+ role
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');
    if (user.role !== 'admin' && user.role !== 'agent' && user.role !== 'moderator') {
      throw new ForbiddenException('Insufficient permissions. Moderator or admin role required.');
    }

    // Generate slug from name
    const slug = dto.slug || dto.name
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .trim();

    // Check slug uniqueness
    const existing = await this.prisma.community.findUnique({ where: { slug } });
    if (existing) throw new ConflictException('A community with this name already exists');

    const community = await this.prisma.community.create({
      data: {
        type: dto.type,
        name: dto.name,
        slug,
        description: dto.description || null,
        isPrivate: dto.isPrivate ?? false,
        gotraName: dto.gotraName || null,
        villageName: dto.villageName || null,
        surname: dto.surname || null,
        region: dto.region || null,
        memberCount: 1,
      },
    });

    // Auto-add creator as admin
    await this.prisma.communityMember.create({
      data: {
        communityId: community.id,
        userId,
        role: 'admin',
        joinedVia: 'creation',
      },
    });

    return { community };
  }

  async getCommunity(communityId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
      include: {
        members: {
          take: 10,
          orderBy: { joinedAt: 'desc' },
          include: { user: { select: { id: true, name: true, email: true } } },
        },
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

  async updateCommunity(communityId: string, dto: UpdateCommunityDto, userId: string) {
    const membership = await this.prisma.communityMember.findFirst({
      where: { communityId, userId, role: 'admin' },
    });
    if (!membership) throw new ForbiddenException('Only community admins can update the community');

    const updateData: Record<string, unknown> = {};
    if (dto.name !== undefined) updateData.name = dto.name;
    if (dto.description !== undefined) updateData.description = dto.description;
    if (dto.coverImageUrl !== undefined) updateData.coverImageUrl = dto.coverImageUrl;
    if (dto.iconUrl !== undefined) updateData.iconUrl = dto.iconUrl;
    if (dto.isPrivate !== undefined) updateData.isPrivate = dto.isPrivate;
    if (dto.region !== undefined) updateData.region = dto.region;

    if (dto.isVerified !== undefined) {
      const user = await this.prisma.user.findUnique({ where: { id: userId } });
      if (user?.role === 'admin') updateData.isVerified = dto.isVerified;
    }

    const community = await this.prisma.community.update({
      where: { id: communityId },
      data: updateData,
    });

    return { community };
  }

  async deleteCommunity(communityId: string, userId: string) {
    const membership = await this.prisma.communityMember.findFirst({
      where: { communityId, userId, role: 'admin' },
    });
    if (!membership) throw new ForbiddenException('Only community admins can delete the community');

    await this.prisma.community.delete({ where: { id: communityId } });
    return { success: true };
  }

  // ── Join / Leave ────────────────────────────────────────────────────

  async joinOrLeave(communityId: string, dto: JoinCommunityDto, userId: string) {
    const community = await this.prisma.community.findUnique({ where: { id: communityId } });
    if (!community) throw new NotFoundException('Community not found');

    if (dto.action === 'leave') {
      const membership = await this.prisma.communityMember.findUnique({
        where: { communityId_userId: { communityId, userId } },
      });
      if (!membership) throw new BadRequestException('Not a member of this community');

      if (membership.role === 'admin') {
        const adminCount = await this.prisma.communityMember.count({
          where: { communityId, role: 'admin' },
        });
        if (adminCount <= 1) {
          throw new BadRequestException('Cannot leave as the last admin. Transfer admin role first.');
        }
      }

      await this.prisma.communityMember.delete({
        where: { communityId_userId: { communityId, userId } },
      });
      await this.prisma.community.update({
        where: { id: communityId },
        data: { memberCount: { decrement: 1 } },
      });

      return { success: true, action: 'left' };
    }

    // Join
    const existing = await this.prisma.communityMember.findUnique({
      where: { communityId_userId: { communityId, userId } },
    });

    if (existing) {
      if (existing.role === 'banned') throw new ForbiddenException('You have been banned from this community');
      throw new BadRequestException('Already a member of this community');
    }

    let joinVia = 'search';

    // Auto-detect via gotra/village/surname
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
    await this.prisma.community.update({
      where: { id: communityId },
      data: { memberCount: { increment: 1 } },
    });

    // Record contribution
    const userFamily = await this.prisma.familyMember.findFirst({ where: { userId } });
    if (userFamily) {
      await this.recordContribution(userId, userFamily.familyId, 'communityJoin');
    }

    return { success: true, action: 'joined', joinedVia: joinVia };
  }

  // ── Feed ────────────────────────────────────────────────────────────

  async getFeed(userId: string, cursor?: string, limit = 30) {
    const familyMemberships = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const familyIds = familyMemberships.map((m) => m.familyId);

    const communityMemberships = await this.prisma.communityMember.findMany({
      where: { userId },
      select: { communityId: true },
    });
    const communityIds = communityMemberships.map((m) => m.communityId);

    // Get posts from family and community
    const postsWhere: Record<string, unknown>[] = [];
    if (communityIds.length > 0) postsWhere.push({ communityId: { in: communityIds } });
    if (familyIds.length > 0) postsWhere.push({ familyId: { in: familyIds } });
    postsWhere.push({ visibility: 'public' });

    const posts = await this.prisma.communityPost.findMany({
      where: {
        OR: postsWhere,
        isHidden: false,
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      take: limit * 2,
      orderBy: { createdAt: 'desc' },
      include: {
        author: { select: { id: true, name: true } },
        _count: { select: { reactions: true, comments: true } },
      },
    });

    const feedItems = posts.map((post) => ({
      id: post.id,
      type: post.type,
      title: post.title || '',
      body: post.body,
      authorId: post.authorId,
      authorName: post.author.name || 'Unknown',
      familyId: post.familyId,
      communityId: post.communityId,
      mediaUrls: JSON.parse(post.mediaUrls || '[]'),
      createdAt: post.createdAt,
      reactionCount: post._count.reactions,
      commentCount: post._count.comments,
    }));

    // Paginate
    const paginated = feedItems.slice(0, limit);
    const nextCursor = paginated.length > 0
      ? paginated[paginated.length - 1].createdAt.toISOString()
      : null;

    return {
      items: paginated,
      pagination: {
        nextCursor,
        hasMore: feedItems.length > limit,
        count: paginated.length,
      },
    };
  }

  // ── Events ──────────────────────────────────────────────────────────

  async listEvents(familyId: string, upcoming?: boolean, eventType?: string, page = 1, limit = 20) {
    const where: Record<string, unknown> = { familyId, isCancelled: false };
    if (upcoming) where.startDate = { gte: new Date() };
    if (eventType) where.eventType = eventType;

    const [events, total] = await Promise.all([
      this.prisma.communityEvent.findMany({
        where,
        skip: (page - 1) * limit,
        take: limit,
        orderBy: { startDate: 'asc' },
        include: { _count: { select: { rsvps: true, reminders: true } } },
      }),
      this.prisma.communityEvent.count({ where }),
    ]);

    return {
      events,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    };
  }

  async createEvent(familyId: string, dto: CreateEventDto, userId: string) {
    // Verify family membership
    const familyMember = await this.prisma.familyMember.findFirst({
      where: { familyId, userId },
    });
    if (!familyMember) throw new ForbiddenException('You must be a family member to create events');

    const resolvedEventType = dto.eventType || 'custom';
    const resolvedVisibility = dto.visibility || 'family';

    const event = await this.prisma.communityEvent.create({
      data: {
        familyId,
        communityId: dto.communityId || null,
        creatorId: userId,
        title: dto.title,
        description: dto.description || null,
        eventType: resolvedEventType,
        startDate: new Date(dto.startDate),
        endDate: dto.endDate ? new Date(dto.endDate) : null,
        isAllDay: dto.isAllDay ?? false,
        isRecurring: dto.isRecurring ?? false,
        recurrenceRule: dto.recurrenceRule || null,
        location: dto.location || null,
        locationUrl: dto.locationUrl || null,
        meetingUrl: dto.meetingUrl || null,
        visibility: resolvedVisibility,
        coverImageUrl: dto.coverImageUrl || null,
        metadata: dto.metadata || null,
      },
    });

    // Auto-RSVP creator as attending
    await this.prisma.eventRSVP.create({
      data: { eventId: event.id, userId, status: 'attending' },
    });

    // Auto-create reminders
    const reminderOffsets = DEFAULT_REMINDER_OFFSETS;
    for (const offsetMinutes of reminderOffsets) {
      const remindAt = new Date(new Date(dto.startDate).getTime() - offsetMinutes * 60 * 1000);
      if (remindAt > new Date()) {
        await this.prisma.eventReminder.create({
          data: { eventId: event.id, userId, remindAt },
        });
      }
    }

    // Create reminders + auto-RSVP for family members
    const familyMembers = await this.prisma.familyMember.findMany({
      where: { familyId, userId: { not: userId } },
      select: { userId: true },
    });

    for (const member of familyMembers) {
      await this.prisma.eventRSVP.create({
        data: { eventId: event.id, userId: member.userId, status: 'pending' },
      });

      for (const offsetMinutes of reminderOffsets) {
        const remindAt = new Date(new Date(dto.startDate).getTime() - offsetMinutes * 60 * 1000);
        if (remindAt > new Date()) {
          await this.prisma.eventReminder.create({
            data: { eventId: event.id, userId: member.userId, remindAt },
          });
        }
      }
    }

    // Create a feed post for the event
    await this.prisma.communityPost.create({
      data: {
        familyId,
        communityId: dto.communityId || null,
        authorId: userId,
        type: 'event',
        title: `${dto.title}`,
        body: dto.description || `New event: ${dto.title}`,
        visibility: resolvedVisibility === 'public' ? 'public' : 'family_only',
        metadata: JSON.stringify({ eventId: event.id, eventType: resolvedEventType }),
      },
    });

    // Record contribution
    await this.recordContribution(userId, familyId, 'eventCreated');

    return { event };
  }

  // ── RSVP ────────────────────────────────────────────────────────────

  async rsvp(eventId: string, dto: RsvpDto, userId: string) {
    const event = await this.prisma.communityEvent.findUnique({ where: { id: eventId } });
    if (!event) throw new NotFoundException('Event not found');
    if (event.isCancelled) throw new BadRequestException('Cannot RSVP to a cancelled event');

    const statusMap: Record<string, string> = {
      going: 'attending',
      maybe: 'maybe',
      not_going: 'declined',
    };
    const rsvpStatus = statusMap[dto.status] || 'pending';

    const existingRSVP = await this.prisma.eventRSVP.findUnique({
      where: { eventId_userId: { eventId, userId } },
    });

    let rsvp;
    if (existingRSVP) {
      rsvp = await this.prisma.eventRSVP.update({
        where: { id: existingRSVP.id },
        data: {
          status: rsvpStatus,
          plusOne: dto.plusOne ?? existingRSVP.plusOne,
          note: dto.note ?? existingRSVP.note,
          respondedAt: new Date(),
        },
      });
    } else {
      rsvp = await this.prisma.eventRSVP.create({
        data: {
          eventId,
          userId,
          status: rsvpStatus,
          plusOne: dto.plusOne ?? false,
          note: dto.note || null,
          respondedAt: new Date(),
        },
      });
    }

    // Get updated RSVP summary
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

  // ── Family Stats ────────────────────────────────────────────────────

  async getFamilyStats(familyId: string) {
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      select: { id: true, isDeceased: true, dateOfBirth: true, relationship: true },
    });

    const relationships = await this.prisma.relationship.findMany({
      where: { familyId },
      select: { type: true },
    });

    const totalCount = persons.length;
    const livingCount = persons.filter((p) => !p.isDeceased).length;
    const deceasedCount = persons.filter((p) => p.isDeceased).length;

    // Gender distribution (simplified)
    const genderDistribution: Record<string, number> = { male: 0, female: 0, unknown: 0 };
    const maleRels = ['father', 'son', 'brother', 'husband', 'grandfather', 'uncle', 'nephew', 'cousin'];
    const femaleRels = ['mother', 'daughter', 'sister', 'wife', 'grandmother', 'aunt', 'niece'];

    for (const person of persons) {
      if (person.relationship) {
        const rel = person.relationship.toLowerCase();
        if (maleRels.some((r) => rel.includes(r))) genderDistribution.male++;
        else if (femaleRels.some((r) => rel.includes(r))) genderDistribution.female++;
        else genderDistribution.unknown++;
      } else {
        genderDistribution.unknown++;
      }
    }

    // Average age
    const now = new Date();
    const livingWithDOB = persons.filter((p) => !p.isDeceased && p.dateOfBirth);
    let avgAge = 0;
    if (livingWithDOB.length > 0) {
      const totalAge = livingWithDOB.reduce((acc, p) => {
        const age = (now.getTime() - p.dateOfBirth!.getTime()) / (365.25 * 24 * 60 * 60 * 1000);
        return acc + age;
      }, 0);
      avgAge = Math.round((totalAge / livingWithDOB.length) * 10) / 10;
    }

    // Top relationship types
    const relTypeCounts: Record<string, number> = {};
    for (const rel of relationships) {
      relTypeCounts[rel.type] = (relTypeCounts[rel.type] || 0) + 1;
    }
    const topRelationshipTypes = Object.entries(relTypeCounts)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 10)
      .map(([type, count]) => ({ type, count }));

    const memberCount = await this.prisma.familyMember.count({ where: { familyId } });

    return {
      totalPersons: totalCount,
      livingCount,
      deceasedCount,
      genderDistribution,
      averageAge: avgAge,
      topRelationshipTypes,
      totalRelationships: relationships.length,
      memberCount,
    };
  }

  // ── Leaderboard ─────────────────────────────────────────────────────

  async getLeaderboard(familyId: string, page = 1, limit = 25) {
    const family = await this.prisma.family.findUnique({ where: { id: familyId } });
    if (!family) throw new NotFoundException('Family not found');

    const [contributions, total] = await Promise.all([
      this.prisma.userContribution.findMany({
        where: { familyId },
        skip: (page - 1) * limit,
        take: limit,
        orderBy: { totalPoints: 'desc' },
        include: { user: { select: { id: true, name: true, email: true } } },
      }),
      this.prisma.userContribution.count({ where: { familyId } }),
    ]);

    const leaderboard = contributions.map((c, index) => {
      const rank = (page - 1) * limit + index + 1;
      const levelInfo = this.getLevel(c.totalPoints);

      return {
        rank,
        userId: c.userId,
        userName: c.user.name || c.user.email,
        totalPoints: c.totalPoints,
        level: levelInfo,
        stats: {
          personsAdded: c.personsAdded,
          relationshipsAdded: c.relationshipsAdded,
          photosAdded: c.photosAdded,
          eventsCreated: c.eventsCreated,
          storiesShared: c.storiesShared,
          commentsWritten: c.commentsWritten,
          invitationsSent: c.invitationsSent,
          personsEdited: c.personsEdited,
        },
      };
    });

    const familyBadges = await this.prisma.userBadge.findMany({
      where: { familyId },
      include: { badge: true, user: { select: { id: true, name: true } } },
      orderBy: { earnedAt: 'desc' },
      take: 10,
    });

    const familyTotals = await this.prisma.userContribution.aggregate({
      where: { familyId },
      _sum: { totalPoints: true, personsAdded: true, relationshipsAdded: true, photosAdded: true },
    });

    return {
      family: { id: family.id, name: family.name },
      leaderboard,
      badges: familyBadges.map((ub) => ({
        badge: { id: ub.badge.id, slug: ub.badge.slug, name: ub.badge.name, icon: ub.badge.icon, tier: ub.badge.tier },
        earnedBy: ub.user.name,
        earnedAt: ub.earnedAt,
      })),
      totals: {
        totalPoints: familyTotals._sum.totalPoints ?? 0,
        personsAdded: familyTotals._sum.personsAdded ?? 0,
        relationshipsAdded: familyTotals._sum.relationshipsAdded ?? 0,
        photosAdded: familyTotals._sum.photosAdded ?? 0,
      },
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    };
  }

  // ── Comments ────────────────────────────────────────────────────────

  async listComments(postId: string, parentId?: string, page = 1, limit = 50) {
    const where: Record<string, unknown> = { postId, isHidden: false };
    if (parentId) where.parentId = parentId;
    else where.parentId = null;

    const [comments, total] = await Promise.all([
      this.prisma.comment.findMany({
        where,
        skip: (page - 1) * limit,
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

  async addComment(postId: string, dto: CreateCommentDto, userId: string) {
    if (dto.body.trim().length === 0) throw new BadRequestException('Comment cannot be empty');
    if (dto.body.length > MAX_COMMENT_LENGTH) {
      throw new BadRequestException(`Comment exceeds maximum length of ${MAX_COMMENT_LENGTH} characters`);
    }

    const post = await this.prisma.communityPost.findUnique({ where: { id: postId } });
    if (!post) throw new NotFoundException('Post not found');
    if (post.isLocked) throw new ForbiddenException('This post is locked for new comments');

    // Verify parent comment belongs to same post and is top-level
    if (dto.parentId) {
      const parentComment = await this.prisma.comment.findUnique({ where: { id: dto.parentId } });
      if (!parentComment || parentComment.postId !== postId) {
        throw new NotFoundException('Parent comment not found');
      }
      if (parentComment.parentId) {
        throw new BadRequestException('Only one level of comment nesting is supported');
      }
    }

    const comment = await this.prisma.comment.create({
      data: {
        postId,
        authorId: userId,
        parentId: dto.parentId || null,
        body: dto.body.trim(),
      },
      include: { author: { select: { id: true, name: true } } },
    });

    // Record contribution
    const authorFamily = await this.prisma.familyMember.findFirst({ where: { userId } });
    if (authorFamily) {
      await this.recordContribution(userId, authorFamily.familyId, 'commentWritten');
    }

    return { comment };
  }

  // ── Reactions ───────────────────────────────────────────────────────

  async toggleReaction(postId: string, dto: ToggleReactionDto, userId: string) {
    const post = await this.prisma.communityPost.findUnique({ where: { id: postId } });
    if (!post) throw new NotFoundException('Post not found');

    const existing = await this.prisma.reaction.findUnique({
      where: { postId_userId_emoji: { postId, userId, emoji: dto.emoji } },
    });

    if (existing) {
      await this.prisma.reaction.delete({ where: { id: existing.id } });
      return { action: 'removed', emoji: dto.emoji };
    } else {
      await this.prisma.reaction.create({
        data: { postId, userId, emoji: dto.emoji },
      });
      return { action: 'added', emoji: dto.emoji };
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  private getLevel(points: number): { level: number; name: string; nextAt: number } {
    const levels = [
      { level: 1, name: 'Seed', nextAt: 0 },
      { level: 2, name: 'Sprout', nextAt: 50 },
      { level: 3, name: 'Sapling', nextAt: 200 },
      { level: 4, name: 'Tree', nextAt: 500 },
      { level: 5, name: 'Oak', nextAt: 1000 },
      { level: 6, name: 'Banyan', nextAt: 2500 },
      { level: 7, name: 'Elder', nextAt: 5000 },
    ];

    let current = levels[0];
    for (const l of levels) {
      if (points >= l.nextAt) current = l;
    }
    return current;
  }

  private async recordContribution(userId: string, familyId: string, type: string) {
    const pointsMap: Record<string, { field: string; points: number }> = {
      personsAdded: { field: 'personsAdded', points: 5 },
      relationshipsAdded: { field: 'relationshipsAdded', points: 10 },
      photosAdded: { field: 'photosAdded', points: 2 },
      eventsCreated: { field: 'eventsCreated', points: 15 },
      storiesShared: { field: 'storiesShared', points: 8 },
      commentsWritten: { field: 'commentsWritten', points: 3 },
      invitationsSent: { field: 'invitationsSent', points: 5 },
      communityJoin: { field: 'personsEdited', points: 2 },
      commentWritten: { field: 'commentsWritten', points: 3 },
      eventCreated: { field: 'eventsCreated', points: 15 },
    };

    const config = pointsMap[type];
    if (!config) return;

    await this.prisma.userContribution.upsert({
      where: { userId_familyId: { userId, familyId } },
      create: {
        userId,
        familyId,
        [config.field]: 1,
        totalPoints: config.points,
      },
      update: {
        [config.field]: { increment: 1 },
        totalPoints: { increment: config.points },
      },
    });
  }
}
