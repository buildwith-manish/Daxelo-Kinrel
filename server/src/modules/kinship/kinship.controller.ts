import { Controller, Get, Post, Body, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { KinshipService } from './kinship.service';
import { KinshipQueryDto } from './dto/kinship-query.dto';
import { GraphEngineService, KinshipSignature } from '../graph/graph-engine.service';

@Controller('v1/kinship')
@UseGuards(JwtAuthGuard)
export class KinshipController {
  constructor(
    private readonly kinshipService: KinshipService,
    private readonly graphEngineService: GraphEngineService,
  ) {}

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

  /**
   * v4.0: POST /v1/kinship/resolve
   * Resolves a KinshipSignature to a kinship term from the 5,396+
   * vocabulary database.
   *
   * Body: { signature: KinshipSignature, locale: string }
   * Response: { term: string, termEn: string, fallback: boolean }
   */
  @Post('resolve')
  async resolveSignature(@Body() body: { signature: KinshipSignature; locale?: string }) {
    const { signature, locale = 'en' } = body;

    // Try the vocabulary database first
    const result = await this.kinshipService.resolveSignature(signature, locale);

    if (result) {
      return { term: result.term, termEn: result.termEn, fallback: false };
    }

    // Fallback: use the engine's local mapper
    const fallbackTerm = this.graphEngineService['resolveTerm'](signature);
    return { term: fallbackTerm, termEn: fallbackTerm, fallback: true };
  }

  /**
   * v4.0: GET /v1/kinship/resolve-between
   * Resolves the kinship between two persons in a family.
   *
   * Query: familyId, fromPersonId, toPersonId
   * Response: KinshipResult
   */
  @Get('resolve-between')
  async resolveBetween(
    @Query('familyId') familyId: string,
    @Query('fromPersonId') fromPersonId: string,
    @Query('toPersonId') toPersonId: string,
    @Query('locale') locale?: string,
  ) {
    const result = await this.graphEngineService.resolveKinship(
      familyId,
      fromPersonId,
      toPersonId,
    );

    if (!result) {
      return { found: false, result: null };
    }

    // Try vocabulary database for the localized term
    if (locale && locale !== 'en') {
      const vocabResult = await this.kinshipService.resolveSignature(result.signature, locale);
      if (vocabResult) {
        return {
          found: true,
          result: { ...result, term: vocabResult.term },
        };
      }
    }

    return { found: true, result };
  }

  /**
   * v4.0: GET /v1/kinship/suggest-spouse
   * Checks if two persons share children and suggests a spouse relationship.
   */
  @Get('suggest-spouse')
  async suggestSpouse(
    @Query('familyId') familyId: string,
    @Query('personAId') personAId: string,
    @Query('personBId') personBId: string,
  ) {
    const result = await this.graphEngineService.suggestSpouseIfSharedChildren(
      familyId,
      personAId,
      personBId,
    );
    return { suggested: result !== null, result };
  }
}
