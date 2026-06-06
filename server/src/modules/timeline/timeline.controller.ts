import { Controller, Get, Post, Param, Body, Query, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { TimelineService } from './timeline.service';

@ApiTags('Timeline')
@Controller('families/:familyId/timeline')
@UseGuards(JwtAuthGuard)
export class TimelineController {
  constructor(private readonly timelineService: TimelineService) {}

  @Get()
  async getTimeline(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getTimeline(familyId, userId, limit ? parseInt(limit, 10) : 20, cursor);
  }

  @Post()
  async createPost(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() body: { postType: string; content: Record<string, any> },
  ) {
    return this.timelineService.createPost(familyId, userId, body.postType, body.content);
  }
}
