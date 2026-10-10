// server/src/modules/chat/privacy.controller.ts
//
// DAXELO KINREL — Tier 3 Feature 3.5: Privacy toggles — Controller

import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PrivacyService } from './privacy.service';

@Controller('chat/privacy')
@UseGuards(JwtAuthGuard)
export class PrivacyController {
  constructor(private readonly service: PrivacyService) {}

  @Get()
  async getMySettings(@CurrentUser('id') userId: string) {
    return this.service.getMySettings(userId);
  }

  @Post()
  async updateMySettings(
    @CurrentUser('id') userId: string,
    @Body() body: { lastSeenVisibility?: string | null; readReceiptsEnabled?: boolean | null },
  ) {
    return this.service.updateMySettings(userId, body);
  }
}
