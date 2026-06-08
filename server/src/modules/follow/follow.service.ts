import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { FollowPaginationDto } from './dto/follow.dto';

@Injectable()
export class FollowService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: KinrelGateway,
  ) {}

  /** Follow a user — instant if public, pending request if private */
  async followUser(followerId: string, followingId: string) {
    if (followerId === followingId) {
      throw new BadRequestException('You cannot follow yourself');
    }

    // Check if already following / request pending
    const existing = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId, followingId } },
    });
    if (existing) {
      throw new ConflictException(
        existing.status === 'PENDING'
          ? 'Follow request already pending'
          : 'Already following this user',
      );
    }

    // Ensure target user exists
    const targetUser = await this.prisma.user.findUnique({
      where: { id: followingId },
      select: { id: true, name: true, avatarUrl: true, isPrivate: true },
    });
    if (!targetUser) {
      throw new NotFoundException('User not found');
    }

    const status = targetUser.isPrivate ? 'PENDING' : 'ACCEPTED';

    const follow = await this.prisma.follow.create({
      data: { followerId, followingId, status },
    });

    // Emit socket events
    const followerProfile = await this.prisma.user.findUnique({
      where: { id: followerId },
      select: { id: true, name: true, avatarUrl: true },
    });

    if (status === 'PENDING') {
      this.gateway.emitToUser(followingId, 'follow:request', {
        follower: followerProfile,
      });
    } else {
      // Accepted immediately — notify the target that someone followed them
      this.gateway.emitToUser(followingId, 'follow:new', {
        follower: followerProfile,
      });
    }

    return { ...follow, status };
  }

  /** Unfollow a user — removes the Follow record regardless of status */
  async unfollowUser(followerId: string, followingId: string) {
    const existing = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId, followingId } },
    });
    if (!existing) {
      throw new NotFoundException('Not following this user');
    }
    await this.prisma.follow.delete({
      where: { id: existing.id },
    });
    return { success: true };
  }

  /** Accept a follow request — only the target user can accept */
  async acceptRequest(userId: string, followerId: string) {
    const follow = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId, followingId: userId } },
    });
    if (!follow) {
      throw new NotFoundException('Follow request not found');
    }
    if (follow.status !== 'PENDING') {
      throw new BadRequestException('Follow request is not pending');
    }

    const updated = await this.prisma.follow.update({
      where: { id: follow.id },
      data: { status: 'ACCEPTED' },
    });

    // Notify the original requester that their follow was accepted
    const followingProfile = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, name: true },
    });
    this.gateway.emitToUser(followerId, 'follow:accepted', {
      following: followingProfile,
    });

    return updated;
  }

  /** Reject a follow request — deletes the Follow record */
  async rejectRequest(userId: string, followerId: string) {
    const follow = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId, followingId: userId } },
    });
    if (!follow) {
      throw new NotFoundException('Follow request not found');
    }
    if (follow.status !== 'PENDING') {
      throw new BadRequestException('Follow request is not pending');
    }

    await this.prisma.follow.delete({ where: { id: follow.id } });

    this.gateway.emitToUser(followerId, 'follow:rejected', {
      followingId: userId,
    });

    return { success: true };
  }

  /** Get paginated list of the current user's followers */
  async getFollowers(userId: string, dto: FollowPaginationDto) {
    const page = dto.page ?? 1;
    const limit = dto.limit ?? 20;
    const skip = (page - 1) * limit;

    const [items, total] = await Promise.all([
      this.prisma.follow.findMany({
        where: { followingId: userId, status: 'ACCEPTED' },
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: {
          follower: {
            select: { id: true, name: true, username: true, avatarUrl: true, photoThumb: true },
          },
        },
      }),
      this.prisma.follow.count({
        where: { followingId: userId, status: 'ACCEPTED' },
      }),
    ]);

    return {
      items: items.map((f) => ({ ...f.follower, followId: f.id, followedAt: f.createdAt })),
      total,
      page,
      limit,
    };
  }

  /** Get paginated list of users the current user is following */
  async getFollowing(userId: string, dto: FollowPaginationDto) {
    const page = dto.page ?? 1;
    const limit = dto.limit ?? 20;
    const skip = (page - 1) * limit;

    const [items, total] = await Promise.all([
      this.prisma.follow.findMany({
        where: { followerId: userId, status: 'ACCEPTED' },
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: {
          following: {
            select: { id: true, name: true, username: true, avatarUrl: true, photoThumb: true },
          },
        },
      }),
      this.prisma.follow.count({
        where: { followerId: userId, status: 'ACCEPTED' },
      }),
    ]);

    return {
      items: items.map((f) => ({ ...f.following, followId: f.id, followedAt: f.createdAt })),
      total,
      page,
      limit,
    };
  }

  /** Get pending follow requests received by the current user */
  async getPendingRequests(userId: string) {
    const requests = await this.prisma.follow.findMany({
      where: { followingId: userId, status: 'PENDING' },
      orderBy: { createdAt: 'desc' },
      include: {
        follower: {
          select: { id: true, name: true, username: true, avatarUrl: true, photoThumb: true },
        },
      },
    });

    return requests.map((r) => ({ ...r.follower, followId: r.id, requestedAt: r.createdAt }));
  }

  /** Get follow relationship status with a specific user */
  async getFollowStatus(currentUserId: string, targetUserId: string) {
    if (currentUserId === targetUserId) {
      return { status: 'self' };
    }

    const follow = await this.prisma.follow.findUnique({
      where: { followerId_followingId: { followerId: currentUserId, followingId: targetUserId } },
    });

    if (!follow) {
      // Check if the target has a pending request towards the current user
      const reverseFollow = await this.prisma.follow.findUnique({
        where: { followerId_followingId: { followerId: targetUserId, followingId: currentUserId } },
      });
      if (reverseFollow?.status === 'PENDING') {
        return { status: 'pending_incoming' };
      }
      return { status: 'none' };
    }

    return { status: follow.status === 'ACCEPTED' ? 'following' : 'pending' };
  }

  /** Get follower and following counts for a user */
  async getFollowCounts(userId: string) {
    const [followerCount, followingCount] = await Promise.all([
      this.prisma.follow.count({ where: { followingId: userId, status: 'ACCEPTED' } }),
      this.prisma.follow.count({ where: { followerId: userId, status: 'ACCEPTED' } }),
    ]);
    return { followerCount, followingCount };
  }
}
