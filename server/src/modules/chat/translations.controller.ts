// server/src/modules/chat/translations.controller.ts
//
// DAXELO KINREL — Tier 6 Feature 6.4: Translation — Controller

import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { TranslationsService } from './translations.service';

@Controller('chat/translate')
@UseGuards(JwtAuthGuard)
export class TranslationsController {
  constructor(private readonly service: TranslationsService) {}

  /// POST /chat/translate
  /// Body: { messageId, targetLang, isDirectMessage? }
  /// Returns the translation (cached or freshly fetched from the provider).
  @Post()
  async translate(
    @CurrentUser('id') userId: string,
    @Body() body: { messageId: string; targetLang: string; isDirectMessage?: boolean },
  ) {
    return this.service.translateMessage(userId, body);
  }

  /// GET /chat/translate/:messageId?targetLang=en&isDirectMessage=false
  /// Returns the cached translation only (no provider call).
  @Get(':messageId')
  async getCached(
    @Param('messageId') messageId: string,
    @Query('targetLang') targetLang: string,
  ) {
    return (await this.service.getCachedTranslation(messageId, targetLang ?? 'en')) ?? { cached: false };
  }
}
