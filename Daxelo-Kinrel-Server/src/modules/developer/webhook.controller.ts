import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  Query,
  Req,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import type { Request } from 'express';
import { ApiKeyGuard } from '@/common/guards/api-key.guard';
import { DeveloperService } from './developer.service';
import { CreateWebhookDto } from './dto/create-webhook.dto';

/**
 * WebhookController — /api/v1/webhooks/*
 *
 * Routes:
 * - GET  /api/v1/webhooks                        — List webhooks
 * - POST /api/v1/webhooks                        — Create webhook
 * - GET  /api/v1/webhooks/:webhookId/deliveries   — List deliveries
 */
@Controller('v1/webhooks')
@UseGuards(ApiKeyGuard)
export class WebhookController {
  constructor(private readonly developerService: DeveloperService) {}

  @Get()
  async listWebhooks(
    @Req() req: Request,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const userId = (req as any).apiKey?.userId;
    if (!userId) return { error: 'Unauthorized' };
    return this.developerService.listWebhooks(userId, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createWebhook(@Req() req: Request, @Body() dto: CreateWebhookDto) {
    const userId = (req as any).apiKey?.userId;
    if (!userId) return { error: 'Unauthorized' };
    return this.developerService.createWebhook(userId, dto);
  }

  @Get(':webhookId/deliveries')
  async listDeliveries(
    @Req() req: Request,
    @Param('webhookId') webhookId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('status') status?: string,
  ) {
    const userId = (req as any).apiKey?.userId;
    if (!userId) return { error: 'Unauthorized' };
    return this.developerService.listDeliveries(userId, webhookId, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      status: status || undefined,
    });
  }
}
