import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
  Req,
  Res,
  Logger,
} from '@nestjs/common';
import { FamilyService } from './family.service';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';
import { ApiKeyGuard } from '@/common/guards/api-key.guard';
import { Scopes } from '@/common/decorators/scopes.decorator';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import type { Request, Response } from 'express';

/**
 * FamilyV1Controller — API v1 routes (API Key Auth)
 *
 * Handles:
 * - GET    /api/v1/families                 — List families (paginated, API key auth, scope: families:read)
 * - POST   /api/v1/families                 — Create family (API key auth, scope: families:write, Idempotency-Key)
 * - GET    /api/v1/families/:familyId       — Get family (scope: families:read, ?include=members,stats)
 * - PATCH  /api/v1/families/:familyId       — Update family (scope: families:write)
 * - DELETE /api/v1/families/:familyId       — Delete family (scope: families:write)
 * - GET    /api/v1/families/:familyId/stats — Family stats (scope: stats:read)
 * - GET    /api/v1/families/:familyId/leaderboard — Leaderboard
 * - GET    /api/v1/families/:familyId/events — List events
 * - POST   /api/v1/families/:familyId/events — Create event
 */
@Controller('v1/families')
@UseGuards(ApiKeyGuard)
export class FamilyV1Controller {
  private readonly logger = new Logger(FamilyV1Controller.name);

  constructor(private readonly familyService: FamilyService) {}

  // ── GET /api/v1/families ─────────────────────────────────────────
  @Get()
  @Scopes('families:read')
  async listFamilies(
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('sort') sort?: string,
    @Query('order') order?: string,
    @Query('search') search?: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.listFamiliesV1(userId, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      sort,
      order,
      search,
    });

    // Add API version header
    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }

  // ── POST /api/v1/families ────────────────────────────────────────
  @Post()
  @Scopes('families:write')
  @HttpCode(HttpStatus.CREATED)
  async createFamily(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateFamilyDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    // Check idempotency
    const idempotencyKey = req.headers['idempotency-key'] as string | undefined;
    if (idempotencyKey) {
      const idemResult = await this.familyService.checkIdempotencyKey(idempotencyKey);
      if (idemResult.isDuplicate && idemResult.response) {
        res.setHeader('X-Idempotent-Replayed', 'true');
        res.setHeader('X-API-Version', '1.0.0');
        res.status(idemResult.response.status);
        return idemResult.response.body;
      }
    }

    const result = await this.familyService.createFamily(userId, dto);

    // Store idempotency response
    if (idempotencyKey) {
      await this.familyService.storeIdempotencyResponse(
        idempotencyKey,
        result,
        HttpStatus.CREATED,
      );
    }

    res.setHeader('X-API-Version', '1.0.0');
    return result;
  }

  // ── GET /api/v1/families/:familyId ───────────────────────────────
  @Get(':familyId')
  @Scopes('families:read')
  async getFamily(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('include') include?: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.getFamilyV1(familyId, userId, include);

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return { data: result };
  }

  // ── PATCH /api/v1/families/:familyId ─────────────────────────────
  @Patch(':familyId')
  @Scopes('families:write')
  async updateFamily(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateFamilyDto,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.updateFamily(familyId, userId, dto);

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return { data: result };
  }

  // ── DELETE /api/v1/families/:familyId ────────────────────────────
  @Delete(':familyId')
  @Scopes('families:write')
  @HttpCode(HttpStatus.OK)
  async deleteFamily(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.deleteFamily(familyId, userId);

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return { data: result };
  }

  // ── GET /api/v1/families/:familyId/stats ─────────────────────────
  @Get(':familyId/stats')
  @Scopes('stats:read')
  async getFamilyStats(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.getFamilyStats(familyId, userId);

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return { data: result };
  }

  // ── GET /api/v1/families/:familyId/leaderboard ───────────────────
  @Get(':familyId/leaderboard')
  async getFamilyLeaderboard(
    @Param('familyId') familyId: string,
    @Query('period') period?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.getFamilyLeaderboard(familyId, {
      period,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }

  // ── GET /api/v1/families/:familyId/events ────────────────────────
  @Get(':familyId/events')
  async listFamilyEvents(
    @Param('familyId') familyId: string,
    @Query('upcoming') upcoming?: string,
    @Query('eventType') eventType?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.listFamilyEvents(familyId, {
      upcoming: upcoming === 'true',
      eventType,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }

  // ── POST /api/v1/families/:familyId/events ───────────────────────
  @Post(':familyId/events')
  @HttpCode(HttpStatus.CREATED)
  async createFamilyEvent(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: Record<string, unknown>,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.createFamilyEvent(familyId, userId, body);

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }
}
