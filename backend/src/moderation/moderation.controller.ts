import { Controller, Get, Post, Patch, Param, Query, Body, UseGuards } from '@nestjs/common';
import { ModerationService } from './moderation.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClassifyContentDto } from './dto/classify-content.dto';
import { ReportContentDto } from './dto/report-content.dto';
import { QueueQueryDto } from './dto/queue-query.dto';
import { ModeratorActionDto } from './dto/moderator-action.dto';
import { AppealDto } from './dto/appeal.dto';
import { AppealReviewDto } from './dto/appeal-review.dto';

@Controller('moderation')
@UseGuards(JwtAuthGuard)
export class ModerationController {
  constructor(private moderationService: ModerationService) {}

  /** POST /api/moderation/classify — Classify content */
  @Post('classify')
  async classifyContent(
    @Body() dto: ClassifyContentDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.moderationService.classifyContent(dto, user.id);
  }

  /** POST /api/moderation/report — Report content */
  @Post('report')
  async reportContent(@Body() dto: ReportContentDto) {
    return this.moderationService.reportContent(dto);
  }

  /** GET /api/moderation/queue — Get moderation queue */
  @Get('queue')
  async getQueue(
    @Query() dto: QueueQueryDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.moderationService.getQueue(dto, user.id);
  }

  /** POST /api/moderation/queue — Moderator action */
  @Post('queue')
  async moderatorAction(
    @Body() dto: ModeratorActionDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.moderationService.moderatorAction(dto, user.id);
  }

  /** POST /api/moderation/appeal — File appeal */
  @Post('appeal')
  async fileAppeal(@Body() dto: AppealDto) {
    return this.moderationService.fileAppeal(dto);
  }

  /** POST /api/moderation/appeal/:appealId/review — Review appeal */
  @Post('appeal/:appealId/review')
  async reviewAppeal(
    @Param('appealId') appealId: string,
    @Body() dto: AppealReviewDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.moderationService.reviewAppeal(appealId, dto, user.id);
  }
}
