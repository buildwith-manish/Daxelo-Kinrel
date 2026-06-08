import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { FollowPaginationDto } from './dto/follow-user.dto';

@Injectable()
export class FollowService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: KinrelGateway,
  ) {}

  // ── Follow User ─────────────────────────────────────────────────

  /** Follow a user. If the target is private, creates a PENDING request; otherwise ACCEPTED immediately. */
  async followUser(followerId: string, targetUserId: string) {
    if (followerId === targetUserId) {
      throw new BadRequestException('Cannot follow yourself');
    }

    // Check if target user exists
    const targetUser = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: { id: true, isPrivate: true, name: true, avatarUrl: true, photoThumb: true },
    });

    if (!targetUser) {
      throw new NotFoundException('User not found');
    }

    // Check if already following or pending
    const existing = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId, followingId: targetUserId } },
    });

    if (existing) {
      if (existing.status === 'ACCEPTED') {
        throw new ConflictException('Already following this user');
      }
      if (existing.status === 'PENDING') {
        throw new ConflictException('Follow request already pending');
      }
    }

    // Get follower info for socket events
    const follower = await this.prisma.user.findUnique({
      where: { id: followerId },
      select: { id: true, name: true, avatarUrl: true, photoThumb: true },
    });

    if (!follower) {
      throw new NotFoundException('Follower user not found');
    }

    const status = targetUser.isPrivate ? 'PENDING' : 'ACCEPTED';

    const follow = await this.prisma.follow.create({
      data: {
        followerId,
        followingId: targetUserId,
        status,
      },
    });

    // Emit socket events
    const followerAvatar = follower.photoThumb || follower.avatarUrl || null;
    const followerName = follower.name || 'Unknown';

    if (targetUser.isPrivate) {
      // Private profile: send follow:request to target
      this.gateway.emitToUser(targetUserId, 'follow:request', {
        followerId,
        followerName,
        followerAvatar,
      });
    } else {
      // Public profile: send follow:new to target
      this.gateway.emitToUser(targetUserId, 'follow:new', {
        followerId,
        followerName,
        followerAvatar,
      });
    }

    return {
      id: follow.id,
      followerId: follow.followerId,
      followingId: follow.followingId,
      status: follow.status,
      createdAt: follow.createdAt,
    };
  }

  // ── Unfollow User ───────────────────────────────────────────────

  /** Unfollow a user — deletes the Follow record regardless of status. */
  async unfollowUser(followerId: string, targetUserId: string) {
    const existing = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId, followingId: targetUserId } },
    });

    if (!existing) {
      throw new NotFoundException('Not following this user');
    }

    await this.prisma.follow.delete({
      where: { followerId_followingId: { followerId, followingId: targetUserId } },
    });

    return { unfollowed: true, userId: targetUserId };
  }

  // ── Accept Follow Request ───────────────────────────────────────

  /** Accept a pending follow request. Only the target (private profile owner) can accept. */
  async acceptFollowRequest(userId: string, requesterId: string) {
    const follow = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId: requesterId, followingId: userId } },
    });

    if (!follow) {
      throw new NotFoundException('Follow request not found');
    }

    if (follow.status !== 'PENDING') {
      throw new BadRequestException('Follow request is not pending');
    }

    // Only the user being followed (followingId) can accept
    if (follow.followingId !== userId) {
      throw new ForbiddenException('Only the profile owner can accept follow requests');
    }

    const updated = await this.prisma.follow.update({
      where: { id: follow.id },
      data: { status: 'ACCEPTED' },
    });

    // Get user info for socket event
    const followingUser = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { name: true },
    });

    // Emit follow:accepted to the requester
    this.gateway.emitToUser(requesterId, 'follow:accepted', {
      followingId: userId,
      followingName: followingUser?.name || 'Unknown',
    });

    return {
      id: updated.id,
      followerId: updated.followerId,
      followingId: updated.followingId,
      status: updated.status,
    };
  }

  // ── Reject Follow Request ───────────────────────────────────────

  /** Reject a pending follow request — deletes the record. */
  async rejectFollowRequest(userId: string, requesterId: string) {
    const follow = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId: requesterId, followingId: userId } },
    });

    if (!follow) {
      throw new NotFoundException('Follow request not found');
    }

    if (follow.status !== 'PENDING') {
      throw new BadRequestException('Follow request is not pending');
    }

    if (follow.followingId !== userId) {
      throw new ForbiddenException('Only the profile owner can reject follow requests');
    }

    await this.prisma.follow.delete({
      where: { id: follow.id },
    });

    // Emit follow:rejected to the requester
    this.gateway.emitToUser(requesterId, 'follow:rejected', {
      followingId: userId,
    });

    return { rejected: true, requesterId };
  }

  // ── Get Followers ───────────────────────────────────────────────

  /** Get paginated list of users following the current user. */
  async getFollowers(userId: string, pagination: FollowPaginationDto) {
    const page = pagination.page ?? 1;
    const limit = pagination.limit ?? 20;
    const skip = (page - 1) * limit;

    const [followers, total] = await Promise.all([
      this.prisma.follow.findMany({
        where: { followingId: userId, status: 'ACCEPTED' },
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: {
          follower: {
            select: {
              id: true,
              name: true,
              username: true,
              avatarUrl: true,
              photoThumb: true,
              bio: true,
            },
          },
        },
      }),
      this.prisma.follow.count({
        where: { followingId: userId, status: 'ACCEPTED' },
      }),
    ]);

    return {
      items: followers.map((f) => ({
        id: f.id,
        user: {
          id: f.follower.id,
          name: f.follower.name,
          username: f.follower.username,
          avatarUrl: f.follower.photoThumb || f.follower.avatarUrl,
          bio: f.follower.bio,
        },
        createdAt: f.createdAt,
      })),
      total,
      page,
      limit,
    };
  }

  // ── Get Following ───────────────────────────────────────────────

  /** Get paginated list of users the current user is following. */
  async getFollowing(userId: string, pagination: FollowPaginationDto) {
    const page = pagination.page ?? 1;
    const limit = pagination.limit ?? 20;
    const skip = (page - 1) * limit;

    const [following, total] = await Promise.all([
      this.prisma.follow.findMany({
        where: { followerId: userId, status: 'ACCEPTED' },
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: {
          following: {
            select: {
              id: true,
              name: true,
              username: true,
              avatarUrl: true,
              photoThumb: true,
              bio: true,
            },
          },
        },
      }),
      this.prisma.follow.count({
        where: { followerId: userId, status: 'ACCEPTED' },
      }),
    ]);

    return {
      items: following.map((f) => ({
        id: f.id,
        user: {
          id: f.following.id,
          name: f.following.name,
          username: f.following.username,
          avatarUrl: f.following.photoThumb || f.following.avatarUrl,
          bio: f.following.bio,
        },
        createdAt: f.createdAt,
      })),
      total,
      page,
      limit,
    };
  }

  // ── Get Pending Follow Requests ─────────────────────────────────

  /** Get pending follow requests received by the current user (private profiles). */
  async getFollowRequests(userId: string) {
    const requests = await this.prisma.follow.findMany({
      where: { followingId: userId, status: 'PENDING' },
      orderBy: { createdAt: 'desc' },
      include: {
        follower: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            photoThumb: true,
            bio: true,
          },
        },
      },
    });

    return {
      items: requests.map((r) => ({
        id: r.id,
        user: {
          id: r.follower.id,
          name: r.follower.name,
          username: r.follower.username,
          avatarUrl: r.follower.photoThumb || r.follower.avatarUrl,
          bio: r.follower.bio,
        },
        createdAt: r.createdAt,
      })),
    };
  }

  // ── Get Follow Status ───────────────────────────────────────────

  /** Returns the follow status between current user and target user. */
  async getFollowStatus(currentUserId: string, targetUserId: string) {
    if (currentUserId === targetUserId) {
      return { status: 'self' };
    }

    const follow = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId: currentUserId, followingId: targetUserId } },
    });

    if (!follow) {
      return { status: 'none' };
    }

    if (follow.status === 'PENDING') {
      return { status: 'pending' };
    }

    if (follow.status === 'ACCEPTED') {
      return { status: 'following' };
    }

    return { status: 'none' };
  }

  // ── Get Follow Counts ───────────────────────────────────────────

  /** Returns follower and following counts for a user. */
  async getFollowCounts(userId: string) {
    const [followers, following] = await Promise.all([
      this.prisma.follow.count({
        where: { followingId: userId, status: 'ACCEPTED' },
      }),
      this.prisma.follow.count({
        where: { followerId: userId, status: 'ACCEPTED' },
      }),
    ]);

    return { followers, following };
  }
}
