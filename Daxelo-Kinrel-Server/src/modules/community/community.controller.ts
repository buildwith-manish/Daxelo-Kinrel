import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { CommunityService } from './community.service';
import { CreateCommunityDto } from './dto/create-community.dto';

/**
 * CommunityController — /api/v1/communities/*
 *
 * Routes:
 * - GET    /api/v1/communities                    — List communities
 * - POST   /api/v1/communities                    — Create community
 * - GET    /api/v1/communities/:communityId        — Get community
 * - PATCH  /api/v1/communities/:communityId        — Update community
 * - DELETE /api/v1/communities/:communityId        — Delete community
 * - POST   /api/v1/communities/:communityId/join   — Join/leave
 */
@Controller('v1/communities')
export class CommunityController {
  constructor(private readonly communityService: CommunityService) {}

  @Get()
  async listCommunities(
    @Query('type') type?: string,
    @Query('q') q?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.listCommunities({
      type: type || undefined,
      q: q || undefined,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createCommunity(@Body() dto: CreateCommunityDto) {
    return this.communityService.createCommunity(dto);
  }

  @Get(':communityId')
  async getCommunity(@Param('communityId') communityId: string) {
    return this.communityService.getCommunity(communityId);
  }

  @Patch(':communityId')
  async updateCommunity(
    @Param('communityId') communityId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.communityService.updateCommunity(communityId, body);
  }

  @Delete(':communityId')
  async deleteCommunity(
    @Param('communityId') communityId: string,
    @Query('userId') userId: string,
  ) {
    return this.communityService.deleteCommunity(communityId, userId);
  }

  @Post(':communityId/join')
  @HttpCode(HttpStatus.OK)
  async joinOrLeave(
    @Param('communityId') communityId: string,
    @Body() body: { userId: string; action: 'join' | 'leave' },
  ) {
    return this.communityService.joinOrLeave(communityId, body);
  }
}
