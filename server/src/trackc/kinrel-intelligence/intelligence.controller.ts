// =============================================================================
// Track C v2.0 — Kinrel Intelligence
// intelligence.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { IntelligenceService, InsightKind } from './intelligence.service';

@Controller('v1')
@UseGuards(JwtAuthGuard)
export class IntelligenceController {
  constructor(private readonly service: IntelligenceService) {}

  @Post('families/:familyId/decisions/:decisionId/insights/request')
  requestInsights(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { kinds: InsightKind[] },
  ) {
    if (!body?.kinds?.length) throw new BadRequestException('kinds must be non-empty');
    return this.service.requestInsights({ familyId, decisionId, kinds: body.kinds, userId });
  }

  @Get('families/:familyId/decisions/:decisionId/insights')
  listInsights(
    @Param('familyId') familyId: string,
    @Param('decisionId') decisionId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.listInsights({ familyId, decisionId, userId });
  }

  @Post('insights/:insightId/accept')
  accept(
    @Param('insightId') insightId: string,
    @Body() body: { familyId: string },
    @CurrentUser('id') userId: string,
  ) {
    if (!body?.familyId) throw new BadRequestException('familyId is required');
    return this.service.accept(insightId, body.familyId, userId);
  }

  @Post('insights/:insightId/dismiss')
  dismiss(
    @Param('insightId') insightId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { familyId: string; reason: 'not_relevant' | 'already_known' | 'too_prescriptive' | 'other' },
  ) {
    if (!body?.familyId) throw new BadRequestException('familyId is required');
    if (!body.reason) throw new BadRequestException('reason is required');
    return this.service.dismiss(insightId, body.familyId, userId, body.reason);
  }
}
