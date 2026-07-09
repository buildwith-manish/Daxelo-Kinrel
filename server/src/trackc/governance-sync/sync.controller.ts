// =============================================================================
// Track C v2.0 — Governance Sync
// sync.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Query,
  Body,
  Headers,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { SyncDeltaService } from './sync.delta.service';
import { SyncPushService, PushOperation } from './sync.push.service';

@Controller('v1/sync')
@UseGuards(JwtAuthGuard)
export class GovernanceSyncController {
  constructor(
    private readonly deltaService: SyncDeltaService,
    private readonly pushService: SyncPushService,
  ) {}

  @Get('delta')
  delta(
    @CurrentUser('id') userId: string,
    @Headers('x-device-id') deviceId: string,
    @Query('since') since?: string,
    @Query('families') families?: string,
    @Query('limit') limit?: string,
  ) {
    if (!deviceId) throw new BadRequestException('X-Device-Id header is required');
    return this.deltaService.getDelta({
      userId,
      deviceId,
      since,
      families: families?.split(',').filter(Boolean),
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Post('push')
  push(
    @CurrentUser('id') userId: string,
    @Body() body: { operations: PushOperation[] },
  ) {
    if (!body?.operations?.length) throw new BadRequestException('operations must be non-empty');
    return this.pushService.push({ userId, operations: body.operations });
  }
}
