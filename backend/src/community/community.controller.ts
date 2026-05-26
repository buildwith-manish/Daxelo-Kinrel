import { Controller, Get, Post, Patch, Delete, Param, Query, Body, UseGuards } from '@nestjs/common';
import { CommunityService } from './community.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ListCommunitiesDto } from './dto/list-communities.dto';
import { CreateCommunityDto } from './dto/create-community.dto';
import { UpdateCommunityDto } from './dto/update-community.dto';
import { JoinCommunityDto } from './dto/join-community.dto';
import { FeedQueryDto } from './dto/feed-query.dto';
import { CreateEventDto } from './dto/create-event.dto';
import { RsvpDto } from './dto/rsvp.dto';
import { CreateCommentDto } from './dto/create-comment.dto';
import { ToggleReactionDto } from './dto/toggle-reaction.dto';

@Controller('v1')
export class CommunityController {
  constructor(private communityService: CommunityService) {}

  // ── Communities ─────────────────────────────────────────────────────

  /** GET /api/v1/communities — Browse communities */
  @Get('communities')
  async listCommunities(@Query() dto: ListCommunitiesDto) {
    return this.communityService.listCommunities(dto);
  }

  /** POST /api/v1/communities — Create community */
  @Post('communities')
  @UseGuards(JwtAuthGuard)
  async createCommunity(
    @Body() dto: CreateCommunityDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.createCommunity(dto, user.id);
  }

  /** GET /api/v1/communities/:communityId — Get community detail */
  @Get('communities/:communityId')
  async getCommunity(@Param('communityId') communityId: string) {
    return this.communityService.getCommunity(communityId);
  }

  /** PATCH /api/v1/communities/:communityId — Update community */
  @Patch('communities/:communityId')
  @UseGuards(JwtAuthGuard)
  async updateCommunity(
    @Param('communityId') communityId: string,
    @Body() dto: UpdateCommunityDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.updateCommunity(communityId, dto, user.id);
  }

  /** DELETE /api/v1/communities/:communityId — Delete community */
  @Delete('communities/:communityId')
  @UseGuards(JwtAuthGuard)
  async deleteCommunity(
    @Param('communityId') communityId: string,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.deleteCommunity(communityId, user.id);
  }

  /** POST /api/v1/communities/:communityId/join — Join/leave community */
  @Post('communities/:communityId/join')
  @UseGuards(JwtAuthGuard)
  async joinOrLeave(
    @Param('communityId') communityId: string,
    @Body() dto: JoinCommunityDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.joinOrLeave(communityId, dto, user.id);
  }

  // ── Feed ────────────────────────────────────────────────────────────

  /** GET /api/v1/feed — Personalized ranked feed */
  @Get('feed')
  @UseGuards(JwtAuthGuard)
  async getFeed(
    @CurrentUser() user: { id: string },
    @Query() dto: FeedQueryDto,
  ) {
    return this.communityService.getFeed(user.id, dto.cursor, dto.limit);
  }

  // ── Events ──────────────────────────────────────────────────────────

  /** GET /api/v1/families/:familyId/events — List family events */
  @Get('families/:familyId/events')
  async listEvents(
    @Param('familyId') familyId: string,
    @Query('upcoming') upcoming?: string,
    @Query('eventType') eventType?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.listEvents(
      familyId,
      upcoming === 'true',
      eventType,
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
    );
  }

  /** POST /api/v1/families/:familyId/events — Create event */
  @Post('families/:familyId/events')
  @UseGuards(JwtAuthGuard)
  async createEvent(
    @Param('familyId') familyId: string,
    @Body() dto: CreateEventDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.createEvent(familyId, dto, user.id);
  }

  /** POST /api/v1/events/:eventId/rsvp — RSVP */
  @Post('events/:eventId/rsvp')
  @UseGuards(JwtAuthGuard)
  async rsvp(
    @Param('eventId') eventId: string,
    @Body() dto: RsvpDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.rsvp(eventId, dto, user.id);
  }

  // ── Family Stats & Leaderboard ──────────────────────────────────────

  /** GET /api/v1/families/:familyId/stats — Family statistics */
  @Get('families/:familyId/stats')
  async getFamilyStats(@Param('familyId') familyId: string) {
    return this.communityService.getFamilyStats(familyId);
  }

  /** GET /api/v1/families/:familyId/leaderboard — Contribution leaderboard */
  @Get('families/:familyId/leaderboard')
  async getLeaderboard(
    @Param('familyId') familyId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.getLeaderboard(
      familyId,
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 25,
    );
  }

  // ── Comments ────────────────────────────────────────────────────────

  /** POST /api/v1/posts/:postId/comments — Add comment */
  @Post('posts/:postId/comments')
  @UseGuards(JwtAuthGuard)
  async addComment(
    @Param('postId') postId: string,
    @Body() dto: CreateCommentDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.addComment(postId, dto, user.id);
  }

  /** GET /api/v1/posts/:postId/comments — List comments */
  @Get('posts/:postId/comments')
  async listComments(
    @Param('postId') postId: string,
    @Query('parentId') parentId?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.listComments(
      postId,
      parentId,
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 50,
    );
  }

  // ── Reactions ───────────────────────────────────────────────────────

  /** POST /api/v1/posts/:postId/reactions — Toggle emoji reaction */
  @Post('posts/:postId/reactions')
  @UseGuards(JwtAuthGuard)
  async toggleReaction(
    @Param('postId') postId: string,
    @Body() dto: ToggleReactionDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.communityService.toggleReaction(postId, dto, user.id);
  }
}
