// server/src/modules/chat/bots.service.spec.ts
//
// Unit tests for BotsService — Tier 6 Features 6.6 + 6.7.

import { Test, TestingModule } from '@nestjs/testing';
import { BotsService } from './bots.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { BadRequestException, NotFoundException } from '@nestjs/common';

describe('BotsService', () => {
  let service: BotsService;

  const mockPrisma = {
    bot: { findMany: jest.fn(), findFirst: jest.fn(), findUnique: jest.fn(), create: jest.fn() },
    userBotInstall: { findMany: jest.fn(), upsert: jest.fn(), deleteMany: jest.fn() },
    botMessage: { create: jest.fn(), findMany: jest.fn() },
  };
  const mockConfig = { get: jest.fn() };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        BotsService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();
    service = module.get<BotsService>(BotsService);
    jest.clearAllMocks();
  });

  describe('createBot — validation', () => {
    it('throws BadRequestException when the handle is too short', async () => {
      await expect(
        service.createBot('user-1', { name: 'Gif', handle: 'ab' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when the handle has invalid chars', async () => {
      await expect(
        service.createBot('user-1', { name: 'Gif', handle: 'invalid!chars_here' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when the handle starts with a digit', async () => {
      await expect(
        service.createBot('user-1', { name: 'Gif', handle: '1gif_bot' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when the name is empty', async () => {
      await expect(
        service.createBot('user-1', { name: '   ', handle: 'valid_handle' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('creates the bot when validation passes', async () => {
      const created = { id: 'bot_1', name: 'Gif', handle: 'gif_bot' };
      mockPrisma.bot.create.mockResolvedValue(created);
      const result = await service.createBot('user-1', {
        name: 'Gif', handle: '@Gif_Bot', isInline: true,
      });
      expect(result).toBe(created);
      expect(mockPrisma.bot.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            ownerUserId: 'user-1',
            handle: 'gif_bot',
            isInline: true,
          }),
        }),
      );
    });

    it('rethrows a P2002 unique violation as a BadRequestException', async () => {
      mockPrisma.bot.create.mockRejectedValue({ code: 'P2002' });
      await expect(
        service.createBot('user-1', { name: 'Gif', handle: 'taken_handle' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('getBotByHandle', () => {
    it('throws NotFoundException when no bot matches', async () => {
      mockPrisma.bot.findFirst.mockResolvedValue(null);
      await expect(
        service.getBotByHandle('@missing'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('returns the bot when found', async () => {
      const bot = { id: 'bot_1', handle: 'gif_bot' };
      mockPrisma.bot.findFirst.mockResolvedValue(bot);
      const result = await service.getBotByHandle('@Gif_Bot');
      expect(result).toBe(bot);
    });
  });

  describe('installBot', () => {
    it('throws NotFoundException when the bot does not exist', async () => {
      mockPrisma.bot.findUnique.mockResolvedValue(null);
      await expect(
        service.installBot('user-1', 'bot_missing'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('upserts the install row (idempotent)', async () => {
      mockPrisma.bot.findUnique.mockResolvedValue({ id: 'bot_1' });
      mockPrisma.userBotInstall.upsert.mockResolvedValue({});
      const result = await service.installBot('user-1', 'bot_1');
      expect(result).toEqual({ success: true, botId: 'bot_1' });
      expect(mockPrisma.userBotInstall.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'ubi_bot_1_user-1' },
        }),
      );
    });
  });

  describe('sendBotMessage — validation', () => {
    it('throws NotFoundException when the bot does not exist', async () => {
      mockPrisma.bot.findUnique.mockResolvedValue(null);
      await expect(
        service.sendBotMessage('user-1', { botId: 'bot_x', content: 'hi' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws BadRequestException when the content is empty', async () => {
      mockPrisma.bot.findUnique.mockResolvedValue({ id: 'bot_1', webhookUrl: null });
      await expect(
        service.sendBotMessage('user-1', { botId: 'bot_1', content: '   ' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('persists the incoming message', async () => {
      mockPrisma.bot.findUnique.mockResolvedValue({ id: 'bot_1', webhookUrl: null });
      const created = { id: 'bm_in_1', direction: 'incoming' };
      mockPrisma.botMessage.create.mockResolvedValue(created);
      const result = await service.sendBotMessage('user-1', { botId: 'bot_1', content: 'hi' });
      expect(result).toBe(created);
    });
  });

  describe('inlineQuery', () => {
    it('throws BadRequestException when the bot is not inline', async () => {
      mockPrisma.bot.findFirst.mockResolvedValue({ id: 'bot_1', isInline: false, webhookUrl: 'http://x' });
      await expect(
        service.inlineQuery('user-1', { botHandle: 'gif_bot', query: 'cat' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('returns empty results when the bot has no webhook', async () => {
      mockPrisma.bot.findFirst.mockResolvedValue({ id: 'bot_1', isInline: true, webhookUrl: null });
      const result = await service.inlineQuery('user-1', { botHandle: 'gif_bot', query: 'cat' });
      expect(result).toEqual({ results: [], cached: false });
    });
  });
});
