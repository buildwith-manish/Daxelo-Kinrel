import {
  Controller,
  Get,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { AnalyticsService } from './analytics.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { AdminGuard } from '../common/guards/admin.guard';
import { IsString, IsNotEmpty, IsOptional, IsObject } from 'class-validator';

class TrackEventDto {
  @IsString()
  @IsNotEmpty()
  event: string;

  @IsOptional()
  @IsObject()
  properties?: Record<string, any>;
}

@Controller('analytics')
export class AnalyticsController {
  constructor(private analyticsService: AnalyticsService) {}

  /**
   * POST /api/analytics/event
   * Track an analytics event (auth required, rate limited 100/min)
   */
  @Post('event')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async trackEvent(
    @CurrentUser() user: { id: string },
    @Body() dto: TrackEventDto,
  ) {
    return this.analyticsService.trackEvent(user.id, dto.event, dto.properties);
  }

  /**
   * GET /api/analytics/dashboard
   * Get analytics dashboard data (admin only)
   */
  @Get('dashboard')
  @UseGuards(JwtAuthGuard, AdminGuard)
  async getDashboard() {
    return this.analyticsService.getDashboard();
  }
}
