import { Controller, Get, Post, Body, Query, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { KinshipService } from './kinship.service';
import { KinshipQueryDto } from './dto/kinship-query.dto';
import { GraphEngineService, KinshipSignature } from '../graph/graph-engine.service';
import { CanonicalIdService, CanonicalResolution } from './canonical-id.service';
import { RelationshipNormalizerService, NormalizationResult } from './relationship-normalizer.service';

@ApiTags('kinship')
@Controller('v1/kinship')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class KinshipController {
  constructor(
    private readonly kinshipService: KinshipService,
    private readonly graphEngineService: GraphEngineService,
    private readonly canonicalIdService: CanonicalIdService,
    private readonly normalizerService: RelationshipNormalizerService,
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

  // ── v4.1 NEW ENDPOINTS (issue #3 fix — vocabulary data) ──────────────

  /**
   * v4.1: GET /v1/kinship/vocab/browse
   * Browse the full 9,552-row vocabulary (replaces the 51-entry array).
   */
  @Get('vocab/browse')
  async vocabBrowse(
    @Query('lang') lang: string = 'en',
    @Query('category') category?: string,
    @Query('limit') limit?: string,
  ) {
    const parsedLimit = limit ? parseInt(limit, 10) : 100;
    return this.kinshipService.browseVocabulary({
      languageCode: lang,
      category,
      limit: parsedLimit,
    });
  }

  /**
   * v4.1: GET /v1/kinship/vocab/stats
   * Returns vocabulary statistics — useful for /health and admin dashboards.
   */
  @Get('vocab/stats')
  async vocabStats() {
    return this.kinshipService.vocabularyStats();
  }

  // ── v3.0 NEW ENDPOINTS (spec §4 + §8 + §10) ──────────────────────────

  /**
   * v3.0 §4: GET /v1/kinship/canonical
   * Maps a user-input kinship term to its Canonical Relationship ID.
   *
   * Query: term (e.g. "appa"), locale (e.g. "ta")
   * Returns: CanonicalResolution with canonicalId + direction + englishLabel
   */
  @Get('canonical')
  async canonicalize(
    @Query('term') term: string,
    @Query('locale') locale: string = 'en',
  ): Promise<CanonicalResolution> {
    return this.canonicalIdService.normalizeToCanonical(term, locale);
  }

  /**
   * v3.0 §8: GET /v1/kinship/normalize
   * Maps a user-input kinship term to the fundamental edge to store.
   *
   * Query: term (e.g. "wife"), locale (e.g. "en")
   * Returns: NormalizationResult with fundamentalEdge + direction + isDerived
   *          For derived terms, missingEdges describes what to add instead.
   */
  @Get('normalize')
  async normalize(
    @Query('term') term: string,
    @Query('locale') locale: string = 'en',
  ): Promise<NormalizationResult> {
    return this.normalizerService.normalize(term, locale);
  }

  /**
   * v3.0 §10: GET /v1/kinship/auto-detect
   * Auto-detect the relationship between two persons in a family.
   *
   * Implements the full auto-detection workflow:
   *   1. Build shortest path (BFS, max depth 8) between personA and personB.
   *   2. Build KinshipSignature from the path.
   *   3. Resolve the term via Vocabulary Mapper.
   *   4. Normalize to fundamental edge (if applicable).
   *   5. Return detected relationship + suggested storage action.
   *
   * If the path doesn't exist (insufficient graph info), returns the
   * list of fundamental edges the user can pick from to start linking.
   */
  @Get('auto-detect')
  async autoDetect(
    @Query('familyId') familyId: string,
    @Query('personAId') personAId: string,
    @Query('personBId') personBId: string,
    @Query('locale') locale: string = 'en',
  ) {
    if (personAId === personBId) {
      return {
        detected: false,
        self: true,
        message: 'Cannot auto-detect a self-relationship.',
        suggestedEdges: this.normalizerService.listFundamentalEdges(),
      };
    }

    // Step 1-2: Find shortest path + build signature
    const pathResult = await this.graphEngineService.findPath(
      familyId,
      personAId,
      personBId,
    );

    if (!pathResult.found || !pathResult.signature) {
      return {
        detected: false,
        self: false,
        message: 'Insufficient graph information to auto-detect a relationship. Please pick a fundamental edge to add.',
        suggestedEdges: this.normalizerService.listFundamentalEdges(),
        canonicalIds: this.canonicalIdService.listFundamentalCanonicalIds(),
        supportedLocales: this.canonicalIdService.listSupportedLocales(),
      };
    }

    // Step 3: Resolve term via Vocabulary Mapper (or engine fallback)
    let term = pathResult.result?.term ?? 'Unknown';
    let termFallback = true;
    if (locale && locale !== 'en') {
      const vocabResult = await this.kinshipService.resolveSignature(
        pathResult.signature,
        locale,
      );
      if (vocabResult) {
        term = vocabResult.term;
        termFallback = false;
      }
    } else {
      // Try English vocab
      const vocabResult = await this.kinshipService.resolveSignature(
        pathResult.signature,
        'en',
      );
      if (vocabResult) {
        term = vocabResult.term;
        termFallback = false;
      }
    }

    // Step 4: Normalize — derive the fundamental edge from the signature
    const fundamentalEdge = pathResult.signature.pathPattern === 'UP_PARENT' || pathResult.signature.pathPattern === 'DOWN_CHILD'
      ? 'parent'
      : pathResult.signature.pathPattern === 'SPOUSE'
        ? 'spouse'
        : pathResult.signature.pathPattern === 'UP_ADOPTIVE_PARENT'
          ? 'adoptive_parent'
          : pathResult.signature.pathPattern === 'UP_STEP_PARENT'
            ? 'step_parent'
            : null;

    // Step 5: Return detected relationship
    return {
      detected: true,
      self: false,
      term,
      termEn: pathResult.result?.term ?? 'Unknown',
      termFallback,
      fundamentalEdge,
      isDerived: fundamentalEdge === null,
      direction:
        pathResult.signature.pathPattern === 'DOWN_CHILD' ? 'reverse'
          : pathResult.signature.pathPattern === 'SPOUSE' ? 'bidirectional'
          : 'forward',
      signature: pathResult.signature,
      path: pathResult.path,
      distance: pathResult.distance,
      suggestedAction: fundamentalEdge
        ? `Add a ${fundamentalEdge} edge from person A to person B to store this relationship.`
        : 'This is a derived relationship — add the underlying fundamental edges (parent/spouse) and the engine will derive this term automatically.',
    };
  }

  /**
   * v3.0 §4: GET /v1/kinship/canonical/languages
   * Returns the list of locales supported by the canonical ID layer.
   */
  @Get('canonical/languages')
  async canonicalLanguages() {
    return {
      locales: this.canonicalIdService.listSupportedLocales(),
      canonicalIds: this.canonicalIdService.listFundamentalCanonicalIds(),
    };
  }
}
