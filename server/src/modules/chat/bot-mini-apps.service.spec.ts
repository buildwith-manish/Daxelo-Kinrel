// server/src/modules/chat/bot-mini-apps.service.spec.ts
//
// Unit tests for BotMiniAppsService — Tier 6 Feature 6.7.

import { Test, TestingModule } from '@nestjs/testing';
import { BotMiniAppsService } from './bot-mini-apps.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { BadRequestException, NotFoundException, ForbiddenException } from '@nestjs/common';

describe('BotMiniAppsService', () => {
  let service: BotMiniAppsService;

  const mockPrisma = {
    bot: { findUnique: jest.fn() },
    familyMember: { findUnique: jest.fn() },
    botMiniAppSession: { create: jest.fn() },
  };
  const mockConfig = { get: jest.fn() };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        BotMiniAppsService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();
    service = module.get<BotMiniAppsService>(BotMiniAppsService);
    jest.clearAllMocks();
  });

  describe('createSession', () => {
    it('returns no_secret_configured when BOT_MINIAPP_SECRET is missing', async () => {
      mockConfig.get.mockReturnValue(undefined);
      const result = await service.createSession('user-1', { botId: 'bot_1', familyId: 'fam-1' });
      expect(result).toEqual(expect.objectContaining({ error: 'no_secret_configured' }));
    });

    it('throws BadRequestException when both familyId and receiverId are set', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      await expect(
        service.createSession('user-1', { botId: 'bot_1', familyId: 'fam-1', receiverId: 'user-2' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when neither familyId nor receiverId is set', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      await expect(
        service.createSession('user-1', { botId: 'bot_1' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws NotFoundException when the bot does not exist', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      mockPrisma.bot.findUnique.mockResolvedValue(null);
      await expect(
        service.createSession('user-1', { botId: 'bot_x', familyId: 'fam-1' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not a family member', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      mockPrisma.bot.findUnique.mockResolvedValue({ id: 'bot_1' });
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);
      await expect(
        service.createSession('user-1', { botId: 'bot_1', familyId: 'fam-1' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('creates a session + returns the signed initData token', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      mockPrisma.bot.findUnique.mockResolvedValue({ id: 'bot_1' });
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.botMiniAppSession.create.mockResolvedValue({});
      const result = await service.createSession('user-1', { botId: 'bot_1', familyId: 'fam-1' });
      expect(result).toEqual(expect.objectContaining({
        botId: 'bot_1',
        initData: expect.any(String),
        expiresAt: expect.any(String),
      }));
      // initData format: <payloadB64>.<signature>
      expect(result.initData).toMatch(/^[A-Za-z0-9_-]+\.[a-f0-9]+$/);
    });
  });

  describe('verifyToken', () => {
    it('throws BadRequestException when the secret is not configured', async () => {
      mockConfig.get.mockReturnValue(undefined);
      await expect(
        service.verifyToken('abc.def'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException for a malformed token', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      await expect(
        service.verifyToken('no-dot-here'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when the signature does not match', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      await expect(
        service.verifyToken('payloadB64.wrongsig'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('round-trips: a token created by createSession is verifiable', async () => {
      mockConfig.get.mockReturnValue('test-secret');
      mockPrisma.bot.findUnique.mockResolvedValue({ id: 'bot_1' });
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.botMiniAppSession.create.mockResolvedValue({});
      // Create a session with a 1h expiry (future).
      const created = await service.createSession('user-1', { botId: 'bot_1', familyId: 'fam-1' }) as any;
      // Verify the token round-trips.
      const verified = await service.verifyToken(created.initData);
      expect(verified).toEqual(expect.objectContaining({
        botId: 'bot_1',
        userId: 'user-1',
        familyId: 'fam-1',
      }));
    });
  });
});
