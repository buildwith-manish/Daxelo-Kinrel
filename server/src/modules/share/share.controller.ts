import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiBearerAuth,
  ApiResponse,
  ApiParam,
} from '@nestjs/swagger';
import { ShareService } from './share.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import {
  CreateShareableLinkDto,
  TrackShareDto,
} from './dto/share.dto';

@ApiTags('share')
@Controller('share')
export class ShareController {
  constructor(private readonly shareService: ShareService) {}

  /**
   * POST /api/share
   * Create a shareable link (authenticated).
   */
  @Post()
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a shareable link' })
  @ApiResponse({ status: 201, description: 'Shareable link created' })
  async createShareableLink(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateShareableLinkDto,
  ) {
    return this.shareService.createShareableLink(userId, dto);
  }

  /**
   * POST /api/share/track
   * Track a share event (increment shareCount).
   */
  @Post('track')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Track a share event — increment shareCount' })
  @ApiResponse({ status: 200, description: 'Share tracked' })
  async trackShare(@Body() dto: TrackShareDto) {
    return this.shareService.trackShare(dto);
  }

  /**
   * GET /api/share/mine
   * List all shareable links created by the current user.
   */
  @Get('mine')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'List my shareable links' })
  @ApiResponse({ status: 200, description: 'Paginated list of user shareable links' })
  async getMyShareableLinks(
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('page') page?: string,
  ) {
    return this.shareService.getMyShareableLinks(
      userId,
      limit ? parseInt(limit, 10) : 20,
      page ? parseInt(page, 10) : 1,
    );
  }

  /**
   * GET /api/share?token=xxx
   * Get share stats (authenticated).
   */
  @Get()
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Get share stats by token' })
  @ApiResponse({ status: 200, description: 'Share stats returned' })
  async getShareStats(@Query('token') token: string) {
    if (!token) {
      return { error: 'Token is required' };
    }
    return this.shareService.getShareStats(token);
  }

  /**
   * GET /api/share/:token
   * Get shared card data (public — no auth required).
   */
  @Get(':token')
  @ApiOperation({ summary: 'Get shared card data (public)' })
  @ApiParam({ name: 'token', description: 'Shareable link token' })
  @ApiResponse({ status: 200, description: 'Shared card data' })
  @ApiResponse({ status: 404, description: 'Link not found or expired' })
  async getSharedCard(@Param('token') token: string) {
    return this.shareService.getSharedCard(token);
  }

  /**
   * DELETE /api/share/:id
   * Revoke a shareable link (authenticated, owner only).
   */
  @Delete(':id')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Revoke a shareable link' })
  @ApiParam({ name: 'id', description: 'Shareable link ID' })
  @ApiResponse({ status: 200, description: 'Link revoked' })
  @ApiResponse({ status: 404, description: 'Link not found' })
  async revokeShareableLink(
    @Param('id') id: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.shareService.revokeShareableLink(userId, id);
  }
}
