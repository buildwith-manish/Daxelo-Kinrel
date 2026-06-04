import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ModerationService } from './moderation.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('moderation')
@UseGuards(JwtAuthGuard)
export class ModerationController {
  constructor(private readonly moderationService: ModerationService) {}

  /**
   * POST /api/moderation/report
   * Submit a content report.
   */
  @Post('report')
  @HttpCode(HttpStatus.CREATED)
  async submitReport(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      targetType: string;
      targetId: string;
      reason: string;
      description?: string;
    },
  ) {
    return this.moderationService.submitReport(userId, body);
  }

  /**
   * GET /api/moderation/queue
   * Get moderation queue (admin).
   */
  @Get('queue')
  async getQueue(
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('status') status?: string,
    @Query('priority') priority?: string,
    @Query('category') category?: string,
  ) {
    return this.moderationService.getQueue(
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
      { status, priority, category },
    );
  }

  /**
   * POST /api/moderation/classify
   * Classify content (admin).
   */
  @Post('classify')
  @HttpCode(HttpStatus.OK)
  async classifyContent(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      contentType: string;
      contentId: string;
      contentPreview: string;
    },
  ) {
    return this.moderationService.classifyContent(userId, body);
  }

  /**
   * GET /api/moderation/appeal
   * List appeals.
   */
  @Get('appeal')
  async listAppeals(
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('status') status?: string,
  ) {
    return this.moderationService.listAppeals(
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
      status,
    );
  }

  /**
   * PATCH /api/moderation/appeal/:appealId/review
   * Review an appeal (admin).
   */
  @Patch('appeal/:appealId/review')
  async reviewAppeal(
    @CurrentUser('id') userId: string,
    @Param('appealId') appealId: string,
    @Body()
    body: {
      decision: string;
      notes?: string;
    },
  ) {
    return this.moderationService.reviewAppeal(appealId, userId, body);
  }
}
