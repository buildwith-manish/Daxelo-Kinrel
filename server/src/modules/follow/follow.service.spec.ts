import { Test, TestingModule } from '@nestjs/testing';
import { FollowService } from './follow.service';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';

describe('FollowService', () => {
  let service: FollowService;
  let prisma: PrismaService;
  let gateway: KinrelGateway;

  const mockPrisma = {
    follow: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    user: {
      findUnique: jest.fn(),
    },
  };

  const mockGateway = {
    emitToUser: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FollowService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: KinrelGateway, useValue: mockGateway },
      ],
    }).compile();

    service = module.get<FollowService>(FollowService);
    prisma = module.get<PrismaService>(PrismaService);
    gateway = module.get<KinrelGateway>(KinrelGateway);

    // Reset all mocks before each test
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ─── followUser ────────────────────────────────────────────────────
  describe('followUser', () => {
    const followerId = 'user-1';
    const followingId = 'user-2';

    it('should throw BadRequestException if following self', async () => {
      await expect(service.followUser('user-1', 'user-1')).rejects.toThrow(
        BadRequestException,
      );
      await expect(service.followUser('user-1', 'user-1')).rejects.toThrow(
        'You cannot follow yourself',
      );
    });

    it('should throw ConflictException if already following', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId,
        status: 'ACCEPTED',
      });

      await expect(service.followUser(followerId, followingId)).rejects.toThrow(
        ConflictException,
      );
      await expect(service.followUser(followerId, followingId)).rejects.toThrow(
        'Already following this user',
      );
    });

    it('should throw ConflictException if follow request already pending', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId,
        status: 'PENDING',
      });

      await expect(service.followUser(followerId, followingId)).rejects.toThrow(
        ConflictException,
      );
      await expect(service.followUser(followerId, followingId)).rejects.toThrow(
        'Follow request already pending',
      );
    });

    it('should throw NotFoundException if target user not found', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(service.followUser(followerId, followingId)).rejects.toThrow(
        NotFoundException,
      );
      await expect(service.followUser(followerId, followingId)).rejects.toThrow(
        'User not found',
      );
    });

    it('should create PENDING follow for private users', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);
      mockPrisma.user.findUnique
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
      mockPrisma.follow.create.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId,
        status: 'PENDING',
      });

      const result = await service.followUser(followerId, followingId);

      expect(result.status).toBe('PENDING');
      expect(mockPrisma.follow.create).toHaveBeenCalledWith({
        data: { followerId, followingId, status: 'PENDING' },
      });
    });

    it('should create ACCEPTED follow for public users', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({
          id: followingId,
          name: 'Public User',
          avatarUrl: null,
          isPrivate: false,
        })
        .mockResolvedValueOnce({
          id: followerId,
          name: 'Follower',
          avatarUrl: null,
        });
      mockPrisma.follow.create.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId,
        status: 'ACCEPTED',
      });

      const result = await service.followUser(followerId, followingId);

      expect(result.status).toBe('ACCEPTED');
      expect(mockPrisma.follow.create).toHaveBeenCalledWith({
        data: { followerId, followingId, status: 'ACCEPTED' },
      });
    });

    it('should emit follow:request socket event for private users', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);
      mockPrisma.user.findUnique
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
      mockPrisma.follow.create.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId,
        status: 'PENDING',
      });

      await service.followUser(followerId, followingId);

      expect(gateway.emitToUser).toHaveBeenCalledWith(
        followingId,
        'follow:request',
        { follower: { id: followerId, name: 'Follower', avatarUrl: null } },
      );
    });

    it('should emit follow:new socket event for public users', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({
          id: followingId,
          name: 'Public User',
          avatarUrl: null,
          isPrivate: false,
        })
        .mockResolvedValueOnce({
          id: followerId,
          name: 'Follower',
          avatarUrl: null,
        });
      mockPrisma.follow.create.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId,
        status: 'ACCEPTED',
      });

      await service.followUser(followerId, followingId);

      expect(gateway.emitToUser).toHaveBeenCalledWith(
        followingId,
        'follow:new',
        { follower: { id: followerId, name: 'Follower', avatarUrl: null } },
      );
    });
  });

  // ─── unfollowUser ──────────────────────────────────────────────────
  describe('unfollowUser', () => {
    const followerId = 'user-1';
    const followingId = 'user-2';

    it('should throw NotFoundException if not following', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);

      await expect(
        service.unfollowUser(followerId, followingId),
      ).rejects.toThrow(NotFoundException);
      await expect(
        service.unfollowUser(followerId, followingId),
      ).rejects.toThrow('Not following this user');
    });

    it('should delete follow record', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId,
        status: 'ACCEPTED',
      });
      mockPrisma.follow.delete.mockResolvedValue({ id: 'f1' });

      const result = await service.unfollowUser(followerId, followingId);

      expect(mockPrisma.follow.delete).toHaveBeenCalledWith({
        where: { id: 'f1' },
      });
      expect(result).toEqual({ success: true });
    });
  });

  // ─── acceptRequest ─────────────────────────────────────────────────
  describe('acceptRequest', () => {
    const userId = 'user-2'; // the target user accepting
    const followerId = 'user-1'; // the one who requested

    it('should throw NotFoundException if follow not found', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);

      await expect(
        service.acceptRequest(userId, followerId),
      ).rejects.toThrow(NotFoundException);
      await expect(
        service.acceptRequest(userId, followerId),
      ).rejects.toThrow('Follow request not found');
    });

    it('should throw BadRequestException if not PENDING', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId: userId,
        status: 'ACCEPTED',
      });

      await expect(
        service.acceptRequest(userId, followerId),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.acceptRequest(userId, followerId),
      ).rejects.toThrow('Follow request is not pending');
    });

    it('should update status to ACCEPTED and emit follow:accepted', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId: userId,
        status: 'PENDING',
      });
      mockPrisma.follow.update.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId: userId,
        status: 'ACCEPTED',
      });
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        name: 'Target User',
      });

      const result = await service.acceptRequest(userId, followerId);

      expect(mockPrisma.follow.update).toHaveBeenCalledWith({
        where: { id: 'f1' },
        data: { status: 'ACCEPTED' },
      });
      expect(gateway.emitToUser).toHaveBeenCalledWith(
        followerId,
        'follow:accepted',
        { following: { id: userId, name: 'Target User' } },
      );
      expect(result.status).toBe('ACCEPTED');
    });
  });

  // ─── rejectRequest ─────────────────────────────────────────────────
  describe('rejectRequest', () => {
    const userId = 'user-2';
    const followerId = 'user-1';

    it('should throw NotFoundException if follow not found', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue(null);

      await expect(
        service.rejectRequest(userId, followerId),
      ).rejects.toThrow(NotFoundException);
      await expect(
        service.rejectRequest(userId, followerId),
      ).rejects.toThrow('Follow request not found');
    });

    it('should throw BadRequestException if not PENDING', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId: userId,
        status: 'ACCEPTED',
      });

      await expect(
        service.rejectRequest(userId, followerId),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.rejectRequest(userId, followerId),
      ).rejects.toThrow('Follow request is not pending');
    });

    it('should delete follow and emit follow:rejected', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        followerId,
        followingId: userId,
        status: 'PENDING',
      });
      mockPrisma.follow.delete.mockResolvedValue({ id: 'f1' });

      const result = await service.rejectRequest(userId, followerId);

      expect(mockPrisma.follow.delete).toHaveBeenCalledWith({
        where: { id: 'f1' },
      });
      expect(gateway.emitToUser).toHaveBeenCalledWith(
        followerId,
        'follow:rejected',
        { followingId: userId },
      );
      expect(result).toEqual({ success: true });
    });
  });

  // ─── getFollowers ──────────────────────────────────────────────────
  describe('getFollowers', () => {
    it('should return paginated followers with profile info', async () => {
      const items = [
        {
          id: 'f1',
          followerId: 'user-1',
          followingId: 'user-2',
          status: 'ACCEPTED',
          createdAt: new Date(),
          follower: {
            id: 'user-1',
            name: 'Follower 1',
            username: 'follower1',
            avatarUrl: null,
            photoThumb: null,
          },
        },
      ];
      mockPrisma.follow.findMany.mockResolvedValue(items);
      mockPrisma.follow.count.mockResolvedValue(1);

      const result = await service.getFollowers('user-2', {
        page: 1,
        limit: 20,
      });

      expect(result.items).toHaveLength(1);
      expect(result.items[0]).toMatchObject({
        id: 'user-1',
        name: 'Follower 1',
        followId: 'f1',
      });
      expect(result.total).toBe(1);
      expect(result.page).toBe(1);
      expect(result.limit).toBe(20);
    });
  });

  // ─── getFollowing ──────────────────────────────────────────────────
  describe('getFollowing', () => {
    it('should return paginated following with profile info', async () => {
      const items = [
        {
          id: 'f1',
          followerId: 'user-1',
          followingId: 'user-2',
          status: 'ACCEPTED',
          createdAt: new Date(),
          following: {
            id: 'user-2',
            name: 'Following 1',
            username: 'following1',
            avatarUrl: null,
            photoThumb: null,
          },
        },
      ];
      mockPrisma.follow.findMany.mockResolvedValue(items);
      mockPrisma.follow.count.mockResolvedValue(1);

      const result = await service.getFollowing('user-1', {
        page: 1,
        limit: 20,
      });

      expect(result.items).toHaveLength(1);
      expect(result.items[0]).toMatchObject({
        id: 'user-2',
        name: 'Following 1',
        followId: 'f1',
      });
      expect(result.total).toBe(1);
    });
  });

  // ─── getPendingRequests ────────────────────────────────────────────
  describe('getPendingRequests', () => {
    it('should return pending requests with follower info', async () => {
      const requests = [
        {
          id: 'f1',
          followerId: 'user-1',
          followingId: 'user-2',
          status: 'PENDING',
          createdAt: new Date(),
          follower: {
            id: 'user-1',
            name: 'Requester',
            username: 'requester1',
            avatarUrl: null,
            photoThumb: null,
          },
        },
      ];
      mockPrisma.follow.findMany.mockResolvedValue(requests);

      const result = await service.getPendingRequests('user-2');

      expect(result).toHaveLength(1);
      expect(result[0]).toMatchObject({
        id: 'user-1',
        name: 'Requester',
        followId: 'f1',
      });
    });
  });

  // ─── getFollowStatus ───────────────────────────────────────────────
  describe('getFollowStatus', () => {
    it('should return self if same user', async () => {
      const result = await service.getFollowStatus('user-1', 'user-1');
      expect(result).toEqual({ status: 'self' });
    });

    it('should return following if ACCEPTED follow exists', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        status: 'ACCEPTED',
      });

      const result = await service.getFollowStatus('user-1', 'user-2');
      expect(result).toEqual({ status: 'following' });
    });

    it('should return pending if PENDING follow exists', async () => {
      mockPrisma.follow.findUnique.mockResolvedValue({
        id: 'f1',
        status: 'PENDING',
      });

      const result = await service.getFollowStatus('user-1', 'user-2');
      expect(result).toEqual({ status: 'pending' });
    });

    it('should return pending_incoming if reverse PENDING exists', async () => {
      mockPrisma.follow.findUnique
        .mockResolvedValueOnce(null) // forward check
        .mockResolvedValueOnce({ id: 'f2', status: 'PENDING' }); // reverse check

      const result = await service.getFollowStatus('user-1', 'user-2');
      expect(result).toEqual({ status: 'pending_incoming' });
    });

    it('should return none if no follow relationship', async () => {
      mockPrisma.follow.findUnique
        .mockResolvedValueOnce(null) // forward
        .mockResolvedValueOnce(null); // reverse

      const result = await service.getFollowStatus('user-1', 'user-2');
      expect(result).toEqual({ status: 'none' });
    });

    it('should return none if reverse is ACCEPTED (not pending)', async () => {
      mockPrisma.follow.findUnique
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({ id: 'f2', status: 'ACCEPTED' });

      const result = await service.getFollowStatus('user-1', 'user-2');
      expect(result).toEqual({ status: 'none' });
    });
  });

  // ─── getFollowCounts ───────────────────────────────────────────────
  describe('getFollowCounts', () => {
    it('should return follower and following counts', async () => {
      mockPrisma.follow.count
        .mockResolvedValueOnce(42) // follower count
        .mockResolvedValueOnce(15); // following count

      const result = await service.getFollowCounts('user-1');

      expect(result).toEqual({ followerCount: 42, followingCount: 15 });
      expect(mockPrisma.follow.count).toHaveBeenCalledTimes(2);
    });
  });
});
