import { Controller, Get, Query } from '@nestjs/common';
import { CommunityService } from './community.service';

/**
 * FeedController — /api/v1/feed
 */
@Controller('v1/feed')
export class FeedController {
  constructor(private readonly communityService: CommunityService) {}

  @Get()
  async getFeed(
    @Query('userId') userId: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
    @Query('types') types?: string,
  ) {
    return this.communityService.getFeed({
      userId,
      cursor: cursor || undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      types: types || undefined,
    });
  }
}
