// server/src/modules/chat/privacy.service.spec.ts
//
// Unit tests for PrivacyService — Tier 3 Feature 3.5.

import { Test, TestingModule } from '@nestjs/testing';
import { PrivacyService } from './privacy.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException } from '@nestjs/common';

describe('PrivacyService', () => {
  let service: PrivacyService;

  const mockPrisma = {
    user: { findUnique: jest.fn(), update: jest.fn() },
    familyMember: { findMany: jest.fn(), findFirst: jest.fn() },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PrivacyService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<PrivacyService>(PrivacyService);
    jest.clearAllMocks();
  });

  describe('getMySettings', () => {
    it('returns the user row when found', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        lastSeenVisibility: 'contacts',
        readReceiptsEnabled: false,
      });
      const result = await service.getMySettings('user-1');
      expect(result).toEqual({
        lastSeenVisibility: 'contacts',
        readReceiptsEnabled: false,
      });
    });

    it('returns defaults when the user row is missing', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);
      const result = await service.getMySettings('user-1');
      expect(result).toEqual({
        lastSeenVisibility: 'everyone',
        readReceiptsEnabled: true,
      });
    });
  });

  describe('updateMySettings — validation', () => {
    it('throws BadRequestException for an invalid lastSeenVisibility value', async () => {
      await expect(
        service.updateMySettings('user-1', { lastSeenVisibility: 'friends' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('returns the current settings when no params are passed', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        lastSeenVisibility: 'everyone',
        readReceiptsEnabled: true,
      });
      const result = await service.updateMySettings('user-1', {});
      expect(result).toEqual({
        lastSeenVisibility: 'everyone',
        readReceiptsEnabled: true,
      });
      expect(mockPrisma.user.update).not.toHaveBeenCalled();
    });
  });

  describe('updateMySettings — happy path', () => {
    it('updates lastSeenVisibility + readReceiptsEnabled together', async () => {
      mockPrisma.user.update.mockResolvedValue({});
      mockPrisma.user.findUnique.mockResolvedValue({
        lastSeenVisibility: 'nobody',
        readReceiptsEnabled: false,
      });
      const result = await service.updateMySettings('user-1', {
        lastSeenVisibility: 'nobody',
        readReceiptsEnabled: false,
      });
      expect(result).toEqual({
        lastSeenVisibility: 'nobody',
        readReceiptsEnabled: false,
      });
      expect(mockPrisma.user.update).toHaveBeenCalledWith({
        where: { id: 'user-1' },
        data: { lastSeenVisibility: 'nobody', readReceiptsEnabled: false },
      });
    });

    it('updates only one field (nulls are ignored)', async () => {
      mockPrisma.user.update.mockResolvedValue({});
      mockPrisma.user.findUnique.mockResolvedValue({
        lastSeenVisibility: 'everyone',
        readReceiptsEnabled: false,
      });
      await service.updateMySettings('user-1', {
        readReceiptsEnabled: false,
        lastSeenVisibility: null,
      });
      expect(mockPrisma.user.update).toHaveBeenCalledWith({
        where: { id: 'user-1' },
        data: { readReceiptsEnabled: false },
      });
    });
  });

  describe('canSeeLastSeenOf', () => {
    it('returns true when the requester is the target (self)', async () => {
      const result = await service.canSeeLastSeenOf('user-1', 'user-1');
      expect(result).toBe(true);
      expect(mockPrisma.user.findUnique).not.toHaveBeenCalled();
    });

    it('returns false when the requester hides from everyone (reciprocity)', async () => {
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({ lastSeenVisibility: 'nobody' })  // requester
        .mockResolvedValueOnce({ lastSeenVisibility: 'everyone' }); // target
      const result = await service.canSeeLastSeenOf('user-1', 'user-2');
      expect(result).toBe(false);
    });

    it('returns false when the target hides from everyone', async () => {
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({ lastSeenVisibility: 'everyone' })  // requester
        .mockResolvedValueOnce({ lastSeenVisibility: 'nobody' });    // target
      const result = await service.canSeeLastSeenOf('user-1', 'user-2');
      expect(result).toBe(false);
    });

    it('returns true when both visibility settings are everyone', async () => {
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({ lastSeenVisibility: 'everyone' })
        .mockResolvedValueOnce({ lastSeenVisibility: 'everyone' });
      const result = await service.canSeeLastSeenOf('user-1', 'user-2');
      expect(result).toBe(true);
    });

    it('returns true when target is contacts and the requester shares a family', async () => {
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({ lastSeenVisibility: 'everyone' })
        .mockResolvedValueOnce({ lastSeenVisibility: 'contacts' });
      mockPrisma.familyMember.findMany.mockResolvedValue([{ familyId: 'fam-1' }]);
      mockPrisma.familyMember.findFirst.mockResolvedValue({ id: 'fm-1' });
      const result = await service.canSeeLastSeenOf('user-1', 'user-2');
      expect(result).toBe(true);
    });

    it('returns false when target is contacts and the requester shares NO family', async () => {
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({ lastSeenVisibility: 'everyone' })
        .mockResolvedValueOnce({ lastSeenVisibility: 'contacts' });
      mockPrisma.familyMember.findMany.mockResolvedValue([{ familyId: 'fam-1' }]);
      mockPrisma.familyMember.findFirst.mockResolvedValue(null);
      const result = await service.canSeeLastSeenOf('user-1', 'user-2');
      expect(result).toBe(false);
    });

    it('returns true when the target row is missing (default open)', async () => {
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({ lastSeenVisibility: 'everyone' })  // requester
        .mockResolvedValueOnce(null);                                // target missing
      const result = await service.canSeeLastSeenOf('user-1', 'user-2');
      expect(result).toBe(true);
    });
  });

  describe('hasReadReceiptsEnabled', () => {
    it('returns the user setting when found', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({ readReceiptsEnabled: false });
      const result = await service.hasReadReceiptsEnabled('user-1');
      expect(result).toBe(false);
    });

    it('returns true (default) when the user row is missing', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);
      const result = await service.hasReadReceiptsEnabled('user-1');
      expect(result).toBe(true);
    });
  });
});
