import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ModerationService } from './moderation.service';
import { ReportDto } from './dto/report.dto';
import { ReviewDto } from './dto/review.dto';
import { AppealDto, AppealReviewDto } from './dto/appeal.dto';

/**
 * ModerationController — /api/moderation/*
 *
 * Routes:
 * - POST /api/moderation/report              — Submit report
 * - GET  /api/moderation/queue               — Get queue
 * - POST /api/moderation/queue               — Review case
 * - POST /api/moderation/appeal              — Submit appeal
 * - POST /api/moderation/appeal/:appealId/review — Review appeal
 */
@Controller('moderation')
export class ModerationController {
  constructor(private readonly moderationService: ModerationService) {}

  // ── POST /api/moderation/report ───────────────────────────────────
  @Post('report')
  @HttpCode(HttpStatus.CREATED)
  async submitReport(@Body() dto: ReportDto) {
    return this.moderationService.submitReport(dto);
  }

  // ── GET /api/moderation/queue ─────────────────────────────────────
  @Get('queue')
  async getQueue(
    @Query('userId') userId: string,
    @Query('status') status?: string,
    @Query('priority') priority?: string,
    @Query('category') category?: string,
    @Query('limit') limit?: string,
  ) {
    return this.moderationService.getQueue({
      userId,
      status: status || undefined,
      priority: priority || undefined,
      category: category || undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  // ── POST /api/moderation/queue ────────────────────────────────────
  @Post('queue')
  async reviewCase(@Body() dto: ReviewDto) {
    return this.moderationService.reviewCase(dto);
  }

  // ── POST /api/moderation/appeal ───────────────────────────────────
  @Post('appeal')
  @HttpCode(HttpStatus.CREATED)
  async submitAppeal(@Body() dto: AppealDto) {
    return this.moderationService.submitAppeal(dto);
  }
}

/**
 * ModerationAppealController — /api/moderation/appeal/:appealId/review
 *
 * Separate controller to properly capture the `:appealId` URL param.
 */
@Controller('moderation/appeal')
export class ModerationAppealController {
  constructor(private readonly moderationService: ModerationService) {}

  @Post(':appealId/review')
  async reviewAppeal(
    @Param('appealId') appealId: string,
    @Body() dto: AppealReviewDto,
  ) {
    return this.moderationService.reviewAppeal(appealId, dto);
  }
}
