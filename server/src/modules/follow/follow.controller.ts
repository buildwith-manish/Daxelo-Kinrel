import {
  Controller,
  Post,
  Delete,
  Get,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { FollowService } from './follow.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { FollowPaginationDto } from './dto/follow-user.dto';

@ApiTags('Follow')
@Controller('follow')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class FollowController {
  constructor(private readonly followService: FollowService) {}

  // ── Static routes MUST come before dynamic :userId routes ──────

  @Get('followers')
  @ApiOperation({ summary: "Get current user's followers (paginated)" })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns paginated followers list' })
  async getFollowers(
    @CurrentUser('id') userId: string,
    @Query() pagination: FollowPaginationDto,
  ) {
    return this.followService.getFollowers(userId, pagination);
  }

  @Get('following')
  @ApiOperation({ summary: "Get current user's following (paginated)" })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns paginated following list' })
  async getFollowing(
    @CurrentUser('id') userId: string,
    @Query() pagination: FollowPaginationDto,
  ) {
    return this.followService.getFollowing(userId, pagination);
  }

  @Get('requests')
  @ApiOperation({ summary: 'Get pending follow requests received' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns pending follow requests' })
  async getFollowRequests(@CurrentUser('id') userId: string) {
    return this.followService.getFollowRequests(userId);
  }

  // ── Dynamic :userId routes ──────────────────────────────────────

  @Post(':userId')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Follow a user' })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'Followed successfully or request sent' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Cannot follow yourself' })
  @ApiResponse({ status: HttpStatus.CONFLICT, description: 'Already following or request pending' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'User not found' })
  async followUser(
    @CurrentUser('id') currentUserId: string,
    @Param('userId') targetUserId: string,
  ) {
    return this.followService.followUser(currentUserId, targetUserId);
  }

  @Delete(':userId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Unfollow a user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Unfollowed successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Not following this user' })
  async unfollowUser(
    @CurrentUser('id') currentUserId: string,
    @Param('userId') targetUserId: string,
  ) {
    return this.followService.unfollowUser(currentUserId, targetUserId);
  }

  @Post(':userId/accept')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Accept a follow request' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Follow request accepted' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Follow request not found' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Only the profile owner can accept' })
  async acceptFollowRequest(
    @CurrentUser('id') userId: string,
    @Param('userId') requesterId: string,
  ) {
    return this.followService.acceptFollowRequest(userId, requesterId);
  }

  @Post(':userId/reject')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Reject a follow request' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Follow request rejected' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Follow request not found' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Only the profile owner can reject' })
  async rejectFollowRequest(
    @CurrentUser('id') userId: string,
    @Param('userId') requesterId: string,
  ) {
    return this.followService.rejectFollowRequest(userId, requesterId);
  }

  @Get(':userId/status')
  @ApiOperation({ summary: 'Get follow status between current user and target user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns follow status' })
  async getFollowStatus(
    @CurrentUser('id') currentUserId: string,
    @Param('userId') targetUserId: string,
  ) {
    return this.followService.getFollowStatus(currentUserId, targetUserId);
  }
}
