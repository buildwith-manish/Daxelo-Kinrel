import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import { GraphService } from './graph.service';
import { DualAuthGuard } from './dual-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';

@Controller('v1/graph')
@UseGuards(DualAuthGuard)
export class GraphController {
  constructor(private graphService: GraphService) {}

  /**
   * GET /api/v1/graph/:familyId
   * Unified graph (tree or path based on query params)
   * If both fromPersonId and toPersonId are provided, returns path.
   * Otherwise, returns tree.
   */
  @Get(':familyId')
  async getUnifiedGraph(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Query('format') format?: 'nested' | 'flat',
    @Query('depth') depth?: string,
    @Query('fromPersonId') fromPersonId?: string,
    @Query('toPersonId') toPersonId?: string,
    @Query('locale') locale?: string,
  ) {
    // If both person IDs are provided, return path
    if (fromPersonId && toPersonId) {
      const pathResult = await this.graphService.findPath(
        familyId,
        user.id,
        fromPersonId,
        toPersonId,
        locale || 'en',
      );
      return { data: pathResult };
    }

    // Otherwise, return tree
    const treeResult = await this.graphService.buildTree(familyId, user.id, {
      format: format || 'nested',
      depth: depth ? parseInt(depth, 10) : undefined,
    });
    return { data: treeResult };
  }

  /**
   * GET /api/v1/graph/:familyId/tree
   * Family tree (nested or flat format)
   * Response: { data: { familyId, format, depth, tree|nodes, totalNodes } }
   */
  @Get(':familyId/tree')
  async getTree(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Query('format') format?: 'nested' | 'flat',
    @Query('depth') depth?: string,
  ) {
    const result = await this.graphService.buildTree(familyId, user.id, {
      format: format || 'nested',
      depth: depth ? parseInt(depth, 10) : undefined,
    });
    return { data: result };
  }

  /**
   * GET /api/v1/graph/:familyId/path
   * Shortest path between two persons
   * Response: { data: { from, to, path, length, relationshipDescription, localizedDescription, locale } }
   */
  @Get(':familyId/path')
  async getPath(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Query('fromPersonId') fromPersonId: string,
    @Query('toPersonId') toPersonId: string,
    @Query('locale') locale?: string,
  ) {
    const result = await this.graphService.findPath(
      familyId,
      user.id,
      fromPersonId,
      toPersonId,
      locale || 'en',
    );
    return { data: result };
  }
}
