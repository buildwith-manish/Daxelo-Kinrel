import { Controller, Get, Post, Param, Body, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { TimelineService } from './timeline.service';

@Controller('families/:familyId/timeline')
@UseGuards(JwtAuthGuard)
export class TimelineController {
  constructor(private readonly timelineService: TimelineService) {}

  @Get()
  async getTimeline(
    @Param('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getTimeline(familyId, limit ? parseInt(limit, 10) : 20, cursor);
  }

  @Post()
  async createPost(
    @Param('familyId') familyId: string,
    @Body() body: { authorId: string; postType: string; content: Record<string, any> },
  ) {
    return this.timelineService.createPost(familyId, body.authorId, body.postType, body.content);
  }
}
