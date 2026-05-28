import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { WhatsAppService } from './whatsapp.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('whatsapp')
@UseGuards(JwtAuthGuard)
export class WhatsAppController {
  constructor(private readonly whatsappService: WhatsAppService) {}

  /**
   * GET /api/whatsapp/consent?userId=xxx
   * Get consent status.
   */
  @Get('consent')
  async getConsent(
    @CurrentUser('id') currentUserId: string,
    @Query('userId') userId?: string,
  ) {
    // Use the queried userId if provided (admin), otherwise use the authenticated user
    const targetUserId = userId || currentUserId;
    return this.whatsappService.getConsent(targetUserId);
  }

  /**
   * POST /api/whatsapp/consent
   * Opt-in to WhatsApp notifications.
   */
  @Post('consent')
  @HttpCode(HttpStatus.CREATED)
  async optIn(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      userId?: string;
      phone: string;
      optInMethod?: string;
      messageCategories?: string[];
    },
  ) {
    const targetUserId = body.userId || userId;
    return this.whatsappService.optIn(targetUserId, {
      phone: body.phone,
      optInMethod: body.optInMethod,
      messageCategories: body.messageCategories,
    });
  }

  /**
   * PUT /api/whatsapp/consent
   * Opt-out of WhatsApp notifications.
   */
  @Put('consent')
  @HttpCode(HttpStatus.OK)
  async optOut(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      userId?: string;
      optOutMethod?: string;
      optOutReason?: string;
    },
  ) {
    const targetUserId = body.userId || userId;
    return this.whatsappService.optOut(targetUserId, {
      optOutMethod: body.optOutMethod,
      optOutReason: body.optOutReason,
    });
  }

  /**
   * PATCH /api/whatsapp/consent
   * Update marketing consent.
   */
  @Patch('consent')
  async updateMarketingConsent(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      marketingConsent: boolean;
    },
  ) {
    return this.whatsappService.updateMarketingConsent(userId, body);
  }

  /**
   * GET /api/whatsapp/analytics
   * Get WhatsApp analytics.
   */
  @Get('analytics')
  async getAnalytics(
    @Query('event') event?: string,
    @Query('startDate') startDate?: string,
    @Query('endDate') endDate?: string,
    @Query('userId') userId?: string,
  ) {
    return this.whatsappService.getAnalytics({
      event,
      startDate,
      endDate,
      userId,
    });
  }

  /**
   * POST /api/whatsapp/analytics
   * Track a WhatsApp event.
   */
  @Post('analytics')
  @HttpCode(HttpStatus.CREATED)
  async trackEvent(
    @Body()
    body: {
      event: string;
      userId?: string;
      familyId?: string;
      messageId?: string;
      templateId?: string;
      metadata?: Record<string, any>;
    },
  ) {
    return this.whatsappService.trackEvent(body);
  }
}
