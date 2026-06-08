import {
  Controller,
  Post,
  Delete,
  Get,
  Body,
  Query,
  Param,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { FollowService } from './follow.service';
import {
  FollowUserDto,
  FollowStatusQueryDto,
  FollowPaginationDto,
} from './dto/follow.dto';

@ApiTags('Follow')
@Controller('follow')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class FollowController {
  constructor(private readonly followService: FollowService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Follow a user' })
  follow(@CurrentUser('id') userId: string, @Body() dto: FollowUserDto) {
    return this.followService.followUser(userId, dto.userId);
  }

  @Delete(':userId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Unfollow a user' })
  unfollow(@CurrentUser('id') userId: string, @Param('userId') targetId: string) {
    return this.followService.unfollowUser(userId, targetId);
  }

  @Post('accept/:userId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Accept a follow request' })
  acceptRequest(@CurrentUser('id') userId: string, @Param('userId') followerId: string) {
    return this.followService.acceptRequest(userId, followerId);
  }

  @Post('reject/:userId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Reject a follow request' })
  rejectRequest(@CurrentUser('id') userId: string, @Param('userId') followerId: string) {
    return this.followService.rejectRequest(userId, followerId);
  }

  @Get('followers')
  @ApiOperation({ summary: "Get current user's followers" })
  getFollowers(@CurrentUser('id') userId: string, @Query() dto: FollowPaginationDto) {
    return this.followService.getFollowers(userId, dto);
  }

  @Get('following')
  @ApiOperation({ summary: 'Get users the current user is following' })
  getFollowing(@CurrentUser('id') userId: string, @Query() dto: FollowPaginationDto) {
    return this.followService.getFollowing(userId, dto);
  }

  @Get('requests')
  @ApiOperation({ summary: 'Get pending follow requests' })
  getPendingRequests(@CurrentUser('id') userId: string) {
    return this.followService.getPendingRequests(userId);
  }

  @Get('status')
  @ApiOperation({ summary: 'Get follow status with a specific user' })
  getStatus(@CurrentUser('id') userId: string, @Query() dto: FollowStatusQueryDto) {
    return this.followService.getFollowStatus(userId, dto.userId);
  }

  @Get('counts/:userId')
  @ApiOperation({ summary: 'Get follower and following counts for a user' })
  getCounts(@Param('userId') userId: string) {
    return this.followService.getFollowCounts(userId);
  }
}
