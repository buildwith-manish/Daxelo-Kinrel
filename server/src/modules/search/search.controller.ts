import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { SearchService } from './search.service';
import { SearchQueryDto } from './dto/search-query.dto';

@Controller('search')
@UseGuards(JwtAuthGuard)
export class SearchController {
  constructor(private readonly searchService: SearchService) {}

  /**
   * Unified search across users and families.
   * Passes the authenticated user's ID for privacy-aware filtering.
   *
   * GET /api/search?q=query&type=all|users|families&limit=20&offset=0
   */
  @Get()
  async search(
    @Query() dto: SearchQueryDto,
    @CurrentUser('id') viewerId: string,
  ) {
    return this.searchService.search(dto, viewerId);
  }
}

