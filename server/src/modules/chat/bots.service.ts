// server/src/modules/chat/bots.service.ts
//
// DAXELO KINREL — Tier 6 Features 6.6 + 6.7: Bots + Inline bots + Mini-apps — Service
//
// Wraps the bot catalog + bot-message persistence + inline-query dispatch.
// The actual webhook dispatch to the bot's webhookUrl is implemented as a
// fire-and-forget fetch() call — failures are logged but don't block the
// user's request (the bot will time out from the user's perspective if
// the webhook is unreachable, which matches Telegram's behavior).

import { Injectable, BadRequestException, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class BotsService {
  private readonly logger = new Logger(BotsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /// List all bots in the catalog (with installed flag for the caller).
  async listCatalog(userId: string) {
    const [bots, installs] = await Promise.all([
      this.prisma.bot.findMany({
        orderBy: [{ isVerified: 'desc' }, { name: 'asc' }],
      }),
      this.prisma.userBotInstall.findMany({
        where: { userId },
        select: { botId: true },
      }),
    ]);
    const installedSet = new Set(installs.map((i) => i.botId));
    return bots.map((b) => ({ ...b, installed: installedSet.has(b.id) }));
  }

  /// List only the caller's installed bots.
  async listInstalled(userId: string) {
    const installs = await this.prisma.userBotInstall.findMany({
      where: { userId },
      include: { bot: true },
      orderBy: { installedAt: 'desc' },
    });
    return installs.map((i) => i.bot);
  }

  /// Get a bot by @handle (case-insensitive, with or without the leading @).
  async getBotByHandle(handle: string) {
    const normalized = handle.toLowerCase().replace(/^@/, '');
    const bot = await this.prisma.bot.findFirst({
      where: { handle: { contains: normalized, mode: 'insensitive' } },
    });
    if (!bot) throw new NotFoundException('Bot not found');
    return bot;
  }

  /// Create a new bot (caller becomes the owner).
  async createBot(
    userId: string,
    params: {
      name: string;
      handle: string;
      webhookUrl?: string | null;
      isInline?: boolean;
      description?: string | null;
      avatarUrl?: string | null;
    },
  ) {
    const handle = params.handle.toLowerCase().replace(/^@/, '');
    if (handle.length < 4 || handle.length > 32) {
      throw new BadRequestException('Handle must be 4-32 characters');
    }
    if (!/^[a-z][a-z0-9_]*$/.test(handle)) {
      throw new BadRequestException('Handle must start with a letter + use only letters, digits, underscore');
    }
    if (!params.name?.trim()) {
      throw new BadRequestException('Name is required');
    }

    const id = `bot_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    try {
      return await this.prisma.bot.create({
        data: {
          id,
          name: params.name.trim(),
          handle,
          ownerUserId: userId,
          webhookUrl: params.webhookUrl ?? null,
          isInline: params.isInline ?? false,
          description: params.description ?? null,
          avatarUrl: params.avatarUrl ?? null,
        },
      });
    } catch (err: any) {
      if (err?.code === 'P2002') {
        throw new BadRequestException('A bot with this handle already exists');
      }
      throw err;
    }
  }

  /// Install / uninstall a bot.
  async installBot(userId: string, botId: string) {
    const bot = await this.prisma.bot.findUnique({ where: { id: botId } });
    if (!bot) throw new NotFoundException('Bot not found');
    const id = `ubi_${botId}_${userId}`;
    await this.prisma.userBotInstall.upsert({
      where: { id },
      create: { id, userId, botId },
      update: {},
    });
    return { success: true, botId };
  }

  async uninstallBot(userId: string, botId: string) {
    await this.prisma.userBotInstall.deleteMany({ where: { userId, botId } });
    return { success: true, botId };
  }

  /// Send a message to a bot (DM with a bot). The bot's response comes
  /// asynchronously via the webhook → BotMessage row with direction='outgoing'
  /// → Realtime publication → the user's client renders it.
  async sendBotMessage(
    userId: string,
    params: { botId: string; content: string; payload?: any },
  ) {
    const bot = await this.prisma.bot.findUnique({ where: { id: params.botId } });
    if (!bot) throw new NotFoundException('Bot not found');
    if (!params.content?.trim()) {
      throw new BadRequestException('content is required');
    }

    // Persist the incoming message.
    const id = `bm_in_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const message = await this.prisma.botMessage.create({
      data: {
        id,
        botId: bot.id,
        userId,
        direction: 'incoming',
        content: params.content,
        payload: params.payload ?? [],
      },
    });

    // Fire-and-forget webhook dispatch.
    if (bot.webhookUrl) {
      this.dispatchToWebhook(bot.webhookUrl, {
        botId: bot.id,
        userId,
        messageId: id,
        content: params.content,
        payload: params.payload ?? null,
      }).catch((err) => {
        this.logger.warn(`Webhook dispatch to ${bot.webhookUrl} failed: ${err?.message}`);
      });
    }

    return message;
  }

  /// List the bot-message history between the caller and a bot.
  async listBotMessages(userId: string, botId: string, limit: number = 50, before?: Date) {
    const bot = await this.prisma.bot.findUnique({ where: { id: botId } });
    if (!bot) throw new NotFoundException('Bot not found');
    return this.prisma.botMessage.findMany({
      where: {
        botId,
        userId,
        ...(before ? { createdAt: { lt: before } } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 200),
    });
  }

  /// Inline query — the user types `@gif cat` in any chat. We dispatch
  /// to the bot's webhook with the query + return whatever the bot
  /// responds with synchronously (capped at 5s — matches Telegram's
  /// inline-query timeout).
  async inlineQuery(
    userId: string,
    params: { botHandle: string; query: string; familyId?: string | null; receiverId?: string | null },
  ): Promise<{ results: any[]; cached: boolean }> {
    const bot = await this.getBotByHandle(params.botHandle);
    if (!bot.isInline) {
      throw new BadRequestException('This bot does not support inline queries');
    }
    if (!bot.webhookUrl) {
      return { results: [], cached: false };
    }

    // Dispatch + wait up to 5s for the response.
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      const response = await fetch(bot.webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: 'inline_query',
          botId: bot.id,
          userId,
          query: params.query,
          familyId: params.familyId ?? null,
          receiverId: params.receiverId ?? null,
        }),
        signal: controller.signal,
      });
      clearTimeout(timeout);
      if (!response.ok) {
        this.logger.warn(`Inline-query webhook returned ${response.status}`);
        return { results: [], cached: false };
      }
      const data = await response.json() as any;
      return { results: data.results ?? [], cached: false };
    } catch (err: any) {
      this.logger.warn(`Inline-query dispatch failed: ${err?.message}`);
      return { results: [], cached: false };
    }
  }

  /// Internal: fire-and-forget webhook dispatch.
  private async dispatchToWebhook(url: string, payload: any): Promise<void> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000); // 10s timeout
    try {
      await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'message', ...payload }),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }
  }
}
