import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  Query,
  Res,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import type { Response } from 'express';
import { DualAuthGuard } from '@/common/guards/dual-auth.guard';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import { ShareService } from './share.service';
import { CreateShareDto } from './dto/create-share.dto';

/**
 * ShareController — /api/share/*
 *
 * Routes:
 * - POST /api/share         — Create shareable link
 * - GET  /api/share         — Get link stats
 * - GET  /api/share/:token  — Resolve share link (returns HTML with OG meta)
 */
@Controller('share')
export class ShareController {
  constructor(private readonly shareService: ShareService) {}

  // ── POST /api/share ──────────────────────────────────────────────
  @Post()
  @UseGuards(DualAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createShareLink(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateShareDto,
  ) {
    return this.shareService.createShareLink(userId, dto);
  }

  // ── GET /api/share ───────────────────────────────────────────────
  @Get()
  async getShareStats(@Query('token') token: string) {
    if (!token) {
      return { error: 'Missing required query parameter: token' };
    }
    return this.shareService.getShareStats(token);
  }

  // ── GET /api/share/:token ────────────────────────────────────────
  @Get(':token')
  async resolveShareLink(
    @Param('token') token: string,
    @Res() res: Response,
  ) {
    const result = await this.shareService.resolveShareLink(token);

    // Check if it's an error JSON or HTML
    if (result.html.startsWith('{')) {
      const parsed = JSON.parse(result.html);
      const statusCode = parsed.error === 'This shareable link has expired' ? 410 : 404;
      res.status(statusCode).json(parsed);
      return;
    }

    res.status(200).setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.send(result.html);
  }
}
