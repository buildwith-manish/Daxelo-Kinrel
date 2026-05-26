import { Controller, Get, Post, Delete, Param, Query, Body, UseGuards } from '@nestjs/common';
import { DeveloperService } from './developer.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { CreateKeyDto } from './dto/create-key.dto';
import { RevokeKeyDto } from './dto/revoke-key.dto';
import { CreateWebhookDto } from './dto/create-webhook.dto';
import { ListDeliveriesDto } from './dto/list-deliveries.dto';

@Controller('v1')
export class DeveloperController {
  constructor(private developerService: DeveloperService) {}

  // ── API Keys ────────────────────────────────────────────────────────

  /** GET /api/v1/developer/keys — List user's API keys */
  @Get('developer/keys')
  @UseGuards(JwtAuthGuard)
  async listKeys(@CurrentUser() user: { id: string }) {
    const keys = await this.developerService.listKeys(user.id);
    return { keys };
  }

  /** POST /api/v1/developer/keys — Create API key */
  @Post('developer/keys')
  @UseGuards(JwtAuthGuard)
  async createKey(
    @CurrentUser() user: { id: string },
    @Body() dto: CreateKeyDto,
  ) {
    return this.developerService.createKey(user.id, dto);
  }

  /** DELETE /api/v1/developer/keys/:id — Revoke key */
  @Delete('developer/keys/:id')
  @UseGuards(JwtAuthGuard)
  async revokeKey(
    @Param('id') id: string,
    @CurrentUser() user: { id: string },
    @Body() dto: RevokeKeyDto,
  ) {
    return this.developerService.revokeKey(id, user.id, dto);
  }

  // ── Webhooks ────────────────────────────────────────────────────────

  /** GET /api/v1/webhooks — List user's webhook subscriptions */
  @Get('webhooks')
  @UseGuards(JwtAuthGuard)
  async listWebhooks(
    @CurrentUser() user: { id: string },
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.developerService.listWebhooks(
      user.id,
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
    );
  }

  /** POST /api/v1/webhooks — Create webhook subscription */
  @Post('webhooks')
  @UseGuards(JwtAuthGuard)
  async createWebhook(
    @CurrentUser() user: { id: string },
    @Body() dto: CreateWebhookDto,
  ) {
    return this.developerService.createWebhook(user.id, dto);
  }

  /** GET /api/v1/webhooks/:webhookId/deliveries — List delivery history */
  @Get('webhooks/:webhookId/deliveries')
  @UseGuards(JwtAuthGuard)
  async listDeliveries(
    @Param('webhookId') webhookId: string,
    @CurrentUser() user: { id: string },
    @Query() dto: ListDeliveriesDto,
  ) {
    return this.developerService.listDeliveries(webhookId, user.id, dto);
  }
}
