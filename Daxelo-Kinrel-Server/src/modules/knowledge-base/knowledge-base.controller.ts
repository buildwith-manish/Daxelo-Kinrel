import {
  Controller,
  Get,
  Patch,
  Query,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { KnowledgeBaseService } from './knowledge-base.service';
import { KbQueryDto, KbHelpfulDto, KbSearchDto } from './dto/kb-query.dto';

/**
 * KnowledgeBaseController — /api/kb/*
 *
 * Routes:
 * - GET   /api/kb/articles          — List articles
 * - PATCH /api/kb/articles          — Mark helpful
 * - GET   /api/kb/search            — Search
 * - GET   /api/admin/kb/analytics   — KB analytics
 * - GET   /api/admin/sla/report     — SLA report
 */
@Controller('kb')
export class KnowledgeBaseController {
  constructor(private readonly kbService: KnowledgeBaseService) {}

  // ── GET /api/kb/articles ──────────────────────────────────────────
  @Get('articles')
  async listArticles(@Query() query: KbQueryDto) {
    return this.kbService.listArticles(query);
  }

  // ── PATCH /api/kb/articles ───────────────────────────────────────
  @Patch('articles')
  async markHelpful(@Body() dto: KbHelpfulDto) {
    return this.kbService.markHelpful(dto);
  }

  // ── GET /api/kb/search ───────────────────────────────────────────
  @Get('search')
  async search(@Query() query: KbSearchDto) {
    return this.kbService.search(query);
  }
}

/**
 * AdminKBController — /api/admin/kb/*, /api/admin/sla/*
 */
@Controller('admin/kb')
export class AdminKBController {
  constructor(private readonly kbService: KnowledgeBaseService) {}

  // ── GET /api/admin/kb/analytics ──────────────────────────────────
  @Get('analytics')
  async getAnalytics(@Query('days') days?: string) {
    return this.kbService.getAnalytics(parseInt(days ?? '30', 10));
  }
}

@Controller('admin/sla')
export class AdminSlaController {
  constructor(private readonly kbService: KnowledgeBaseService) {}

  // ── GET /api/admin/sla/report ────────────────────────────────────
  @Get('report')
  async getSlaReport(@Query('month') month?: string) {
    const reportMonth = month ?? new Date().toISOString().slice(0, 7); // YYYY-MM
    return this.kbService.getSlaReport(reportMonth);
  }
}
