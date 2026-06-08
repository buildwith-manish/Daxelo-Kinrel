import { Controller, Get, Post, Param, Body, Query, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { TimelineService } from './timeline.service';

@ApiTags('feed')
@Controller()
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class TimelineController {
  constructor(private readonly timelineService: TimelineService) {}

  // ── Home Feed — combined posts from followed users + joined families ──

  @Get('feed')
  @ApiOperation({ summary: 'Get home feed — posts from followed users and joined families' })
  async getHomeFeed(
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getHomeFeed(
      userId,
      limit ? parseInt(limit, 10) : 20,
      cursor,
    );
  }

  // ── Family Timeline — posts for a specific family ──────────────────────

  @Get('families/:familyId/timeline')
  @ApiOperation({ summary: 'Get family timeline posts' })
  async getTimeline(
    @Param('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getTimeline(familyId, limit ? parseInt(limit, 10) : 20, cursor);
  }

  @Post('families/:familyId/timeline')
  @ApiOperation({ summary: 'Create a post in family timeline' })
  async createPost(
    @Param('familyId') familyId: string,
    @Body() body: { authorId: string; postType: string; content: Record<string, any> },
  ) {
    return this.timelineService.createPost(familyId, body.authorId, body.postType, body.content);
  }
}
