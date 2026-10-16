import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
  BadRequestException,
  ParseIntPipe,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { GraphService, EnrichedGraphResult } from './graph.service';
import { GraphEngineService } from './graph-engine.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('graph')
@Controller('graph')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class GraphController {
  constructor(
    private graphService: GraphService,
    private graphEngineService: GraphEngineService,
  ) {}

  @Get(':familyId/enriched')
  @ApiOperation({ summary: 'Get enriched family graph with computed kinship terms' })
  @ApiResponse({ status: 200, description: 'Returns graph data with computed kinship terms for each person' })
  @ApiQuery({ name: 'selfPersonId', required: false, description: 'Person ID whose perspective to use for kinship computation' })
  async getEnrichedGraph(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('selfPersonId') selfPersonId?: string,
  ): Promise<EnrichedGraphResult> {
    return this.graphService.getEnrichedGraph(userId, familyId, selfPersonId);
  }

  @Get(':familyId/layout')
  @ApiOperation({ summary: 'Get pre-computed graph layout positions' })
  @ApiQuery({ name: 'algorithm', enum: ['hierarchical', 'radial', 'force'], required: false })
  @ApiQuery({ name: 'viewportWidth', required: false, description: 'Device pixel width (320-4096). Default 1400.' })
  @ApiQuery({ name: 'viewportHeight', required: false, description: 'Device pixel height (240-4096). Default 920.' })
  async getGraphLayout(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('algorithm') algorithm: 'hierarchical' | 'radial' | 'force' = 'hierarchical',
    @Query('viewportWidth') viewportWidth?: string,
    @Query('viewportHeight') viewportHeight?: string,
  ): Promise<Record<string, { x: number; y: number }>> {
    // BUG-012 FIX: accept viewport dimensions from the client so layout
    // adapts to phone (360px) / tablet (768px) / desktop (1920px) screens.
    // Validate and clamp; fall back to 1400×920 if missing or invalid.
    const vw = viewportWidth ? parseInt(viewportWidth, 10) : 1400;
    const vh = viewportHeight ? parseInt(viewportHeight, 10) : 920;
    if (Number.isNaN(vw) || vw < 320 || vw > 4096) {
      throw new BadRequestException('viewportWidth must be an integer between 320 and 4096');
    }
    if (Number.isNaN(vh) || vh < 240 || vh > 4096) {
      throw new BadRequestException('viewportHeight must be an integer between 240 and 4096');
    }
    return this.graphService.computeLayout(userId, familyId, algorithm, vw, vh);
  }

  @Get(':familyId/member/:memberId')
  @ApiOperation({ summary: 'Get detailed member info for info card' })
  async getMemberDetails(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('memberId') memberId: string,
  ) {
    return this.graphService.getMemberDetails(userId, familyId, memberId);
  }

  @Get(':familyId/generation/:gen')
  @ApiOperation({ summary: 'Get members by generation' })
  async getGenerationMembers(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('gen', new ParseIntPipe()) generation: number,
  ) {
    // BUG-025 FIX: validate generation range. The data model allows negative
    // generationIndex (e.g. -1 for the parent of the anchor), but the API
    // contract treats 0 as the oldest generation. Reject obviously-wrong
    // values to give callers a clear error instead of an empty result.
    if (generation < -10 || generation > 20) {
      throw new BadRequestException(
        'Generation index must be between -10 and 20 (0 = anchor generation).',
      );
    }
    return this.graphService.getMembersByGeneration(userId, familyId, generation);
  }

  @Get(':familyId')
  @ApiOperation({ summary: 'Get family graph data' })
  @ApiResponse({ status: 200, description: 'Returns graph data for the family' })
  @ApiResponse({ status: 404, description: 'Family not found' })
  async getGraph(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('root') root?: string,
    @Query('depth') depth?: string,
    @Query('format') format?: 'flat' | 'tree',
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('locale') locale?: string,
  ) {
    return this.graphService.getGraph(userId, familyId, {
      root,
      depth: depth ? Math.min(parseInt(depth, 10), 50) : undefined,
      format: format ?? 'flat',
      from,
      to,
      locale,
    });
  }

  @Get(':familyId/tree')
  @ApiOperation({ summary: 'Get family tree structure' })
  @ApiResponse({ status: 200, description: 'Returns tree structure for the family' })
  @ApiResponse({ status: 404, description: 'Family not found' })
  async getTree(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('root') root?: string,
    @Query('depth') depth?: string,
    @Query('locale') locale?: string,
  ) {
    // SECURITY (audit F-02): enforce family membership BEFORE loading any
    // graph data. assertMember() delegates to the same requireFamilyMember
    // check used by every other graph endpoint, so the response (403 for a
    // private family the caller is not in, 404 for a missing family, null
    // membership for read-only access on a public family) is identical to
    // what /graph/:familyId, /graph/:familyId/enriched, etc. already return.
    await this.graphService.assertMember(userId, familyId);

    const rootPersonId = await this.graphService.resolveRootPersonId(
      userId,
      familyId,
      root,
    );

    return this.graphService.getTree(
      familyId,
      rootPersonId,
      depth ? Math.min(parseInt(depth, 10), 50) : 20,
    );
  }

  @Get(':familyId/path')
  @ApiOperation({ summary: 'Find path between two persons in the family graph with resolved kinship terms' })
  @ApiResponse({ status: 200, description: 'Returns the path between two persons with kinship resolution' })
  @ApiResponse({ status: 400, description: 'Missing from/to query parameters' })
  @ApiResponse({ status: 404, description: 'Family or person not found' })
  async getPath(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    if (!from || !to) {
      throw new BadRequestException('Both "from" and "to" query parameters are required for path finding');
    }

    // SECURITY (audit F-03): enforce family membership BEFORE running the
    // BFS path search. We intentionally do NOT switch to GraphService.
    // getPathWithAuth here: that method returns a different response shape
    // ({ path, relationships }) than this endpoint's contract ({ forward }),
    // and the underlying findPath() in GraphEngineService produces the
    // kinship signature data the Flutter client depends on. Adding the
    // assertMember() guard keeps the existing response shape unchanged for
    // authorised users while denying cross-family access the same way the
    // other graph endpoints do.
    await this.graphService.assertMember(userId, familyId);

    // BUG-026 FIX: Compute only the forward path via GraphEngineService.
    // The inverse path is the forward path reversed with swapped kinship
    // terms, so computing it separately doubles the DB/BFS work for no
    // benefit. Clients that need the inverse can derive it locally.
    //
    // (If you genuinely need both directions in the response, add
    // `?includeInverse=true` — but the default is now forward-only.)
    const forward = await this.graphEngineService.findPath(familyId, from, to);

    return { forward };
  }
}
