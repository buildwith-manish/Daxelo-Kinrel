import { Controller, Get, Patch, Param, Query, Body, UseGuards } from '@nestjs/common';
import { KbService } from './kb.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ListArticlesDto } from './dto/list-articles.dto';
import { SearchArticlesDto } from './dto/search-articles.dto';
import { FeedbackDto } from './dto/feedback.dto';

@Controller('kb')
@UseGuards(JwtAuthGuard)
export class KbController {
  constructor(private kbService: KbService) {}

  /** GET /api/kb — List/search KB articles */
  @Get()
  async listArticles(@Query() dto: ListArticlesDto) {
    return this.kbService.listArticles(dto);
  }

  /** GET /api/kb/search — Search with relevance scoring */
  @Get('search')
  async searchArticles(
    @Query() dto: SearchArticlesDto,
    @CurrentUser() user?: { id: string },
  ) {
    return this.kbService.searchArticles(dto, user?.id);
  }

  /** GET /api/kb/articles?slug= — Get article by slug for feedback */
  @Get('articles')
  async getArticleForFeedback(@Query('slug') slug: string, @Query('lang') lang?: string) {
    return this.kbService.getArticleForFeedback(slug, lang);
  }

  /** PATCH /api/kb/articles — Feedback: helpful/not helpful */
  @Patch('articles')
  async submitFeedback(@Body() dto: FeedbackDto) {
    return this.kbService.submitFeedback(dto);
  }

  /** GET /api/kb/:slug — Get article by slug */
  @Get(':slug')
  async getArticleBySlug(
    @Param('slug') slug: string,
    @Query('lang') lang?: string,
  ) {
    return this.kbService.getArticleBySlug(slug, lang);
  }
}
