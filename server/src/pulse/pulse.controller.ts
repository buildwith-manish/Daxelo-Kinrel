// server/src/pulse/pulse.controller.ts
//
// PULSE — REST API Controller
//
// Endpoints (all require JWT auth via global JwtAuthGuard):
//   GET    /pulse/today                 — today's brief (or 404 if not generated yet)
//   POST   /pulse/today/generate        — manually generate today's brief on-demand
//   GET    /pulse/:date                 — a specific date's brief (YYYY-MM-DD)
//   GET    /pulse/history               — last N days of briefs (?days=30&limit=30)
//   POST   /pulse/briefs/:briefId/view  — mark brief as viewed (idempotent)
//   POST   /pulse/items/:briefItemId/interact  — record interaction (call/message/etc.)
//   GET    /pulse/weather               — all RelationshipWeather rows for the user
//   GET    /pulse/streaks               — all ConnectionStreak rows for the user
//   GET    /pulse/karma                 — all FamilyKarma rows for the user
//
// All endpoints use @CurrentUser('id') to extract the userId from the JWT.
// Family membership is verified inline in PulseQueryService.

import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Logger,
  NotFoundException,
  Param,
  Post,
  Query,
  ParseIntPipe,
  BadRequestException,
} from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { BriefGeneratorService } from './brief-generator.service';
import { PulseQueryService } from './pulse-query.service';
import { InteractionType } from './brief-types';

@Controller('pulse')
export class PulseController {
  private readonly logger = new Logger(PulseController.name);

  constructor(
    private readonly generator: BriefGeneratorService,
    private readonly query: PulseQueryService,
  ) {}

  // GET /pulse/today
  // Returns today's brief for the authenticated user, or 404 if not generated yet.
  @Get('today')
  async getTodayBrief(@CurrentUser('id') userId: string) {
    const brief = await this.query.getTodayBrief(userId);
    if (!brief) {
      throw new NotFoundException("Today's brief hasn't been generated yet. Try POST /pulse/today/generate.");
    }
    return brief;
  }

  // POST /pulse/today/generate
  // Manually triggers generation of today's brief on-demand.
  // Used by the Flutter client on first launch of the day (lazy generation
  // before the 7am cron fires).
  @Post('today/generate')
  @HttpCode(HttpStatus.OK)
  async generateTodayBrief(@CurrentUser('id') userId: string) {
    const result = await this.generator.generateBriefForUser(userId);
    return result;
  }

  // GET /pulse/history?days=30&limit=30
  // Returns last N days of briefs for browsing.
  @Get('history')
  async getBriefHistory(
    @CurrentUser('id') userId: string,
    @Query('days', new ParseIntPipe({ optional: true })) days?: number,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
  ) {
    return this.query.getBriefHistory(userId, { days, limit });
  }

  // GET /pulse/:date
  // Returns a specific date's brief. Date must be YYYY-MM-DD.
  @Get(':date')
  async getBriefByDate(
    @Param('date') dateStr: string,
    @CurrentUser('id') userId: string,
  ) {
    // Validate date format (YYYY-MM-DD)
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr);
    if (!m) {
      throw new BadRequestException('Date must be YYYY-MM-DD');
    }
    const date = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
    if (isNaN(date.getTime())) {
      throw new BadRequestException('Invalid date');
    }
    const brief = await this.query.getBriefByDate(userId, date);
    if (!brief) {
      throw new NotFoundException(`No brief found for ${dateStr}`);
    }
    return brief;
  }

  // POST /pulse/briefs/:briefId/view
  // Marks the brief as viewed. Idempotent.
  @Post('briefs/:briefId/view')
  @HttpCode(HttpStatus.OK)
  async markBriefViewed(
    @Param('briefId') briefId: string,
    @CurrentUser('id') userId: string,
  ) {
    await this.query.markBriefViewed(briefId, userId);
    return { ok: true };
  }

  // POST /pulse/items/:briefItemId/interact
  // Records a user's interaction with a brief item.
  // Body: { interactionType: 'call'|'message'|'view'|'dismiss'|'skip'|'snooze', data?: {} }
  // Returns: { karmaAwarded: number }
  @Post('items/:briefItemId/interact')
  @HttpCode(HttpStatus.OK)
  async recordInteraction(
    @Param('briefItemId') briefItemId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { interactionType?: string; data?: Record<string, unknown> },
  ) {
    const validTypes: InteractionType[] = [
      'call',
      'message',
      'view',
      'dismiss',
      'skip',
      'snooze',
    ];
    if (!body.interactionType || !validTypes.includes(body.interactionType as InteractionType)) {
      throw new BadRequestException(
        `interactionType must be one of: ${validTypes.join(', ')}`,
      );
    }
    return this.query.recordInteraction(
      briefItemId,
      userId,
      body.interactionType as InteractionType,
      body.data ?? {},
    );
  }

  // GET /pulse/weather
  // Returns all RelationshipWeather rows for the user (across all families).
  @Get('weather')
  async getWeather(@CurrentUser('id') userId: string) {
    return this.query.getWeatherForUser(userId);
  }

  // GET /pulse/streaks
  // Returns all ConnectionStreak rows for the user.
  @Get('streaks')
  async getStreaks(@CurrentUser('id') userId: string) {
    return this.query.getStreaksForUser(userId);
  }

  // GET /pulse/karma
  // Returns all FamilyKarma rows for the user (one per family).
  @Get('karma')
  async getKarma(@CurrentUser('id') userId: string) {
    return this.query.getKarmaForUser(userId);
  }
}
