// =============================================================================
// Track C v2.0 — AURA Analytics
// analytics.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AnalyticsService } from './analytics.service';
import { Granularity } from './analytics.snapshot-worker';

@Controller('api/v1/families/:familyId/analytics')
@UseGuards(JwtAuthGuard)
export class AnalyticsController {
  constructor(private readonly service: AnalyticsService) {}

  @Get('snapshots')
  snapshots(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('granularity') granularity?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    const g = (granularity ?? 'weekly') as Granularity;
    if (!['weekly', 'monthly', 'quarterly'].includes(g)) {
      throw new BadRequestException('granularity must be weekly|monthly|quarterly');
    }
    return this.service.listSnapshots({ familyId, userId, granularity: g, from, to });
  }

  @Get('summary')
  summary(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('granularity') granularity?: string,
  ) {
    const g = (granularity ?? 'weekly') as Granularity;
    return this.service.getSummary(familyId, userId, g);
  }

  @Post('trigger')
  trigger(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('granularity') granularity?: string,
  ) {
    const g = (granularity ?? 'weekly') as Granularity;
    return this.service.triggerSnapshot(familyId, userId, g);
  }
}
