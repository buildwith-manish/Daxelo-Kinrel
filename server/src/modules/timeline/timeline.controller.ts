import { Controller, Get, Post, Param, Body, Query, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { TimelineService } from './timeline.service';

@ApiTags('Timeline')
@ApiBearerAuth()
@Controller('feed')
@UseGuards(JwtAuthGuard)
export class TimelineController {
  constructor(private readonly timelineService: TimelineService) {}

  @Get()
  @ApiOperation({ summary: 'Get unified feed (followed users + family posts)' })
  async getUnifiedFeed(
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getUnifiedFeed(userId, limit ? parseInt(limit, 10) : 20, cursor);
  }

  @Get('family/:familyId')
  @ApiOperation({ summary: 'Get family-specific timeline' })
  async getTimeline(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getTimeline(familyId, userId, limit ? parseInt(limit, 10) : 20, cursor);
  }

  @Post('family/:familyId')
  @ApiOperation({ summary: 'Create a post in family timeline' })
  async createPost(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() body: { postType: string; content: Record<string, any> },
  ) {
    return this.timelineService.createPost(familyId, userId, body.postType, body.content);
  }
}
