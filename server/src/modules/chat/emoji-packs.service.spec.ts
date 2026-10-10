// server/src/modules/chat/emoji-packs.service.spec.ts
//
// Unit tests for EmojiPacksService — Tier 4 Feature 4.6.

import { Test, TestingModule } from '@nestjs/testing';
import { EmojiPacksService } from './emoji-packs.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, NotFoundException } from '@nestjs/common';

describe('EmojiPacksService', () => {
  let service: EmojiPacksService;

  const mockPrisma = {
    emojiPack: { findMany: jest.fn(), findUnique: jest.fn(), create: jest.fn() },
    emojiPackItem: { findMany: jest.fn(), create: jest.fn() },
    userEmojiPackInstall: {
      findMany: jest.fn(),
      upsert: jest.fn(),
      deleteMany: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        EmojiPacksService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<EmojiPacksService>(EmojiPacksService);
    jest.clearAllMocks();
  });

  describe('listCatalog', () => {
    it('returns the global catalog with installed flags', async () => {
      mockPrisma.emojiPack.findMany.mockResolvedValue([
        { id: 'ep_1', name: 'Party', items: [] },
        { id: 'ep_2', name: 'Food', items: [] },
      ]);
      mockPrisma.userEmojiPackInstall.findMany.mockResolvedValue([{ packId: 'ep_1' }]);
      const result = await service.listCatalog('user-1');
      expect(result).toEqual([
        { id: 'ep_1', name: 'Party', items: [], installed: true },
        { id: 'ep_2', name: 'Food', items: [], installed: false },
      ]);
    });
  });

  describe('listInstalled', () => {
    it('returns only the caller\'s installed packs', async () => {
      const installs = [
        { pack: { id: 'ep_1', name: 'Party', items: [] } },
      ];
      mockPrisma.userEmojiPackInstall.findMany.mockResolvedValue(installs);
      const result = await service.listInstalled('user-1');
      expect(result).toEqual([{ id: 'ep_1', name: 'Party', items: [] }]);
    });
  });

  describe('install', () => {
    it('throws NotFoundException when the pack does not exist', async () => {
      mockPrisma.emojiPack.findUnique.mockResolvedValue(null);
      await expect(
        service.install('user-1', 'ep_missing'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('upserts the install row (idempotent)', async () => {
      mockPrisma.emojiPack.findUnique.mockResolvedValue({ id: 'ep_1' });
      mockPrisma.userEmojiPackInstall.upsert.mockResolvedValue({});
      const result = await service.install('user-1', 'ep_1');
      expect(result).toEqual({ success: true, packId: 'ep_1' });
      expect(mockPrisma.userEmojiPackInstall.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'uepi_ep_1_user-1' },
          create: expect.objectContaining({ userId: 'user-1', packId: 'ep_1' }),
        }),
      );
    });
  });

  describe('uninstall', () => {
    it('deletes the install row', async () => {
      mockPrisma.userEmojiPackInstall.deleteMany.mockResolvedValue({ count: 1 });
      const result = await service.uninstall('user-1', 'ep_1');
      expect(result).toEqual({ success: true, packId: 'ep_1' });
    });
  });

  describe('searchItems', () => {
    it('returns empty when the caller has no installed packs', async () => {
      mockPrisma.userEmojiPackInstall.findMany.mockResolvedValue([]);
      const result = await service.searchItems('user-1', 'party');
      expect(result).toEqual([]);
    });

    it('returns empty when the keyword is blank', async () => {
      const result = await service.searchItems('user-1', '   ');
      expect(result).toEqual([]);
      expect(mockPrisma.userEmojiPackInstall.findMany).not.toHaveBeenCalled();
    });

    it('queries EmojiPackItem with the keyword filter', async () => {
      mockPrisma.userEmojiPackInstall.findMany.mockResolvedValue([{ packId: 'ep_1' }]);
      const items = [{ id: 'epi_1', emojiName: 'party_parrot' }];
      mockPrisma.emojiPackItem.findMany.mockResolvedValue(items);
      const result = await service.searchItems('user-1', 'party');
      expect(result).toBe(items);
      expect(mockPrisma.emojiPackItem.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            packId: { in: ['ep_1'] },
            OR: expect.any(Array),
          }),
        }),
      );
    });
  });

  describe('createPack — validation', () => {
    it('throws BadRequestException when the name is empty', async () => {
      await expect(
        service.createPack('user-1', { name: '   ' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('creates the pack with the given fields', async () => {
      const created = { id: 'ep_new', name: 'Animals' };
      mockPrisma.emojiPack.create.mockResolvedValue(created);
      const result = await service.createPack('user-1', {
        name: 'Animals', isOfficial: false, publisherName: 'Kinrel',
      });
      expect(result).toBe(created);
    });
  });

  describe('addEmojiToPack — validation', () => {
    it('throws NotFoundException when the pack does not exist', async () => {
      mockPrisma.emojiPack.findUnique.mockResolvedValue(null);
      await expect(
        service.addEmojiToPack('user-1', 'ep_x', { emojiName: 'X', imageUrl: 'http://x' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws BadRequestException when isAnimated pack lacks lottieUrl', async () => {
      mockPrisma.emojiPack.findUnique.mockResolvedValue({ id: 'ep_1', isAnimated: true });
      await expect(
        service.addEmojiToPack('user-1', 'ep_1', { emojiName: 'X', imageUrl: 'http://x' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('creates the emoji when validation passes', async () => {
      mockPrisma.emojiPack.findUnique.mockResolvedValue({ id: 'ep_1', isAnimated: false });
      const created = { id: 'epi_new', emojiName: 'party' };
      mockPrisma.emojiPackItem.create.mockResolvedValue(created);
      const result = await service.addEmojiToPack('user-1', 'ep_1', {
        emojiName: 'party', imageUrl: 'http://x.png', keywords: ['celebrate'],
      });
      expect(result).toBe(created);
    });
  });
});
