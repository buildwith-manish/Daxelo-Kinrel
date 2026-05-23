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
  Res,
} from '@nestjs/common';
import { FamilyService } from './family.service';
import { CreatePersonDto } from './dto/create-person.dto';
import { UpdatePersonDto } from './dto/update-person.dto';
import { JwtAuthGuard } from '@/common/guards/jwt-auth.guard';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import type { Response } from 'express';

/**
 * PersonController — Internal persons sub-routes (JWT Auth)
 *
 * Handles:
 * - GET    /api/families/:familyId/persons               — List persons (paginated)
 * - POST   /api/families/:familyId/persons               — Create person
 * - GET    /api/families/:familyId/persons/:personId     — Get person with relationships
 * - PATCH  /api/families/:familyId/persons/:personId     — Update person
 * - DELETE /api/families/:familyId/persons/:personId     — Soft-delete person
 */
@Controller('families/:familyId/persons')
@UseGuards(JwtAuthGuard)
export class PersonController {
  constructor(private readonly familyService: FamilyService) {}

  // ── GET /api/families/:familyId/persons ──────────────────────────
  @Get()
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
  ) {
    return this.familyService.listPersons(familyId, userId, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      includeRelationships: includeRelationships === 'true',
      deceased,
      search,
      sort,
      order,
    });
  }

  // ── POST /api/families/:familyId/persons ─────────────────────────
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createPerson(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: CreatePersonDto,
  ) {
    return this.familyService.createPerson(familyId, userId, dto);
  }

  // ── GET /api/families/:familyId/persons/:personId ────────────────
  @Get(':personId')
  async getPerson(
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.familyService.getPerson(familyId, personId, userId);
  }

  // ── PATCH /api/families/:familyId/persons/:personId ──────────────
  @Patch(':personId')
  async updatePerson(
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: UpdatePersonDto,
  ) {
    return this.familyService.updatePerson(familyId, personId, userId, dto);
  }

  // ── DELETE /api/families/:familyId/persons/:personId ─────────────
  @Delete(':personId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async deletePerson(
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @CurrentUser('id') userId: string,
    @Res() res: Response,
  ) {
    await this.familyService.deletePerson(familyId, personId, userId);
    return res.send();
  }
}
