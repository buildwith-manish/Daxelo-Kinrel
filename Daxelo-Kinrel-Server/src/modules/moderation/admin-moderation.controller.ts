import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ModerationService } from './moderation.service';
import { CreateRuleDto, ToggleRuleDto } from './dto/rule.dto';

/**
 * AdminModerationController — /api/admin/moderation/*
 *
 * Routes:
 * - GET   /api/admin/moderation/stats  — Moderation stats
 * - GET   /api/admin/moderation/rules   — List rules
 * - POST  /api/admin/moderation/rules   — Create rule
 * - PATCH /api/admin/moderation/rules   — Toggle rule
 */
@Controller('admin/moderation')
export class AdminModerationController {
  constructor(private readonly moderationService: ModerationService) {}

  // ── GET /api/admin/moderation/stats ───────────────────────────────
  @Get('stats')
  async getStats(@Query('userId') userId: string) {
    return this.moderationService.getStats(userId);
  }

  // ── GET /api/admin/moderation/rules ──────────────────────────────
  @Get('rules')
  async listRules(
    @Query('userId') userId: string,
    @Query('category') category?: string,
    @Query('activeOnly') activeOnly?: string,
  ) {
    return this.moderationService.listRules({
      userId,
      category: category || undefined,
      activeOnly: activeOnly === 'true',
    });
  }

  // ── POST /api/admin/moderation/rules ─────────────────────────────
  @Post('rules')
  @HttpCode(HttpStatus.CREATED)
  async createRule(@Body() dto: CreateRuleDto) {
    return this.moderationService.createRule(dto);
  }

  // ── PATCH /api/admin/moderation/rules ────────────────────────────
  @Patch('rules')
  async toggleRule(@Body() dto: ToggleRuleDto) {
    return this.moderationService.toggleRule(dto);
  }
}
