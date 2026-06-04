import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { CommunityService } from './community.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('v1/communities')
@UseGuards(JwtAuthGuard)
export class CommunityController {
  constructor(private readonly communityService: CommunityService) {}

  /**
   * GET /api/v1/communities
   * Search/browse communities.
   */
  @Get()
  async search(
    @Query('search') search?: string,
    @Query('type') type?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.search({
      search,
      type,
      page: page ? parseInt(page, 10) : 1,
      limit: limit ? parseInt(limit, 10) : 20,
    });
  }

  /**
   * POST /api/v1/communities
   * Create a community.
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      type: string;
      name: string;
      description?: string;
      isPrivate?: boolean;
      gotraName?: string;
      villageName?: string;
      surname?: string;
      region?: string;
    },
  ) {
    return this.communityService.create(userId, body);
  }

  /**
   * GET /api/v1/communities/:communityId
   * Get community detail.
   */
  @Get(':communityId')
  async findOne(@Param('communityId') communityId: string) {
    return this.communityService.findOne(communityId);
  }

  /**
   * POST /api/v1/communities/:communityId/join
   * Join a community.
   */
  @Post(':communityId/join')
  @HttpCode(HttpStatus.OK)
  async join(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
  ) {
    return this.communityService.join(communityId, userId);
  }
}
