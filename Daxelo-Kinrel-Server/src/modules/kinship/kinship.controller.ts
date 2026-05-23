import {
  Controller,
  Get,
  Query,
  BadRequestException,
} from '@nestjs/common';
import { KinshipService } from './kinship.service';
import { KinshipQueryDto } from './dto/kinship-query.dto';

/**
 * KinshipController — /api/v1/kinship
 *
 * Handles:
 * - GET /api/v1/kinship          — Meta info (default)
 * - GET /api/v1/kinship?key=xxx   — Single key lookup (?lang=hi optional)
 * - GET /api/v1/kinship?q=xxx     — Search kinship terms
 * - GET /api/v1/kinship?category=xxx — Filter by category
 * - GET /api/v1/kinship?gender=xxx   — Filter by gender
 * - GET /api/v1/kinship?lineage=xxx  — Filter by lineage
 */
@Controller('v1/kinship')
export class KinshipController {
  constructor(private readonly kinshipService: KinshipService) {}

  @Get()
  async query(@Query() dto: KinshipQueryDto) {
    // ── Single key lookup ──────────────────────────────────────────
    if (dto.key) {
      return this.kinshipService.lookupKey(dto.key, dto.lang);
    }

    // ── Search ─────────────────────────────────────────────────────
    if (dto.q) {
      return this.kinshipService.searchKinship(dto.q);
    }

    // ── Category filter ────────────────────────────────────────────
    if (dto.category) {
      return this.kinshipService.getByCategory(dto.category);
    }

    // ── Gender filter ──────────────────────────────────────────────
    if (dto.gender) {
      return this.kinshipService.getByGender(dto.gender);
    }

    // ── Lineage filter ─────────────────────────────────────────────
    if (dto.lineage) {
      return this.kinshipService.getByLineage(dto.lineage);
    }

    // ── Meta info (default — don't return all records) ─────────────
    return this.kinshipService.getMetaInfo();
  }
}
