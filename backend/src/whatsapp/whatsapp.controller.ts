import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Body,
  Query,
  Req,
  Res,
  UseGuards,
  HttpCode,
  HttpStatus,
  Header,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { WhatsAppService } from './whatsapp.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { OptInDto } from './dto/opt-in.dto';
import { OptOutDto } from './dto/opt-out.dto';
import { UpdateMarketingConsentDto } from './dto/update-marketing-consent.dto';
import { TrackAnalyticsEventDto } from './dto/track-analytics-event.dto';

@Controller('whatsapp')
export class WhatsAppController {
  constructor(private whatsappService: WhatsAppService) {}

  // ── Consent Management ──────────────────────────────────────────

  /**
   * GET /api/whatsapp/consent?userId=xxx
   */
  @Get('consent')
  @UseGuards(JwtAuthGuard)
  async getConsent(@Query('userId') userId: string) {
    return this.whatsappService.getConsent(userId);
  }

  /**
   * POST /api/whatsapp/consent — Opt-in
   */
  @Post('consent')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async optIn(@Body() dto: OptInDto) {
    return this.whatsappService.optIn(dto);
  }

  /**
   * PUT /api/whatsapp/consent — Opt-out
   */
  @Put('consent')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async optOut(@Body() dto: OptOutDto) {
    return this.whatsappService.optOut(dto);
  }

  /**
   * PATCH /api/whatsapp/consent — Update marketing consent
   */
  @Patch('consent')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async updateMarketingConsent(@Body() dto: UpdateMarketingConsentDto) {
    return this.whatsappService.updateMarketingConsent(dto);
  }

  // ── Webhook ──────────────────────────────────────────────────────

  /**
   * GET /api/whatsapp/webhook — Webhook verification
   */
  @Get('webhook')
  @Header('Content-Type', 'text/plain')
  verifyWebhook(
    @Query('hub.mode') mode: string,
    @Query('hub.verify_token') token: string,
    @Query('hub.challenge') challenge: string,
    @Res() res: Response,
  ) {
    const result = this.whatsappService.verifyWebhook(mode, token, challenge);
    res.send(result);
  }

  /**
   * POST /api/whatsapp/webhook — Incoming message handler
   */
  @Post('webhook')
  @HttpCode(HttpStatus.OK)
  async handleWebhook(@Req() req: Request) {
    const rawBody = req.body ? JSON.stringify(req.body) : '';
    const signature = req.headers['x-hub-signature-256'] as string ?? '';
    return this.whatsappService.handleWebhook(rawBody, signature);
  }

  // ── Analytics ────────────────────────────────────────────────────

  /**
   * GET /api/whatsapp/analytics?event=&userId=&templateId=&startDate=&endDate=&limit=100
   */
  @Get('analytics')
  @UseGuards(JwtAuthGuard)
  async getAnalytics(
    @Query('event') event?: string,
    @Query('userId') userId?: string,
    @Query('templateId') templateId?: string,
    @Query('startDate') startDate?: string,
    @Query('endDate') endDate?: string,
    @Query('limit') limitStr?: string,
  ) {
    const limit = limitStr ? parseInt(limitStr, 10) : 100;
    return this.whatsappService.getAnalytics({
      event,
      userId,
      templateId,
      startDate,
      endDate,
      limit,
    });
  }

  /**
   * POST /api/whatsapp/analytics — Track event
   */
  @Post('analytics')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async trackEvent(@Body() dto: TrackAnalyticsEventDto) {
    return this.whatsappService.trackEvent(dto);
  }
}
