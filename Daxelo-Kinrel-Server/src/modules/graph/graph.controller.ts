import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
  Logger,
  Res,
} from '@nestjs/common';
import { GraphService } from './graph.service';
import { GraphQueryDto, TreeQueryDto, PathQueryDto } from './dto/graph-query.dto';
import { DualAuthGuard } from '@/common/guards/dual-auth.guard';
import { ApiKeyGuard } from '@/common/guards/api-key.guard';
import { Scopes } from '@/common/decorators/scopes.decorator';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import type { Response } from 'express';

/**
 * GraphController — /api/v1/graph/:familyId
 *
 * Unified graph endpoint supporting both JWT session and API key auth.
 * If `from` + `to` query params present → path mode
 * Otherwise → tree mode
 *
 * Dual auth: JWT Session OR API Key (scope: graph:read)
 */
@Controller('v1/graph')
export class GraphController {
  private readonly logger = new Logger(GraphController.name);

  constructor(private readonly graphService: GraphService) {}

  // ── GET /api/v1/graph/:familyId ──────────────────────────────────
  @Get(':familyId')
  @UseGuards(DualAuthGuard)
  async getGraph(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query() dto: GraphQueryDto,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.graphService.getGraph(familyId, userId, {
      from: dto.from,
      to: dto.to,
      root: dto.root,
      depth: dto.depth,
      format: dto.format,
      locale: dto.locale,
    });

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }
}

/**
 * GraphTreeController — /api/v1/graph/:familyId/tree
 * API key auth, scope: graph:read
 */
@Controller('v1/graph')
export class GraphTreeController {
  private readonly logger = new Logger(GraphTreeController.name);

  constructor(private readonly graphService: GraphService) {}

  // ── GET /api/v1/graph/:familyId/tree ─────────────────────────────
  @Get(':familyId/tree')
  @UseGuards(ApiKeyGuard)
  @Scopes('graph:read')
  async getTree(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query() dto: TreeQueryDto,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.graphService.getTree(familyId, userId, {
      depth: dto.depth,
      includeDeceased: dto.includeDeceased !== 'false',
      format: dto.format,
    });

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }
}

/**
 * GraphPathController — /api/v1/graph/:familyId/path
 * API key auth, scope: graph:read
 */
@Controller('v1/graph')
export class GraphPathController {
  private readonly logger = new Logger(GraphPathController.name);

  constructor(private readonly graphService: GraphService) {}

  // ── GET /api/v1/graph/:familyId/path ─────────────────────────────
  @Get(':familyId/path')
  @UseGuards(ApiKeyGuard)
  @Scopes('graph:read')
  async getPath(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query() dto: PathQueryDto,
    @Res({ passthrough: true }) res?: Response,
  ) {
    const result = await this.graphService.getPath(
      familyId,
      userId,
      dto.from,
      dto.to,
    );

    if (res) {
      res.setHeader('X-API-Version', '1.0.0');
    }

    return result;
  }
}
