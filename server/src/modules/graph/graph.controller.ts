import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { GraphService } from './graph.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('graph')
@UseGuards(JwtAuthGuard)
export class GraphController {
  constructor(private graphService: GraphService) {}

  @Get(':familyId')
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
      depth: depth ? parseInt(depth, 10) : undefined,
      format: format || 'flat',
      from,
      to,
      locale,
    });
  }

  @Get(':familyId/tree')
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
      depth ? parseInt(depth, 10) : 10,
    );
  }

  @Get(':familyId/path')
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
