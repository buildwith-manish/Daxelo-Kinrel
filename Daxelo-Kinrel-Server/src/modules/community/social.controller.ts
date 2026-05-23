import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { CommunityService } from './community.service';
import { CreateCommentDto } from './dto/create-comment.dto';

/**
 * SocialController — /api/v1/posts/*
 *
 * Routes:
 * - GET  /api/v1/posts/:postId/comments   — Get comments
 * - POST /api/v1/posts/:postId/comments   — Add comment
 * - GET  /api/v1/posts/:postId/reactions  — Get reactions
 * - POST /api/v1/posts/:postId/reactions  — Toggle reaction
 */
@Controller('v1/posts')
export class SocialController {
  constructor(private readonly communityService: CommunityService) {}

  // ── Comments ──────────────────────────────────────────────────────

  @Get(':postId/comments')
  async getComments(
    @Param('postId') postId: string,
    @Query('parentId') parentId?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.communityService.getComments(postId, {
      parentId: parentId || undefined,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Post(':postId/comments')
  @HttpCode(HttpStatus.CREATED)
  async createComment(
    @Param('postId') postId: string,
    @Body() dto: CreateCommentDto,
  ) {
    return this.communityService.createComment(postId, dto);
  }

  // ── Reactions ─────────────────────────────────────────────────────

  @Get(':postId/reactions')
  async getReactions(
    @Param('postId') postId: string,
    @Query('userId') userId?: string,
  ) {
    return this.communityService.getReactions(postId, userId || undefined);
  }

  @Post(':postId/reactions')
  @HttpCode(HttpStatus.CREATED)
  async toggleReaction(
    @Param('postId') postId: string,
    @Body() body: { userId: string; emoji: string },
  ) {
    return this.communityService.toggleReaction(postId, body);
  }
}
