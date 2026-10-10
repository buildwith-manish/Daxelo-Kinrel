// server/src/modules/chat/bot-mini-apps.controller.ts
//
// DAXELO KINREL — Tier 6 Feature 6.7: Mini-apps — Controller

import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { BotMiniAppsService } from './bot-mini-apps.service';

@Controller('chat/bot-mini-apps')
@UseGuards(JwtAuthGuard)
export class BotMiniAppsController {
  constructor(private readonly service: BotMiniAppsService) {}

  /// POST /chat/bot-mini-apps/sessions
  /// Body: { botId, familyId?, receiverId? }
  /// Creates a mini-app session + returns the signed initData token.
  /// Pass exactly one of familyId or receiverId (the chat context the
  /// mini-app is launched from).
  @Post('sessions')
  async createSession(
    @CurrentUser('id') userId: string,
    @Body() body: { botId: string; familyId?: string | null; receiverId?: string | null },
  ) {
    return this.service.createSession(userId, body);
  }

  /// GET /chat/bot-mini-apps/verify?initData=<token>
  /// Verifies an initData token. Returns the decoded payload when valid.
  /// Useful for testing + for follow-up server-side actions gated by the
  /// token (e.g. "only the user who launched the poll maker can edit it").
  @Get('verify')
  async verify(@Query('initData') initData: string) {
    if (!initData) {
      return { valid: false, error: 'initData query param is required' };
    }
    try {
      const payload = await this.service.verifyToken(initData);
      return { valid: true, ...payload };
    } catch (err: any) {
      return { valid: false, error: err?.message ?? 'verification failed' };
    }
  }
}
