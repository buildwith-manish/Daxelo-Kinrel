// server/src/modules/chat/username-discovery.controller.ts
//
// DAXELO KINREL — Tier 5 Feature 5.2: Public username discovery — Controller

import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { UsernameDiscoveryService } from './username-discovery.service';

@Controller('chat/username-discovery')
@UseGuards(JwtAuthGuard)
export class UsernameDiscoveryController {
  constructor(private readonly service: UsernameDiscoveryService) {}

  /// POST /chat/username-discovery/account-mode
  /// Body: { isUsernameOnly: boolean, showOnUsernameSearch?: boolean | null }
  /// Flip the caller's account to username-only (or back to email-based).
  @Post('account-mode')
  async setAccountMode(
    @CurrentUser('id') userId: string,
    @Body() body: { isUsernameOnly: boolean; showOnUsernameSearch?: boolean | null },
  ) {
    return this.service.setAccountMode(userId, body);
  }

  /// GET /chat/username-discovery/search?q=manish&limit=20
  /// Search the public user catalog by username prefix.
  @Get('search')
  async search(
    @CurrentUser('id') userId: string,
    @Query('q') q: string,
    @Query('limit') limit?: string,
  ) {
    return this.service.searchByUsername(userId, q ?? '', limit ? parseInt(limit, 10) : 20);
  }
}
