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
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { WhatsAppService } from './whatsapp.service';
import { OptInDto, OptOutDto, MarketingToggleDto } from './dto/consent.dto';

/**
 * WhatsAppController
 *
 * Routes:
 * - GET    /api/whatsapp/webhook          — Webhook verification
 * - POST   /api/whatsapp/webhook          — Receive messages (HMAC verified)
 * - GET    /api/whatsapp/analytics        — Query analytics
 * - POST   /api/whatsapp/analytics        — Log analytics event
 * - GET    /api/whatsapp/consent          — Get consent
 * - POST   /api/whatsapp/consent          — Opt-in
 * - PUT    /api/whatsapp/consent          — Opt-out
 * - PATCH  /api/whatsapp/consent          — Marketing toggle
 */
@Controller('whatsapp')
export class WhatsAppController {
  constructor(private readonly whatsappService: WhatsAppService) {}

  // ── GET /api/whatsapp/webhook — Verification ─────────────────────
  @Get('webhook')
  verifyWebhook(
    @Query('hub.mode') mode: string,
    @Query('hub.verify_token') token: string,
    @Query('hub.challenge') challenge: string,
    @Res() res: Response,
  ) {
    if (mode && token && this.whatsappService.verifyWebhook(mode, token)) {
      res.status(200).send(challenge ?? '');
      return;
    }
    res.status(403).json({ error: 'Invalid verification token or mode' });
  }

  // ── POST /api/whatsapp/webhook — Incoming Messages ───────────────
  @Post('webhook')
  @HttpCode(HttpStatus.OK)
  async receiveWebhook(@Req() req: Request) {
    try {
      // Access raw body via (req as any).rawBody when express json() middleware is configured
      const rawBody = (req as any).rawBody ?? req.body;
      const bodyStr = typeof rawBody === 'string' ? rawBody : JSON.stringify(rawBody);

      const signature = (req.headers['x-hub-signature-256'] as string) ?? '';

      if (!this.whatsappService.verifySignature(bodyStr, signature)) {
        return { error: 'Invalid webhook signature' };
      }

      const payload = typeof rawBody === 'string' ? JSON.parse(rawBody) : rawBody;
      await this.whatsappService.processWebhook(payload);

      return { status: 'ok' };
    } catch (error) {
      // Still return 200 to prevent WhatsApp from retrying
      return { status: 'ok' };
    }
  }

  // ── GET /api/whatsapp/analytics ──────────────────────────────────
  @Get('analytics')
  async getAnalytics(
    @Query('event') event?: string,
    @Query('userId') userId?: string,
    @Query('templateId') templateId?: string,
    @Query('startDate') startDate?: string,
    @Query('endDate') endDate?: string,
    @Query('limit') limit?: string,
  ) {
    return this.whatsappService.getAnalytics({
      event: event || undefined,
      userId: userId || undefined,
      templateId: templateId || undefined,
      startDate: startDate || undefined,
      endDate: endDate || undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  // ── POST /api/whatsapp/analytics ─────────────────────────────────
  @Post('analytics')
  @HttpCode(HttpStatus.CREATED)
  async logAnalyticsEvent(
    @Body() body: {
      event: string;
      userId?: string;
      familyId?: string;
      messageId?: string;
      templateId?: string;
      metadata?: Record<string, unknown>;
    },
  ) {
    return this.whatsappService.logAnalyticsEvent(body);
  }

  // ── GET /api/whatsapp/consent ────────────────────────────────────
  @Get('consent')
  async getConsent(@Query('userId') userId: string) {
    return this.whatsappService.getConsent(userId);
  }

  // ── POST /api/whatsapp/consent — Opt-in ─────────────────────────
  @Post('consent')
  async optIn(@Body() dto: OptInDto) {
    return this.whatsappService.optIn(dto);
  }

  // ── PUT /api/whatsapp/consent — Opt-out ─────────────────────────
  @Put('consent')
  async optOut(@Body() dto: OptOutDto) {
    return this.whatsappService.optOut(dto);
  }

  // ── PATCH /api/whatsapp/consent — Marketing toggle ──────────────
  @Patch('consent')
  async marketingToggle(@Body() dto: MarketingToggleDto) {
    return this.whatsappService.marketingToggle(dto);
  }
}
