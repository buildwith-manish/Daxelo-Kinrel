// =============================================================================
// Track C v2.0 — Kinrel Timeline
// timeline.controller.ts
// =============================================================================
// REST endpoints for the Kinrel Timeline. Section 6.3.
//
// Per the spec: NO PATCH or DELETE endpoints exist by design.
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  Body,
  UseGuards,
  BadRequestException,
  Res,
} from '@nestjs/common';
import { Response } from 'express';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { TimelineService } from './timeline.service';
import { TimelineExporter } from './timeline.exporter';
import { TimelineKind, TIMELINE_KINDS } from './timeline.types';
import { FamilyMembershipService } from '../common/family-membership.service';

@Controller('v1/families/:familyId/timeline')
@UseGuards(JwtAuthGuard)
export class TimelineController {
  constructor(
    private readonly service: TimelineService,
    private readonly exporter: TimelineExporter,
    private readonly membership: FamilyMembershipService,
  ) {}

  @Get()
  async list(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('kind') kind?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
    @Query('raw') raw?: string,
  ) {
    let parsedKind: TimelineKind | TimelineKind[] | undefined;
    if (kind) {
      const kinds = kind.split(',').map((k) => k.trim()) as TimelineKind[];
      for (const k of kinds) {
        if (!TIMELINE_KINDS.includes(k)) {
          throw new BadRequestException(`Invalid timeline kind: ${k}`);
        }
      }
      parsedKind = kinds.length === 1 ? kinds[0] : kinds;
    }

    // raw=true → admin-only full unfiltered log
    // raw absent or raw=false → summary whitelist (all members)
    const isRaw = raw === 'true' || raw === '1';

    return this.service.list(familyId, {
      kind: parsedKind,
      cursor,
      limit: limit ? parseInt(limit, 10) : undefined,
      raw: isRaw,
      userId,
    });
  }

  @Get('export')
  async exportTimeline(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('format') format: 'pdf' | 'json' = 'json',
    @Query('year') year?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Res() res?: Response,
  ) {
    await this.membership.requireMember(userId, familyId);

    if (format === 'json') {
      const data = await this.service.exportJson(familyId, { from, to });
      return data;
    }

    const { html, eventCount } = await this.exporter.exportPdfHtml(familyId, {
      year: year ? parseInt(year, 10) : undefined,
      from,
      to,
    });
    if (res) {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.setHeader('X-Event-Count', String(eventCount));
      res.send(html);
      return;
    }
    return { html, eventCount };
  }

  @Get(':eventId')
  async getOne(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('eventId') eventId: string,
  ) {
    return this.service.getOne(familyId, eventId, userId);
  }

  @Get(':eventId/corrections')
  async getCorrections(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('eventId') eventId: string,
  ) {
    await this.membership.requireMember(userId, familyId);
    return this.service.getCorrections(familyId, eventId);
  }

  @Post(':eventId/correct')
  async correct(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('eventId') eventId: string,
    @Body() body: { correctedFields: Record<string, { from: any; to: any }>; note?: string },
  ) {
    await this.membership.requireAdmin(userId, familyId);

    if (!body?.correctedFields || typeof body.correctedFields !== 'object') {
      throw new BadRequestException('correctedFields is required');
    }
    return this.service.appendCorrection(
      familyId,
      eventId,
      userId,
      body.correctedFields,
      body.note,
    );
  }
}
