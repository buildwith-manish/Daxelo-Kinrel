import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Query,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiResponse } from '@nestjs/swagger';
import { CommunityService } from './community.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import {
  CreateCommunityDto,
  UpdateCommunityDto,
  SearchCommunityDto,
  JoinCommunityDto,
  CreateCommunityPostDto,
  UpdateCommunityPostDto,
  CreateCommunityEventDto,
  UpdateCommunityEventDto,
  RSVPDto,
  UpdateMemberRoleDto,
} from './dto';

@ApiTags('Communities')
@Controller('v1/communities')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class CommunityController {
  constructor(private readonly communityService: CommunityService) {}

  // ── Community Management ──────────────────────────────────────────────

  @Get()
  @ApiOperation({ summary: 'Search/browse communities' })
  @ApiResponse({ status: 200, description: 'Paginated list of communities' })
  async search(@Query() dto: SearchCommunityDto) {
    return this.communityService.search(dto);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a community' })
  @ApiResponse({ status: 201, description: 'Community created' })
  async create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateCommunityDto,
  ) {
    return this.communityService.create(userId, dto);
  }

  @Get(':communityId')
  @ApiOperation({ summary: 'Get community detail' })
  @ApiResponse({ status: 200, description: 'Community details' })
  @ApiResponse({ status: 404, description: 'Community not found' })
  async findOne(@Param('communityId') communityId: string) {
    return this.communityService.findOne(communityId);
  }

  @Patch(':communityId')
  @ApiOperation({ summary: 'Update community (admin only)' })
  @ApiResponse({ status: 200, description: 'Community updated' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async update(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Body() dto: UpdateCommunityDto,
  ) {
    return this.communityService.update(communityId, userId, dto);
  }

  @Delete(':communityId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete community (admin only)' })
  @ApiResponse({ status: 200, description: 'Community deleted' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async remove(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
  ) {
    return this.communityService.delete(communityId, userId);
  }

  @Post(':communityId/join')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Join a community' })
  @ApiResponse({ status: 200, description: 'Joined or request pending' })
  async join(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Body() _dto: JoinCommunityDto,
  ) {
    return this.communityService.join(communityId, userId);
  }

  @Post(':communityId/leave')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Leave a community' })
  @ApiResponse({ status: 200, description: 'Left community' })
  async leave(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
  ) {
    return this.communityService.leave(communityId, userId);
  }

  // ── Members ───────────────────────────────────────────────────────────

  @Get(':communityId/members')
  @ApiOperation({ summary: 'List community members (paginated)' })
  @ApiResponse({ status: 200, description: 'Paginated member list' })
  async listMembers(
    @Param('communityId') communityId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.listMembers(communityId, {
      page: page ? parseInt(page, 10) : 1,
      limit: limit ? parseInt(limit, 10) : 20,
    });
  }

  @Patch(':communityId/members/:userId/role')
  @ApiOperation({ summary: 'Update member role (admin only)' })
  @ApiResponse({ status: 200, description: 'Role updated' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async updateMemberRole(
    @CurrentUser('id') requesterId: string,
    @Param('communityId') communityId: string,
    @Param('userId') userId: string,
    @Body() dto: UpdateMemberRoleDto,
  ) {
    return this.communityService.updateMemberRole(communityId, requesterId, userId, dto.role);
  }

  @Delete(':communityId/members/:userId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Remove/ban member (admin/mod only)' })
  @ApiResponse({ status: 200, description: 'Member removed' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async removeMember(
    @CurrentUser('id') requesterId: string,
    @Param('communityId') communityId: string,
    @Param('userId') userId: string,
  ) {
    return this.communityService.removeMember(communityId, requesterId, userId);
  }

  @Get(':communityId/members/requests')
  @ApiOperation({ summary: 'List pending join requests (private communities)' })
  @ApiResponse({ status: 200, description: 'List of pending requests' })
  async getPendingRequests(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
  ) {
    return this.communityService.getPendingRequests(communityId, userId);
  }

  @Post(':communityId/members/:userId/approve')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Approve a join request (admin only)' })
  @ApiResponse({ status: 200, description: 'Join request approved' })
  async approveJoinRequest(
    @CurrentUser('id') requesterId: string,
    @Param('communityId') communityId: string,
    @Param('userId') userId: string,
  ) {
    return this.communityService.approveJoinRequest(communityId, requesterId, userId);
  }

  @Post(':communityId/members/:userId/reject')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Reject a join request (admin only)' })
  @ApiResponse({ status: 200, description: 'Join request rejected' })
  async rejectJoinRequest(
    @CurrentUser('id') requesterId: string,
    @Param('communityId') communityId: string,
    @Param('userId') userId: string,
  ) {
    return this.communityService.rejectJoinRequest(communityId, requesterId, userId);
  }

  // ── Posts ─────────────────────────────────────────────────────────────

  @Get(':communityId/posts')
  @ApiOperation({ summary: 'List community posts (paginated)' })
  @ApiResponse({ status: 200, description: 'Paginated post list' })
  async listPosts(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.listPosts(communityId, userId, {
      page: page ? parseInt(page, 10) : 1,
      limit: limit ? parseInt(limit, 10) : 20,
    });
  }

  @Post(':communityId/posts')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a post in a community (members only)' })
  @ApiResponse({ status: 201, description: 'Post created' })
  @ApiResponse({ status: 403, description: 'Not a member' })
  async createPost(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Body() dto: CreateCommunityPostDto,
  ) {
    return this.communityService.createPost(communityId, userId, dto);
  }

  @Get(':communityId/posts/:postId')
  @ApiOperation({ summary: 'Get a single post' })
  @ApiResponse({ status: 200, description: 'Post details' })
  @ApiResponse({ status: 404, description: 'Post not found' })
  async getPost(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Param('postId') postId: string,
  ) {
    return this.communityService.getPost(communityId, userId, postId);
  }

  @Patch(':communityId/posts/:postId')
  @ApiOperation({ summary: 'Update a post (author or admin/mod)' })
  @ApiResponse({ status: 200, description: 'Post updated' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async updatePost(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Param('postId') postId: string,
    @Body() dto: UpdateCommunityPostDto,
  ) {
    return this.communityService.updatePost(communityId, userId, postId, dto);
  }

  @Delete(':communityId/posts/:postId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete a post (author or admin/mod)' })
  @ApiResponse({ status: 200, description: 'Post deleted' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async deletePost(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Param('postId') postId: string,
  ) {
    return this.communityService.deletePost(communityId, userId, postId);
  }

  // ── Events ────────────────────────────────────────────────────────────

  @Get(':communityId/events')
  @ApiOperation({ summary: 'List community events' })
  @ApiResponse({ status: 200, description: 'Event list' })
  async listEvents(
    @Param('communityId') communityId: string,
    @Query('filter') filter?: string,
  ) {
    return this.communityService.listEvents(communityId, filter);
  }

  @Post(':communityId/events')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create an event (admin/mod only)' })
  @ApiResponse({ status: 201, description: 'Event created' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async createEvent(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Body() dto: CreateCommunityEventDto,
  ) {
    return this.communityService.createEvent(communityId, userId, dto);
  }

  @Get(':communityId/events/:eventId')
  @ApiOperation({ summary: 'Get event detail' })
  @ApiResponse({ status: 200, description: 'Event details' })
  @ApiResponse({ status: 404, description: 'Event not found' })
  async getEvent(
    @Param('communityId') communityId: string,
    @Param('eventId') eventId: string,
  ) {
    return this.communityService.getEvent(communityId, eventId);
  }

  @Patch(':communityId/events/:eventId')
  @ApiOperation({ summary: 'Update an event (creator or admin)' })
  @ApiResponse({ status: 200, description: 'Event updated' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async updateEvent(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Param('eventId') eventId: string,
    @Body() dto: UpdateCommunityEventDto,
  ) {
    return this.communityService.updateEvent(communityId, userId, eventId, dto);
  }

  @Delete(':communityId/events/:eventId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete an event (creator or admin)' })
  @ApiResponse({ status: 200, description: 'Event deleted' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  async deleteEvent(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Param('eventId') eventId: string,
  ) {
    return this.communityService.deleteEvent(communityId, userId, eventId);
  }

  @Post(':communityId/events/:eventId/rsvp')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'RSVP to an event (members only)' })
  @ApiResponse({ status: 200, description: 'RSVP recorded' })
  async rsvp(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Param('eventId') eventId: string,
    @Body() dto: RSVPDto,
  ) {
    return this.communityService.rsvp(communityId, userId, eventId, dto.status);
  }

  @Get(':communityId/events/:eventId/rsvps')
  @ApiOperation({ summary: 'List RSVPs for an event' })
  @ApiResponse({ status: 200, description: 'RSVP list' })
  async listRsvps(
    @Param('communityId') communityId: string,
    @Param('eventId') eventId: string,
  ) {
    return this.communityService.listRsvps(communityId, eventId);
  }

  @Post(':communityId/events/:eventId/remind')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Set a reminder for an event (members only)' })
  @ApiResponse({ status: 200, description: 'Reminder set' })
  async setReminder(
    @CurrentUser('id') userId: string,
    @Param('communityId') communityId: string,
    @Param('eventId') eventId: string,
  ) {
    return this.communityService.setReminder(communityId, userId, eventId);
  }
}
