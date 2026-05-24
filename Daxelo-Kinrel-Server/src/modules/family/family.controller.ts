import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { FamilyService } from './family.service';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';
import { JwtAuthGuard } from '@/common/guards/jwt-auth.guard';
import { CurrentUser } from '@/common/decorators/current-user.decorator';

/**
 * FamilyController — Internal routes (JWT Auth)
 *
 * Handles:
 * - GET    /api/families              — List user's families
 * - POST   /api/families              — Create family
 * - GET    /api/families/:familyId    — Get family details
 * - PATCH  /api/families/:familyId    — Update family (admin only)
 * - DELETE /api/families/:familyId    — Delete family (admin only)
 */
@Controller('families')
@UseGuards(JwtAuthGuard)
export class FamilyController {
  constructor(private readonly familyService: FamilyService) {}

  // ── GET /api/families ────────────────────────────────────────────
  @Get()
  async listFamilies(@CurrentUser('id') userId: string) {
    return this.familyService.listFamilies(userId);
  }

  // ── POST /api/families ───────────────────────────────────────────
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createFamily(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateFamilyDto,
  ) {
    return this.familyService.createFamily(userId, dto);
  }

  // ── GET /api/families/:familyId ──────────────────────────────────
  @Get(':familyId')
  async getFamily(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.familyService.getFamily(familyId, userId);
  }

  // ── PATCH /api/families/:familyId ────────────────────────────────
  @Patch(':familyId')
  async updateFamily(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateFamilyDto,
  ) {
    return this.familyService.updateFamily(familyId, userId, dto);
  }

  // ── DELETE /api/families/:familyId ───────────────────────────────
  @Delete(':familyId')
  @HttpCode(HttpStatus.OK)
  async deleteFamily(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.familyService.deleteFamily(familyId, userId);
  }
}
