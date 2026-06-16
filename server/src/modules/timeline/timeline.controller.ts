import {
  Controller,
  Get,
  Post,
  Delete,
  Param,
  Body,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiBearerAuth,
  ApiResponse,
  ApiParam,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { TimelineService } from './timeline.service';
import {
  CreatePostDto,
  ReactDto,
  CreateCommentDto,
} from './dto/timeline.dto';

@ApiTags('feed')
@Controller()
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class TimelineController {
  constructor(private readonly timelineService: TimelineService) {}

  // ── Home Feed ─────────────────────────────────────────────────────

  @Get('feed')
  @ApiOperation({ summary: 'Get home feed — posts from followed users and joined families' })
  @ApiResponse({ status: 200, description: 'Paginated home feed posts' })
  async getHomeFeed(
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getHomeFeed(
      userId,
      limit ? parseInt(limit, 10) : 20,
      cursor,
    );
  }

  // ── Family Timeline ───────────────────────────────────────────────

  @Get('families/:familyId/timeline')
  @ApiOperation({ summary: 'Get family timeline posts' })
  @ApiParam({ name: 'familyId', description: 'Family ID' })
  @ApiResponse({ status: 200, description: 'Paginated family timeline posts' })
  async getTimeline(
    @Param('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getTimeline(
      familyId,
      limit ? parseInt(limit, 10) : 20,
      cursor,
    );
  }

  @Post('families/:familyId/timeline')
  @ApiOperation({ summary: 'Create a post in family timeline' })
  @ApiParam({ name: 'familyId', description: 'Family ID' })
  @ApiResponse({ status: 201, description: 'Post created successfully' })
  async createPost(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: CreatePostDto,
  ) {
    return this.timelineService.createPost(familyId, userId, dto.postType, dto.content);
  }

  // ── Reactions ─────────────────────────────────────────────────────

  @Post('families/:familyId/posts/:postId/react')
  @ApiOperation({ summary: 'Toggle a reaction on a timeline post' })
  @ApiParam({ name: 'familyId', description: 'Family ID' })
  @ApiParam({ name: 'postId', description: 'Post ID' })
  @ApiResponse({ status: 200, description: 'Reaction toggled; returns updated reactions' })
  async toggleReaction(
    @Param('familyId') _familyId: string,
    @Param('postId') postId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: ReactDto,
  ) {
    return this.timelineService.toggleReaction(postId, userId, dto.emoji);
  }

  // ── Comments ──────────────────────────────────────────────────────

  @Get('families/:familyId/posts/:postId/comments')
  @ApiOperation({ summary: 'Get comments for a timeline post' })
  @ApiParam({ name: 'familyId', description: 'Family ID' })
  @ApiParam({ name: 'postId', description: 'Post ID' })
  @ApiResponse({ status: 200, description: 'Paginated comments' })
  async getComments(
    @Param('familyId') _familyId: string,
    @Param('postId') postId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.timelineService.getComments(
      postId,
      limit ? parseInt(limit, 10) : 50,
      cursor,
    );
  }

  @Post('families/:familyId/posts/:postId/comments')
  @ApiOperation({ summary: 'Add a comment to a timeline post' })
  @ApiParam({ name: 'familyId', description: 'Family ID' })
  @ApiParam({ name: 'postId', description: 'Post ID' })
  @ApiResponse({ status: 201, description: 'Comment added' })
  async addComment(
    @Param('familyId') _familyId: string,
    @Param('postId') postId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: CreateCommentDto,
  ) {
    return this.timelineService.addComment(postId, userId, dto);
  }

  @Delete('families/:familyId/posts/:postId/comments/:commentId')
  @ApiOperation({ summary: 'Delete a comment from a timeline post' })
  @ApiParam({ name: 'familyId', description: 'Family ID' })
  @ApiParam({ name: 'postId', description: 'Post ID' })
  @ApiParam({ name: 'commentId', description: 'Comment ID' })
  @ApiResponse({ status: 200, description: 'Comment deleted' })
  async deleteComment(
    @Param('familyId') _familyId: string,
    @Param('postId') postId: string,
    @Param('commentId') commentId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.timelineService.deleteComment(postId, commentId, userId);
  }

  // ── Delete Post ───────────────────────────────────────────────────

  @Delete('families/:familyId/posts/:postId')
  @ApiOperation({ summary: 'Delete a timeline post (author or family admin only)' })
  @ApiParam({ name: 'familyId', description: 'Family ID' })
  @ApiParam({ name: 'postId', description: 'Post ID' })
  @ApiResponse({ status: 200, description: 'Post deleted' })
  @ApiResponse({ status: 403, description: 'Forbidden — not author or admin' })
  async deletePost(
    @Param('familyId') _familyId: string,
    @Param('postId') postId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.timelineService.deletePost(postId, userId);
  }
}
