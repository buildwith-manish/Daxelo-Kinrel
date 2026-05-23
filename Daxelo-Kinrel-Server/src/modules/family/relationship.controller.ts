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
  Res,
} from '@nestjs/common';
import { FamilyService } from './family.service';
import { CreateRelationshipDto } from './dto/create-relationship.dto';
import { JwtAuthGuard } from '@/common/guards/jwt-auth.guard';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import type { Response } from 'express';

/**
 * RelationshipController — Internal relationships sub-routes (JWT Auth)
 *
 * Handles:
 * - GET    /api/families/:familyId/relationships     — List relationships
 * - POST   /api/families/:familyId/relationships     — Create relationship (auto-creates inverse)
 * - DELETE /api/families/:familyId/relationships     — Delete relationship (and inverse)
 */
@Controller('families/:familyId/relationships')
@UseGuards(JwtAuthGuard)
export class RelationshipController {
  constructor(private readonly familyService: FamilyService) {}

  // ── GET /api/families/:familyId/relationships ────────────────────
  @Get()
  async listRelationships(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('personId') personId?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.familyService.listRelationships(familyId, userId, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      personId,
    });
  }

  // ── POST /api/families/:familyId/relationships ───────────────────
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createRelationship(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: CreateRelationshipDto,
  ) {
    return this.familyService.createRelationship(familyId, userId, dto);
  }

  // ── DELETE /api/families/:familyId/relationships ─────────────────
  @Delete()
  @HttpCode(HttpStatus.NO_CONTENT)
  async deleteRelationship(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('id') relationshipId: string,
    @Res() res: Response,
  ) {
    if (!relationshipId) {
      res.status(HttpStatus.BAD_REQUEST).json({
        error: 'Relationship ID is required as query parameter "?id=xxx"',
      });
      return;
    }
    await this.familyService.deleteRelationship(familyId, userId, relationshipId);
    return res.send();
  }
}
