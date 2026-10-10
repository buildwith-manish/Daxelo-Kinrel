// server/src/modules/chat/sticker-packs.service.spec.ts
//
// Unit tests for StickerPacksService — Tier 4 Features 4.4 + 4.5.

import { Test, TestingModule } from '@nestjs/testing';
import { StickerPacksService } from './sticker-packs.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';

describe('StickerPacksService', () => {
  let service: StickerPacksService;

  const mockPrisma = {
    userStickerPack: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    userStickerItem: {
      findUnique: jest.fn(),
      create: jest.fn(),
      delete: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StickerPacksService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<StickerPacksService>(StickerPacksService);
    jest.clearAllMocks();
  });

  describe('listMyPacks', () => {
    it('returns the caller\'s packs with items included', async () => {
      const packs = [
        { id: 'usp_default_u1', ownerId: 'user-1', name: 'My Stickers', isDefault: true, items: [] },
        { id: 'usp_1', ownerId: 'user-1', name: 'Diwali', isDefault: false, items: [{ id: 'usi_1' }] },
      ];
      mockPrisma.userStickerPack.findMany.mockResolvedValue(packs);
      const result = await service.listMyPacks('user-1');
      expect(result).toBe(packs);
      expect(mockPrisma.userStickerPack.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { ownerId: 'user-1' },
          orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
        }),
      );
    });
  });

  describe('createPack — happy path', () => {
    it('creates a non-default pack', async () => {
      mockPrisma.userStickerPack.create.mockResolvedValue({ id: 'usp_new' });
      const result = await service.createPack('user-1', { name: 'Holi' });
      expect(result).toEqual({ id: 'usp_new' });
      expect(mockPrisma.userStickerPack.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            ownerId: 'user-1',
            name: 'Holi',
            isDefault: false,
          }),
        }),
      );
    });

    it('throws BadRequestException when the name is empty', async () => {
      await expect(
        service.createPack('user-1', { name: '   ' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when the name exceeds 50 chars', async () => {
      await expect(
        service.createPack('user-1', { name: 'X'.repeat(60) }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('updatePack', () => {
    it('throws NotFoundException when the pack does not exist', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue(null);
      await expect(
        service.updatePack('user-1', 'usp_x', { name: 'New' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not the owner', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue({
        id: 'usp_x', ownerId: 'user-OTHER', isDefault: false,
      });
      await expect(
        service.updatePack('user-1', 'usp_x', { name: 'New' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws BadRequestException when renaming the default pack', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue({
        id: 'usp_default_u1', ownerId: 'user-1', isDefault: true,
      });
      await expect(
        service.updatePack('user-1', 'usp_default_u1', { name: 'New' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('deletePack', () => {
    it('throws BadRequestException when deleting the default pack', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue({
        id: 'usp_default_u1', ownerId: 'user-1', isDefault: true,
      });
      await expect(
        service.deletePack('user-1', 'usp_default_u1'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('deletes a non-default pack owned by the caller', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue({
        id: 'usp_x', ownerId: 'user-1', isDefault: false,
      });
      mockPrisma.userStickerPack.delete.mockResolvedValue({});
      const result = await service.deletePack('user-1', 'usp_x');
      expect(result).toEqual({ success: true, deleted: 'usp_x' });
    });
  });

  describe('addSticker — validation', () => {
    it('throws NotFoundException when the pack does not exist', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue(null);
      await expect(
        service.addSticker('user-1', 'usp_x', { stickerName: 'X', imageUrl: 'http://x' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not the owner', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue({ ownerId: 'user-OTHER' });
      await expect(
        service.addSticker('user-1', 'usp_x', { stickerName: 'X', imageUrl: 'http://x' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws BadRequestException when isAnimated=true but lottieUrl is missing', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue({ ownerId: 'user-1' });
      await expect(
        service.addSticker('user-1', 'usp_1', {
          stickerName: 'X', imageUrl: 'http://x', isAnimated: true,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('creates the sticker when owned by the caller', async () => {
      mockPrisma.userStickerPack.findUnique.mockResolvedValue({ ownerId: 'user-1' });
      const created = { id: 'usi_new', packId: 'usp_1' };
      mockPrisma.userStickerItem.create.mockResolvedValue(created);
      const result = await service.addSticker('user-1', 'usp_1', {
        stickerName: 'Diya', imageUrl: 'http://x.png', emoji: '🪔',
      });
      expect(result).toBe(created);
    });
  });

  describe('removeSticker', () => {
    it('throws NotFoundException when the sticker does not exist', async () => {
      mockPrisma.userStickerItem.findUnique.mockResolvedValue(null);
      await expect(
        service.removeSticker('user-1', 'usi_x'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller does not own the parent pack', async () => {
      mockPrisma.userStickerItem.findUnique.mockResolvedValue({
        id: 'usi_x', pack: { ownerId: 'user-OTHER' },
      });
      await expect(
        service.removeSticker('user-1', 'usi_x'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('ensureDefaultPack', () => {
    it('returns the existing default pack when one already exists', async () => {
      const existing = { id: 'usp_default_u1', isDefault: true };
      mockPrisma.userStickerPack.findFirst.mockResolvedValue(existing);
      const result = await service.ensureDefaultPack('user-1');
      expect(result).toBe(existing);
      expect(mockPrisma.userStickerPack.create).not.toHaveBeenCalled();
    });

    it('creates the default pack when none exists', async () => {
      mockPrisma.userStickerPack.findFirst.mockResolvedValue(null);
      const created = { id: 'usp_default_u1', name: 'My Stickers', isDefault: true };
      mockPrisma.userStickerPack.create.mockResolvedValue(created);
      const result = await service.ensureDefaultPack('user-1');
      expect(result).toBe(created);
    });
  });
});
