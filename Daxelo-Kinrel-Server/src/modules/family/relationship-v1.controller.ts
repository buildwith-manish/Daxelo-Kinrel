import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
  Req,
  Res,
} from '@nestjs/common';
import { FamilyService } from './family.service';
import { CreateRelationshipDto } from './dto/create-relationship.dto';
import { ApiKeyGuard } from '@/common/guards/api-key.guard';
import { Scopes } from '@/common/decorators/scopes.decorator';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import type { Request, Response } from 'express';

/**
 * RelationshipV1Controller — API v1 relationships sub-routes (API Key Auth)
 *
 * Handles:
 * - GET    /api/v1/families/:familyId/relationships     — List relationships (scope: persons:read)
 * - POST   /api/v1/families/:familyId/relationships     — Create relationship (scope: persons:write, Idempotency-Key)
 * - DELETE /api/v1/families/:familyId/relationships     — Delete relationship (scope: persons:write)
 */
@Controller('v1/families/:familyId/relationships')
@UseGuards(ApiKeyGuard)
export class RelationshipV1Controller {
  constructor(private readonly familyService: FamilyService) {}

  // ── GET /api/v1/families/:familyId/relationships ─────────────────
  @Get()
  @Scopes('persons:read')
  async listRelationships(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('personId') personId?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.listRelationships(familyId, userId, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      personId,
    });

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }

  // ── POST /api/v1/families/:familyId/relationships ────────────────
  @Post()
  @Scopes('persons:write')
  @HttpCode(HttpStatus.CREATED)
  async createRelationship(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: CreateRelationshipDto,
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

    const result = await this.familyService.createRelationship(familyId, userId, dto);

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

  // ── DELETE /api/v1/families/:familyId/relationships ──────────────
  @Delete()
  @Scopes('persons:write')
  @HttpCode(HttpStatus.NO_CONTENT)
  async deleteRelationship(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('id') relationshipId: string,
    @Res() res: Response,
  ) {
    if (!relationshipId) {
      res.status(HttpStatus.BAD_REQUEST).json({
        error: {
          code: 'MISSING_REQUIRED_FIELD',
          message: 'Relationship ID is required as query parameter "?id=xxx"',
        },
      });
      return;
    }

    await this.familyService.deleteRelationship(familyId, userId, relationshipId);
    res.setHeader('X-API-Version', '1.0.0');
    return res.send();
  }
}
