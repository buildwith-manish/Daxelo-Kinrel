import {
  Controller,
  Get,
  Post,
  Delete,
  Patch,
  Param,
  Body,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CircleService } from './circle.service';
import {
  CreateCircleDto,
  UpdateCircleDto,
  AddMemberDto,
  SendCircleMessageDto,
  AddCircleReactionDto,
  MarkCircleReadDto,
  MuteDto,
} from './dto/circle.dto';

/**
 * CircleController — REST endpoints for account-level cross-family
 * group chats.
 *
 * Real-time updates are pushed over Socket.IO via CircleGateway;
 * this controller handles the REST surface (create, list, message
 * send/list, read receipts, reactions, pins).
 *
 * Every mutation enforces the product rules server-side (see
 * CircleService for the enforcement logic):
 *   • Eligibility: "share at least one family OR accepted follow"
 *   • Blocked users cannot be added
 *   • Limits: max 100 members per circle, max 30 circles per user
 *   • Roles: admin can add/remove members; onlyAdminsPost enforced
 *   • Last-admin auto-promote on leave
 */
@Controller('circles')
@UseGuards(JwtAuthGuard)
export class CircleController {
  constructor(private readonly circleService: CircleService) {}

  // ── Circle CRUD ──────────────────────────────────────────────

  @Post()
  async createCircle(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateCircleDto,
  ) {
    return this.circleService.createCircle(userId, dto);
  }

  @Get()
  async listMyCircles(@CurrentUser('id') userId: string) {
    return this.circleService.listMyCircles(userId);
  }

  @Get(':circleId')
  async getCircle(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.circleService.getCircle(circleId, userId);
  }

  @Patch(':circleId')
  async updateSettings(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateCircleDto,
  ) {
    return this.circleService.updateSettings(circleId, userId, dto);
  }

  @Delete(':circleId')
  async deleteCircle(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.circleService.deleteCircle(circleId, userId);
  }

  // ── Member management ────────────────────────────────────────

  @Post(':circleId/members')
  async addMember(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: AddMemberDto,
  ) {
    return this.circleService.addMember(circleId, userId, dto);
  }

  @Delete(':circleId/members/:targetUserId')
  async removeMember(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Param('targetUserId') targetUserId: string,
  ) {
    return this.circleService.removeMember(circleId, userId, targetUserId);
  }

  @Post(':circleId/leave')
  async leaveCircle(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.circleService.leaveCircle(circleId, userId);
  }

  @Post(':circleId/transfer-admin')
  async transferAdmin(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Body('targetUserId') targetUserId: string,
  ) {
    return this.circleService.transferAdmin(circleId, userId, targetUserId);
  }

  @Post(':circleId/mute')
  async mute(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: MuteDto,
  ) {
    const mutedUntil = dto.mutedUntil ? new Date(dto.mutedUntil) : null;
    return this.circleService.mute(circleId, userId, mutedUntil);
  }

  // ── Messages ─────────────────────────────────────────────────

  @Post(':circleId/messages')
  async sendMessage(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: SendCircleMessageDto,
  ) {
    return this.circleService.sendMessage(circleId, userId, dto);
  }

  @Get(':circleId/messages')
  async listMessages(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    return this.circleService.listMessages(
      circleId,
      userId,
      limit ? parseInt(limit, 10) : undefined,
      before,
    );
  }

  @Post(':circleId/messages/read')
  async markAsRead(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: MarkCircleReadDto,
  ) {
    return this.circleService.markAsRead(circleId, userId, dto.messageId);
  }

  // ── Reactions + Pins ────────────────────────────────────────

  @Post(':circleId/messages/:messageId/reactions')
  async addReaction(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
    @Body() dto: AddCircleReactionDto,
  ) {
    return this.circleService.addReaction(circleId, userId, messageId, dto);
  }

  @Delete(':circleId/messages/:messageId/reactions/:emoji')
  async removeReaction(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
    @Param('emoji') emoji: string,
  ) {
    return this.circleService.removeReaction(
      circleId,
      userId,
      messageId,
      decodeURIComponent(emoji),
    );
  }

  @Post(':circleId/messages/:messageId/pin')
  async pinMessage(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
  ) {
    return this.circleService.pinMessage(circleId, userId, messageId);
  }

  @Delete(':circleId/messages/:messageId/pin')
  async unpinMessage(
    @Param('circleId') circleId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
  ) {
    return this.circleService.unpinMessage(circleId, userId, messageId);
  }
}
