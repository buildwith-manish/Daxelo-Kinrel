// server/src/modules/chat/drafts.controller.ts
//
// DAXELO KINREL — Tier 1 Feature 1.3: Auto-saved Drafts — Controller

import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { DraftsService } from './drafts.service';

@Controller('chat/drafts')
@UseGuards(JwtAuthGuard)
export class DraftsController {
  constructor(private readonly service: DraftsService) {}

  /**
   * POST /chat/drafts
   * Upsert (or clear, when draftText is empty) a draft.
   * Body: { familyId?, receiverId?, draftText, replyToId? }
   */
  @Post()
  async save(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      familyId?: string | null;
      receiverId?: string | null;
      draftText: string;
      replyToId?: string | null;
    },
  ) {
    return this.service.saveDraft(userId, body);
  }

  /**
   * GET /chat/drafts?familyId=... OR /chat/drafts?receiverId=...
   * Returns the caller's draft for a specific chat.
   */
  @Get()
  async get(
    @CurrentUser('id') userId: string,
    @Query('familyId') familyId?: string,
    @Query('receiverId') receiverId?: string,
  ) {
    return this.service.getDraft(userId, {
      familyId: familyId ?? null,
      receiverId: receiverId ?? null,
    });
  }

  /**
   * GET /chat/drafts/list
   * Returns all drafts for the caller (used on app startup).
   */
  @Get('list')
  async list(@CurrentUser('id') userId: string) {
    return this.service.listDrafts(userId);
  }
}
