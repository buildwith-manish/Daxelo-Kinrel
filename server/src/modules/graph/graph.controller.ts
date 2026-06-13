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
  async getGraphLayout(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('algorithm') algorithm: 'hierarchical' | 'radial' | 'force' = 'hierarchical',
  ): Promise<Record<string, { x: number; y: number }>> {
    await this.graphService.resolveRootPersonId(userId, familyId);
    return this.graphService.computeLayout(familyId, algorithm);
  }

  @Get(':familyId/member/:memberId')
  @ApiOperation({ summary: 'Get detailed member info for info card' })
  async getMemberDetails(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('memberId') memberId: string,
  ) {
    await this.graphService.resolveRootPersonId(userId, familyId);
    return this.graphService.getMemberDetails(familyId, memberId);
  }

  @Get(':familyId/generation/:gen')
  @ApiOperation({ summary: 'Get members by generation' })
  async getGenerationMembers(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('gen', new ParseIntPipe()) generation: number,
  ) {
    await this.graphService.resolveRootPersonId(userId, familyId);
    return this.graphService.getMembersByGeneration(familyId, generation);
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

    // Auth check via graphService
    await this.graphService.resolveRootPersonId(userId, familyId);

    // Use GraphEngineService for resolved kinship terms (both forward and inverse)
    const [forward, inverse] = await Promise.all([
      this.graphEngineService.findPath(familyId, from, to),
      this.graphEngineService.findPath(familyId, to, from),
    ]);

    return {
      forward,
      inverse,
    };
  }
}
