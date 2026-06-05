import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { GraphService } from './graph.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('graph')
@Controller('graph')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class GraphController {
  constructor(private graphService: GraphService) {}

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
      format: format || 'flat',
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
      depth ? Math.min(parseInt(depth, 10), 50) : 10,
    );
  }

  @Get(':familyId/path')
  @ApiOperation({ summary: 'Find path between two persons in the family graph' })
  @ApiResponse({ status: 200, description: 'Returns the path between two persons' })
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

    return this.graphService.getPathWithAuth(userId, familyId, from, to);
  }
}
