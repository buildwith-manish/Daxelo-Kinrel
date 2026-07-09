// =============================================================================
// Track C v2.0 — AURA Governance: Decisions
// decisions.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Patch,
  Param,
  Body,
  Query,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { DecisionsService, CreateDecisionInput } from './decisions.service';

@Controller('v1/families/:familyId/decisions')
@UseGuards(JwtAuthGuard)
export class DecisionsController {
  constructor(private readonly service: DecisionsService) {}

  @Get()
  list(
    @Param('familyId') familyId: string,
    @Query('status') status?: string,
    @Query('lifecycleState') lifecycleState?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    return this.service.list(familyId, {
      status,
      lifecycleState,
      cursor,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Post()
  create(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: CreateDecisionInput,
  ) {
    if (!body?.type) throw new BadRequestException('type is required');
    return this.service.create(familyId, userId, body);
  }

  @Get(':decisionId')
  getOne(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
  ) {
    return this.service.getOne(familyId, decisionId);
  }

  @Patch(':decisionId')
  patch(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { title?: string; description?: string; deadlineAt?: string },
  ) {
    return this.service.patch(familyId, decisionId, userId, body);
  }

  @Post(':decisionId/vote')
  vote(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { option: string },
  ) {
    if (!body?.option) throw new BadRequestException('option is required');
    return this.service.vote(familyId, decisionId, userId, body.option);
  }

  @Post(':decisionId/resolve')
  resolve(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { resolutionNote?: string },
  ) {
    return this.service.resolve(familyId, decisionId, userId, body?.resolutionNote);
  }

  @Post(':decisionId/cancel')
  cancel(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.cancel(familyId, decisionId, userId);
  }

  @Patch(':decisionId/lifecycle')
  transitionLifecycle(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { to: string },
  ) {
    if (!body?.to) throw new BadRequestException('to is required');
    return this.service.transitionLifecycle(familyId, decisionId, userId, body.to);
  }

  // ── Memory + Impact ────────────────────────────────────────────────────

  @Get(':decisionId/memory')
  getMemory(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
  ) {
    return this.service.getMemory(familyId, decisionId);
  }

  @Post(':decisionId/memory')
  upsertMemory(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
    @Body() body: any,
  ) {
    return this.service.upsertMemory(familyId, decisionId, userId, body);
  }

  @Post(':decisionId/impacts')
  addImpact(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
    @Body() body: any,
  ) {
    return this.service.addImpact(familyId, decisionId, userId, body);
  }

  @Patch(':decisionId/impacts/:impactId')
  patchImpact(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @Param('impactId') impactId: string,
    @CurrentUser('id') userId: string,
    @Body() body: any,
  ) {
    return this.service.patchImpact(familyId, decisionId, impactId, userId, body);
  }
}
