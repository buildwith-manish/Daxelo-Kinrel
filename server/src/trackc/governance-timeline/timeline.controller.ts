// =============================================================================
// Track C v2.0 — AURA Timeline
// timeline.controller.ts
// =============================================================================
// REST endpoints for the AURA Timeline. Section 6.3.
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

@Controller('api/v1/families/:familyId/timeline')
@UseGuards(JwtAuthGuard)
export class TimelineController {
  constructor(
    private readonly service: TimelineService,
    private readonly exporter: TimelineExporter,
  ) {}

  @Get()
  list(
    @Param('familyId') familyId: string,
    @Query('kind') kind?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    // kind can be a single kind or a CSV of kinds
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

    return this.service.list(familyId, {
      kind: parsedKind,
      cursor,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Get('export')
  async exportTimeline(
    @Param('familyId') familyId: string,
    @Query('format') format: 'pdf' | 'json' = 'json',
    @Query('year') year?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Res() res?: Response,
  ) {
    if (format === 'json') {
      const data = await this.service.exportJson(familyId, { from, to });
      return data;
    }

    // PDF: return print-ready HTML
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
  getOne(
    @Param('familyId') familyId: string,
    @Param('eventId') eventId: string,
  ) {
    return this.service.getOne(familyId, eventId);
  }

  @Get(':eventId/corrections')
  getCorrections(
    @Param('familyId') familyId: string,
    @Param('eventId') eventId: string,
  ) {
    return this.service.getCorrections(familyId, eventId);
  }

  @Post(':eventId/correct')
  async correct(
    @Param('familyId') familyId: string,
    @Param('eventId') eventId: string,
    @CurrentUser('id') actorId: string,
    @Body() body: { correctedFields: Record<string, { from: any; to: any }>; note?: string },
  ) {
    if (!body?.correctedFields || typeof body.correctedFields !== 'object') {
      throw new BadRequestException('correctedFields is required');
    }
    return this.service.appendCorrection(
      familyId,
      eventId,
      actorId,
      body.correctedFields,
      body.note,
    );
  }
}
