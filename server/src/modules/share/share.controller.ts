import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ShareService } from './share.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('share')
export class ShareController {
  constructor(private readonly shareService: ShareService) {}

  /**
   * POST /api/share
   * Create a shareable link (authenticated).
   */
  @Post()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createShareableLink(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      cardType: string;
      familyId?: string;
      personId?: string;
      title: string;
      description?: string;
      deepLinkUrl?: string;
      expiresInDays?: number;
    },
  ) {
    return this.shareService.createShareableLink(userId, body);
  }

  /**
   * GET /api/share?token=xxx
   * Get share stats (authenticated).
   */
  @Get()
  @UseGuards(JwtAuthGuard)
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
  async getSharedCard(@Param('token') token: string) {
    return this.shareService.getSharedCard(token);
  }
}
