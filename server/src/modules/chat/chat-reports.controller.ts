// server/src/modules/chat/chat-reports.controller.ts
//
// DAXELO KINREL — Tier 3 Feature 3.6: Block + Report from chat — Controller

import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { ChatReportsService } from './chat-reports.service';

@Controller('chat/moderation')
@UseGuards(JwtAuthGuard)
export class ChatReportsController {
  constructor(private readonly service: ChatReportsService) {}

  /**
   * POST /chat/moderation/report
   * Submit a report. Body: { reportedUserId?, familyId?, messageId?, reason, details? }
   * Either reportedUserId OR messageId must be set. When messageId is set,
   * the RPC resolves the reportedUserId from the message's sender.
   */
  @Post('report')
  async report(
    @CurrentUser('id') userId: string,
    @Body() body: {
      reportedUserId?: string | null;
      familyId?: string | null;
      messageId?: string | null;
      reason: string;
      details?: string | null;
    },
  ) {
    return this.service.reportUser(userId, body);
  }

  /**
   * POST /chat/moderation/block
   * Block a user. Idempotent (re-blocking a user returns the existing block).
   * BlockedUser table already exists; this RPC wraps the insert.
   */
  @Post('block')
  async block(
    @CurrentUser('id') userId: string,
    @Body() body: { blockedId: string },
  ) {
    return this.service.blockUser(userId, body.blockedId);
  }

  /**
   * GET /chat/moderation/reports
   * List the caller's own submitted reports.
   */
  @Get('reports')
  async listMyReports(@CurrentUser('id') userId: string) {
    return this.service.listMyReports(userId);
  }
}
