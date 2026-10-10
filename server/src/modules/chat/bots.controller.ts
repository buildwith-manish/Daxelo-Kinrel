// server/src/modules/chat/bots.controller.ts
//
// DAXELO KINREL — Tier 6 Features 6.6 + 6.7: Bots — Controller

import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { BotsService } from './bots.service';

@Controller('chat/bots')
@UseGuards(JwtAuthGuard)
export class BotsController {
  constructor(private readonly service: BotsService) {}

  /// GET /chat/bots/catalog
  /// List all bots in the catalog (with installed flag for the caller).
  @Get('catalog')
  async catalog(@CurrentUser('id') userId: string) {
    return this.service.listCatalog(userId);
  }

  /// GET /chat/bots/installed
  /// List only the caller's installed bots.
  @Get('installed')
  async installed(@CurrentUser('id') userId: string) {
    return this.service.listInstalled(userId);
  }

  /// GET /chat/bots/by-handle/:handle
  /// Fetch a bot by its @handle.
  @Get('by-handle/:handle')
  async byHandle(@Param('handle') handle: string) {
    return this.service.getBotByHandle(handle);
  }

  /// POST /chat/bots
  /// Register a new bot (caller becomes the owner).
  @Post()
  async create(
    @CurrentUser('id') userId: string,
    @Body() body: {
      name: string;
      handle: string;
      webhookUrl?: string | null;
      isInline?: boolean;
      description?: string | null;
      avatarUrl?: string | null;
    },
  ) {
    return this.service.createBot(userId, body);
  }

  /// POST /chat/bots/:botId/install
  @Post(':botId/install')
  async install(@CurrentUser('id') userId: string, @Param('botId') botId: string) {
    return this.service.installBot(userId, botId);
  }

  /// DELETE /chat/bots/:botId/install
  @Delete(':botId/install')
  async uninstall(@CurrentUser('id') userId: string, @Param('botId') botId: string) {
    return this.service.uninstallBot(userId, botId);
  }

  /// POST /chat/bots/:botId/messages
  /// Send a message to a bot. The bot's response comes asynchronously
  /// via the webhook → BotMessage with direction='outgoing' → Realtime.
  @Post(':botId/messages')
  async sendMessage(
    @CurrentUser('id') userId: string,
    @Param('botId') botId: string,
    @Body() body: { content: string; payload?: any },
  ) {
    return this.service.sendBotMessage(userId, { botId, ...body });
  }

  /// GET /chat/bots/:botId/messages?limit=&before=
  /// List bot-message history.
  @Get(':botId/messages')
  async listMessages(
    @CurrentUser('id') userId: string,
    @Param('botId') botId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    return this.service.listBotMessages(
      userId,
      botId,
      limit ? parseInt(limit, 10) : 50,
      before ? new Date(before) : undefined,
    );
  }

  /// POST /chat/bots/inline-query
  /// Body: { botHandle, query, familyId?, receiverId? }
  /// Inline query — returns results from the bot's webhook (capped at 5s).
  @Post('inline-query')
  async inlineQuery(
    @CurrentUser('id') userId: string,
    @Body() body: { botHandle: string; query: string; familyId?: string | null; receiverId?: string | null },
  ) {
    return this.service.inlineQuery(userId, body);
  }
}
