import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { KinshipService } from './kinship.service';
import { KinshipQueryDto } from './dto/kinship-query.dto';

@Controller('v1/kinship')
@UseGuards(JwtAuthGuard)
export class KinshipController {
  constructor(private readonly kinshipService: KinshipService) {}

  @Get()
  async lookup(@Query() query: KinshipQueryDto) {
    return this.kinshipService.lookup(query);
  }

  @Get('search')
  async search(
    @Query('term') term: string,
    @Query('lang') lang: string,
    @Query('limit') limit = '20',
  ) {
    return this.kinshipService.searchByTermAndLang(term, lang, parseInt(limit));
  }

  @Get('languages')
  async getLanguages() {
    return this.kinshipService.getSupportedLanguages();
  }
}
