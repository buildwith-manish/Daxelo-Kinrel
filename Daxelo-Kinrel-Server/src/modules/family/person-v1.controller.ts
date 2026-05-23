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
} from '@nestjs/common';
import { FamilyService } from './family.service';
import { CreatePersonDto } from './dto/create-person.dto';
import { UpdatePersonDto } from './dto/update-person.dto';
import { ApiKeyGuard } from '@/common/guards/api-key.guard';
import { Scopes } from '@/common/decorators/scopes.decorator';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import type { Request, Response } from 'express';

/**
 * PersonV1Controller — API v1 persons sub-routes (API Key Auth)
 *
 * Handles:
 * - GET    /api/v1/families/:familyId/persons               — List persons (scope: persons:read)
 * - POST   /api/v1/families/:familyId/persons               — Create person (scope: persons:write, Idempotency-Key)
 * - GET    /api/v1/families/:familyId/persons/:personId     — Get person
 * - PATCH  /api/v1/families/:familyId/persons/:personId     — Update person
 * - DELETE /api/v1/families/:familyId/persons/:personId     — Delete person
 */
@Controller('v1/families/:familyId/persons')
@UseGuards(ApiKeyGuard)
export class PersonV1Controller {
  constructor(private readonly familyService: FamilyService) {}

  // ── GET /api/v1/families/:familyId/persons ───────────────────────
  @Get()
  @Scopes('persons:read')
  async listPersons(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('includeRelationships') includeRelationships?: string,
    @Query('deceased') deceased?: string,
    @Query('search') search?: string,
    @Query('sort') sort?: string,
    @Query('order') order?: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.listPersons(familyId, userId, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      includeRelationships: includeRelationships === 'true',
      deceased,
      search,
      sort,
      order,
    });

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }

  // ── POST /api/v1/families/:familyId/persons ──────────────────────
  @Post()
  @Scopes('persons:write')
  @HttpCode(HttpStatus.CREATED)
  async createPerson(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: CreatePersonDto,
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

    const result = await this.familyService.createPerson(familyId, userId, dto);

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

  // ── GET /api/v1/families/:familyId/persons/:personId ─────────────
  @Get(':personId')
  @Scopes('persons:read')
  async getPerson(
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @CurrentUser('id') userId: string,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.getPerson(familyId, personId, userId);

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return { data: result.data };
  }

  // ── PATCH /api/v1/families/:familyId/persons/:personId ───────────
  @Patch(':personId')
  @Scopes('persons:write')
  async updatePerson(
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: UpdatePersonDto,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.familyService.updatePerson(familyId, personId, userId, dto);

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return { data: result.data };
  }

  // ── DELETE /api/v1/families/:familyId/persons/:personId ──────────
  @Delete(':personId')
  @Scopes('persons:write')
  @HttpCode(HttpStatus.NO_CONTENT)
  async deletePerson(
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @CurrentUser('id') userId: string,
    @Res() res: Response,
  ) {
    await this.familyService.deletePerson(familyId, personId, userId);
    res.setHeader('X-API-Version', '1.0.0');
    return res.send();
  }
}
