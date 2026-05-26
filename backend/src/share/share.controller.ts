import {
  Controller,
  Get,
  Post,
  Body,
  Query,
  Param,
  Req,
  Res,
  UseGuards,
  HttpCode,
  HttpStatus,
  Header,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { ShareService } from './share.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CreateShareableLinkDto } from './dto/create-shareable-link.dto';

@Controller('share')
export class ShareController {
  constructor(private shareService: ShareService) {}

  /**
   * POST /api/share
   * Create shareable link
   */
  @Post()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createShareableLink(
    @Req() req: Request,
    @Body() dto: CreateShareableLinkDto,
  ) {
    const userId = (req as any).user?.id ?? req.headers['x-user-id'] as string;
    return this.shareService.createShareableLink(userId, dto);
  }

  /**
   * GET /api/share?token=xxx
   * Get share stats
   */
  @Get()
  async getShareStats(@Query('token') token: string) {
    return this.shareService.getShareStats(token);
  }

  /**
   * GET /api/share/:token
   * OG preview HTML page with redirect
   * Returns HTML with OG meta tags, increments viewCount, tracks link tap event
   */
  @Get(':token')
  @Header('Content-Type', 'text/html')
  async getOgPreview(
    @Param('token') token: string,
    @Res() res: Response,
  ) {
    const html = await this.shareService.getOgPreview(token);
    res.send(html);
  }
}
