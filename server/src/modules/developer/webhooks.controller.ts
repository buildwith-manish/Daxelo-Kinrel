import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { DeveloperService } from './developer.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('v1/webhooks')
@UseGuards(JwtAuthGuard)
export class WebhooksController {
  constructor(private readonly developerService: DeveloperService) {}

  /**
   * GET /api/v1/webhooks
   * List user's webhooks.
   */
  @Get()
  async listWebhooks(@CurrentUser('id') userId: string) {
    return this.developerService.listWebhooks(userId);
  }

  /**
   * POST /api/v1/webhooks
   * Create a new webhook.
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createWebhook(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      url: string;
      events: string[];
      description?: string;
    },
  ) {
    return this.developerService.createWebhook(userId, body);
  }

  /**
   * GET /api/v1/webhooks/:webhookId/deliveries
   * Get delivery log for a webhook.
   */
  @Get(':webhookId/deliveries')
  async getWebhookDeliveries(
    @CurrentUser('id') userId: string,
    @Param('webhookId') webhookId: string,
  ) {
    return this.developerService.getWebhookDeliveries(webhookId, userId);
  }
}
