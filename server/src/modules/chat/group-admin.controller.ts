// server/src/modules/chat/group-admin.controller.ts
//
// DAXELO KINREL — Tier 2: Group Admin Controller
//
// REST endpoints for the admin-only Tier 2 features. All paths are scoped
// under /families/:familyId so they reuse the existing JWT auth + family
// scoping convention.

import {
  Body, Controller, Delete, Get, Param, Post, Query,
  UseGuards, BadRequestException, NotFoundException,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { GroupAdminService } from './group-admin.service';

@Controller('families/:familyId/admin')
@UseGuards(JwtAuthGuard)
export class GroupAdminController {
  constructor(private readonly service: GroupAdminService) {}

  // ── 2.11: Group description ────────────────────────────────────────────

  @Post('description')
  async setDescription(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { description?: string | null },
  ) {
    return this.service.setGroupDescription(familyId, userId, body.description ?? null);
  }

  // ── 2.6: Slow mode ─────────────────────────────────────────────────────

  @Post('slow-mode')
  async setSlowMode(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { seconds: number },
  ) {
    return this.service.setSlowMode(familyId, userId, body.seconds);
  }

  // ── 2.8: Audit log ─────────────────────────────────────────────────────

  @Get('audit-log')
  async getAuditLog(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    return this.service.getAuditLog(
      familyId,
      userId,
      limit ? Math.min(parseInt(limit, 10), 200) : 50,
      before,
    );
  }

  // ── 2.9: Group invite links ───────────────────────────────────────────

  @Post('invite-links')
  async createInviteLink(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: {
      label?: string;
      expiresAt?: string;   // ISO 8601
      maxUses?: number;
      requireApproval?: boolean;
    },
  ) {
    let expiresAt: Date | undefined;
    if (body.expiresAt) {
      expiresAt = new Date(body.expiresAt);
      if (Number.isNaN(expiresAt.getTime())) {
        throw new BadRequestException('expiresAt must be a valid ISO 8601 timestamp');
      }
    }
    return this.service.createInviteLink(familyId, userId, {
      label: body.label,
      expiresAt,
      maxUses: body.maxUses,
      requireApproval: body.requireApproval,
    });
  }

  @Get('invite-links')
  async listInviteLinks(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.listInviteLinks(familyId, userId);
  }

  @Delete('invite-links/:token')
  async revokeInviteLink(
    @Param('familyId') _familyId: string,
    @CurrentUser('id') userId: string,
    @Param('token') token: string,
  ) {
    return this.service.revokeInviteLink(token, userId);
  }

  // ── 2.10: Join requests ───────────────────────────────────────────────

  @Get('join-requests')
  async listPendingJoinRequests(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.listPendingJoinRequests(familyId, userId);
  }

  @Post('join-requests/:id/approve')
  async approveJoinRequest(
    @Param('familyId') _familyId: string,
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    return this.service.approveJoinRequest(id, userId);
  }

  @Post('join-requests/:id/reject')
  async rejectJoinRequest(
    @Param('familyId') _familyId: string,
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    return this.service.rejectJoinRequest(id, userId);
  }

  // ── 2.12: Sticker pack + custom reactions ────────────────────────────

  @Post('sticker-pack')
  async setStickerPack(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { stickerPackId?: string | null },
  ) {
    return this.service.setStickerPack(familyId, userId, body.stickerPackId ?? null);
  }

  @Post('custom-reactions')
  async setCustomReactions(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { reactions: string[] },
  ) {
    return this.service.setCustomReactions(familyId, userId, body.reactions ?? []);
  }

  // ── 2.5: Forum topics ────────────────────────────────────────────────

  @Post('topics')
  async createTopic(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { name: string; emoji?: string; iconUrl?: string },
  ) {
    return this.service.createTopic(familyId, userId, body.name, body.emoji, body.iconUrl);
  }

  @Get('topics')
  async listTopics(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.listTopics(familyId, userId);
  }
}

/// Public controller for join-via-link + request-to-join (not family-scoped
/// because the caller isn't a member yet). Mounted at /chat/join.
@Controller('chat/join')
@UseGuards(JwtAuthGuard)
export class JoinViaLinkController {
  constructor(private readonly service: GroupAdminService) {}

  /// POST /chat/join/:token — join (or submit a join request if the link
  /// requires approval).
  @Post(':token')
  async join(@Param('token') token: string, @CurrentUser('id') userId: string) {
    return this.service.joinViaInviteLink(token, userId);
  }
}
