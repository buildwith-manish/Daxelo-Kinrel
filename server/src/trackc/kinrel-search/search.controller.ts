// =============================================================================
// Track C v2.0 — Kinrel Search
// search.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { SearchService } from './search.service';
import { FamilyMembershipService } from '../common/family-membership.service';

@Controller('v1/families/:familyId/search')
@UseGuards(JwtAuthGuard)
export class SearchController {
  constructor(
    private readonly service: SearchService,
    private readonly membership: FamilyMembershipService,
  ) {}

  @Get()
  search(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('q') q: string,
    @Query('entityType') entityType?: string,
    @Query('limit') limit?: string,
  ) {
    if (!q) throw new BadRequestException('q is required');
    return this.service.search({
      familyId,
      userId,
      query: q,
      entityType: entityType as any,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Get('suggest')
  suggest(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('q') q: string,
  ) {
    return this.service.suggest({ familyId, userId, q: q ?? '' });
  }

  @Post('reindex')
  async reindex(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    await this.membership.requireAdmin(userId, familyId);
    return this.service.reindexFamily(familyId);
  }
}
