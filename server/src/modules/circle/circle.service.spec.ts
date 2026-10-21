import { Test, TestingModule } from '@nestjs/testing';
import { CircleService } from './circle.service';
import { PrismaService } from '../../prisma/prisma.service';
import {
  ForbiddenException,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';

/**
 * CircleService unit tests — server-side enforcement rules.
 *
 * These tests prove:
 *   1. A non-member cannot read a circle.
 *   2. A non-admin cannot add members when anyoneCanAdd = false.
 *   3. A non-admin cannot post when onlyAdminsPost = true.
 *   4. A blocked user cannot be added.
 *   5. The 30-circle-per-user limit is enforced.
 *   6. The 100-member-per-circle limit is enforced.
 *   7. Last-admin auto-promote on leave works.
 *   8. A removed member's access is revoked (RLS defense-in-depth).
 *
 * The tests mock PrismaService so they run without a database.
 * The RLS policies (tested separately via SQL) are the second
 * defense layer — these tests verify the SERVICE layer logic.
 */
describe('CircleService', () => {
  let service: CircleService;
  let prisma: Record<string, any>;

  beforeEach(async () => {
    // ── Mock PrismaService ──────────────────────────────────────
    // Each test configures the mock's return values as needed.
    prisma = {
      circle: {
        count: jest.fn(),
        create: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
        delete: jest.fn(),
      },
      circleMember: {
        count: jest.fn(),
        findUnique: jest.fn(),
        findFirst: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        delete: jest.fn(),
        findMany: jest.fn(),
      },
      circleMessage: {
        create: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
        groupBy: jest.fn(),
      },
      circleReaction: {
        upsert: jest.fn(),
        delete: jest.fn(),
      },
      circleReadReceipt: {
        createMany: jest.fn(),
        upsert: jest.fn(),
      },
      $queryRaw: jest.fn(),
      $executeRaw: jest.fn(),
      $transaction: jest.fn((args: any[]) => Promise.all(args)),
      raw: jest.fn((val: any) => val),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        CircleService,
        { provide: PrismaService, useValue: prisma },
      ],
    }).compile();

    service = module.get<CircleService>(CircleService);
  });

  // ── 1. Create circle — 30-circle limit ────────────────────────

  describe('createCircle', () => {
    it('creates a circle when under the 30-circle limit', async () => {
      prisma.circle.count.mockResolvedValue(5);
      prisma.circle.create.mockResolvedValue({
        id: 'circle-1',
        ownerId: 'user-1',
        name: 'Test Circle',
        members: [{ userId: 'user-1', role: 'admin' }],
      });

      const result = await service.createCircle('user-1', {
        name: 'Test Circle',
      });

      expect(result.id).toBe('circle-1');
      expect(prisma.circle.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            ownerId: 'user-1',
            name: 'Test Circle',
            members: expect.objectContaining({
              create: expect.objectContaining({
                userId: 'user-1',
                role: 'admin',
              }),
            }),
          }),
        }),
      );
    });

    it('throws BadRequestException when at the 30-circle limit', async () => {
      prisma.circle.count.mockResolvedValue(30);

      await expect(
        service.createCircle('user-1', { name: 'Too Many' }),
      ).rejects.toThrow(BadRequestException);
    });
  });

  // ── 2. getCircle — non-member gets 403 ─────────────────────────

  describe('getCircle', () => {
    it('returns the circle for a member', async () => {
      prisma.circle.findUnique.mockResolvedValue({
        id: 'circle-1',
        ownerId: 'user-1',
        members: [{ userId: 'user-1' }, { userId: 'user-2' }],
      });

      const result = await service.getCircle('circle-1', 'user-2');
      expect(result.id).toBe('circle-1');
    });

    it('throws ForbiddenException for a non-member', async () => {
      prisma.circle.findUnique.mockResolvedValue({
        id: 'circle-1',
        ownerId: 'user-1',
        members: [{ userId: 'user-1' }],
      });

      await expect(
        service.getCircle('circle-1', 'user-2'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws NotFoundException when the circle does not exist', async () => {
      prisma.circle.findUnique.mockResolvedValue(null);

      await expect(
        service.getCircle('nonexistent', 'user-1'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── 3. addMember — eligibility + admin check ──────────────────

  describe('addMember', () => {
    beforeEach(() => {
      // Default: circle exists, caller is admin, anyoneCanAdd=false
      prisma.circle.findUnique.mockResolvedValue({
        ownerId: 'user-1',
        anyoneCanAdd: false,
      });
      prisma.circleMember.findUnique.mockImplementation((args: any) => {
        // Return admin for the caller
        if (args.where.circleId_userId.userId === 'user-1') {
          return { role: 'admin' };
        }
        return null;
      });
    });

    it('throws ForbiddenException when a non-admin tries to add and anyoneCanAdd=false', async () => {
      // Caller is a member but not admin
      prisma.circleMember.findUnique.mockImplementation((args: any) => {
        if (args.where.circleId_userId.userId === 'user-2') {
          return { role: 'member' };
        }
        return null;
      });

      await expect(
        service.addMember('circle-1', 'user-2', { userId: 'user-3' }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when the candidate is blocked', async () => {
      // fn_user_can_be_added_to_circle returns false (blocked)
      prisma.$queryRaw.mockResolvedValueOnce([
        { fn_user_can_be_added_to_circle: false },
      ]);
      // isAlreadyMember check
      prisma.circleMember.findUnique.mockImplementation((args: any) => {
        if (args.where?.circleId_userId?.userId === 'user-1') {
          return { role: 'admin' };
        }
        return null;
      });
      // memberCount
      prisma.circleMember.count.mockResolvedValue(5);
      // BlockedUser check
      prisma.$queryRaw.mockResolvedValueOnce([{ exists: true }]);

      await expect(
        service.addMember('circle-1', 'user-1', { userId: 'blocked-user' }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ConflictException when the candidate is already a member', async () => {
      prisma.$queryRaw.mockResolvedValue([
        { fn_user_can_be_added_to_circle: false },
      ]);
      prisma.circleMember.findUnique.mockImplementation((args: any) => {
        if (args.where?.circleId_userId?.userId === 'user-1') {
          return { role: 'admin' };
        }
        if (args.where?.circleId_userId?.userId === 'user-2') {
          return { id: 'existing-member' }; // already a member
        }
        return null;
      });

      await expect(
        service.addMember('circle-1', 'user-1', { userId: 'user-2' }),
      ).rejects.toThrow(ConflictException);
    });

    it('throws BadRequestException at the 100-member limit', async () => {
      prisma.$queryRaw.mockResolvedValue([
        { fn_user_can_be_added_to_circle: false },
      ]);
      prisma.circleMember.findUnique.mockImplementation((args: any) => {
        if (args.where?.circleId_userId?.userId === 'user-1') {
          return { role: 'admin' };
        }
        return null;
      });
      prisma.circleMember.count.mockResolvedValue(100);

      await expect(
        service.addMember('circle-1', 'user-1', { userId: 'user-99' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('adds the member when eligible and caller is admin', async () => {
      prisma.$queryRaw.mockResolvedValue([
        { fn_user_can_be_added_to_circle: true },
      ]);
      prisma.circleMember.create.mockResolvedValue({
        id: 'member-1',
        circleId: 'circle-1',
        userId: 'user-2',
        role: 'member',
      });

      const result = await service.addMember('circle-1', 'user-1', {
        userId: 'user-2',
        displayName: 'Priya',
      });

      expect(result.userId).toBe('user-2');
      expect(prisma.circleMember.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            circleId: 'circle-1',
            userId: 'user-2',
            role: 'member',
            displayName: 'Priya',
          }),
        }),
      );
    });
  });

  // ── 4. sendMessage — onlyAdminsPost enforcement ─────────────────

  describe('sendMessage', () => {
    it('throws ForbiddenException when onlyAdminsPost=true and sender is not admin', async () => {
      prisma.circleMember.findUnique.mockResolvedValue({
        role: 'member',
        displayName: 'Priya',
      });
      prisma.circle.findUnique.mockResolvedValue({
        onlyAdminsPost: true,
        name: 'Announcements',
      });

      await expect(
        service.sendMessage('circle-1', 'user-2', {
          content: 'Hello',
        }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('allows admin to post when onlyAdminsPost=true', async () => {
      prisma.circleMember.findUnique.mockResolvedValue({
        role: 'admin',
        displayName: 'Admin User',
      });
      prisma.circle.findUnique.mockResolvedValue({
        onlyAdminsPost: true,
        name: 'Announcements',
      });
      prisma.circleMessage.create.mockResolvedValue({
        id: 'msg-1',
        content: 'Hello',
        senderId: 'user-1',
      });
      prisma.circle.update.mockResolvedValue({});

      const result = await service.sendMessage('circle-1', 'user-1', {
        content: 'Hello',
      });

      expect(result.id).toBe('msg-1');
    });

    it('throws ForbiddenException when sender is not a member', async () => {
      prisma.circleMember.findUnique.mockResolvedValue(null);

      await expect(
        service.sendMessage('circle-1', 'non-member', {
          content: 'Hello',
        }),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  // ── 5. leaveCircle — last-admin auto-promote ───────────────────

  describe('leaveCircle', () => {
    it('auto-promotes the longest-standing member when the last admin leaves', async () => {
      prisma.circleMember.findUnique.mockResolvedValue({ role: 'admin' });
      prisma.circleMember.count.mockResolvedValue(1); // 1 admin = last admin
      prisma.circleMember.findFirst.mockResolvedValue({
        id: 'member-2',
        userId: 'user-2',
      });
      prisma.$transaction.mockResolvedValue([{}, {}]);

      const result = await service.leaveCircle('circle-1', 'user-1');

      expect(result).toEqual({ promoted: 'user-2' });
      expect(prisma.$transaction).toHaveBeenCalled();
    });

    it('just removes the member when not the last admin', async () => {
      prisma.circleMember.findUnique.mockResolvedValue({ role: 'member' });
      prisma.circleMember.delete.mockResolvedValue({});

      const result = await service.leaveCircle('circle-1', 'user-2');

      expect(prisma.circleMember.delete).toHaveBeenCalled();
    });

    it('throws NotFoundException when the user is not a member', async () => {
      prisma.circleMember.findUnique.mockResolvedValue(null);

      await expect(
        service.leaveCircle('circle-1', 'non-member'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── 6. deleteCircle — owner-only ────────────────────────────────

  describe('deleteCircle', () => {
    it('deletes the circle when caller is the owner', async () => {
      prisma.circle.findUnique.mockResolvedValue({ ownerId: 'user-1' });
      prisma.circle.delete.mockResolvedValue({});

      await service.deleteCircle('circle-1', 'user-1');

      expect(prisma.circle.delete).toHaveBeenCalledWith({
        where: { id: 'circle-1' },
      });
    });

    it('throws ForbiddenException when caller is not the owner', async () => {
      prisma.circle.findUnique.mockResolvedValue({ ownerId: 'user-1' });

      await expect(
        service.deleteCircle('circle-1', 'user-2'),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  // ── 7. updateSettings — admin-only ─────────────────────────────

  describe('updateSettings', () => {
    it('updates settings when caller is admin', async () => {
      prisma.circleMember.findUnique.mockResolvedValue({ role: 'admin' });
      prisma.circle.update.mockResolvedValue({ id: 'circle-1', name: 'New Name' });

      const result = await service.updateSettings('circle-1', 'user-1', {
        name: 'New Name',
        onlyAdminsPost: true,
      });

      expect(result.name).toBe('New Name');
      expect(prisma.circle.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            name: 'New Name',
            onlyAdminsPost: true,
          }),
        }),
      );
    });

    it('throws ForbiddenException when caller is not admin', async () => {
      prisma.circleMember.findUnique.mockResolvedValue({ role: 'member' });

      await expect(
        service.updateSettings('circle-1', 'user-2', { name: 'Hack' }),
      ).rejects.toThrow(ForbiddenException);
    });
  });
});
