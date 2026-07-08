// server/src/aura/aura.controller.ts
//
// AURA — REST API Controller
//
// Endpoints (all require JWT auth via global JwtAuthGuard):
//   GET  /aura/:familyId            — current AURA parameters
//   GET  /aura/:familyId/roles      — all member role glyphs
//   GET  /aura/:familyId/history    — AURA timeline snapshots
//   POST /aura/:familyId/recompute  — manually trigger AURA recomputation (async, 202)
//
// Family membership is verified in AuraQueryService (for reads) and via RLS
// (for writes — only service_role can write, and the NestJS backend uses
// the service_role key via Prisma).

import {
  Controller,
  Get,
  Post,
  Param,
  HttpCode,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { AuraOrchestrationService } from './aura-orchestration.service';
import { AuraQueryService } from './aura-query.service';

@Controller('aura')
export class AuraController {
  private readonly logger = new Logger(AuraController.name);

  constructor(
    private readonly orchestration: AuraOrchestrationService,
    private readonly query: AuraQueryService,
  ) {}

  // GET /aura/:familyId
  // Returns the current AURA parameters for a family.
  // Used by Flutter on first load and as a fallback if realtime fails.
  @Get(':familyId')
  async getFamilyAura(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.query.getFamilyAura(familyId, userId);
  }

  // GET /aura/:familyId/roles
  // Returns all member role glyphs for a family.
  @Get(':familyId/roles')
  async getMemberRoles(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.query.getMemberRoles(familyId, userId);
  }

  // GET /aura/:familyId/history
  // Returns the AURA Timeline — all historical AURA snapshots.
  @Get(':familyId/history')
  async getAuraHistory(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.query.getAuraHistory(familyId, userId);
  }

  // POST /aura/:familyId/recompute
  // Manually triggers a full AURA recomputation.
  // Used for: initial setup, after bulk imports, after migrations.
  // Returns 202 Accepted immediately; computation runs asynchronously.
  @Post(':familyId/recompute')
  @HttpCode(HttpStatus.ACCEPTED)
  async recomputeAura(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    // Fire-and-forget: returns 202 immediately, computes asynchronously.
    // Errors are logged but not surfaced to the client (the client can
    // poll GET /aura/:familyId to see when the new AURA appears).
    this.orchestration
      .computeAndSave(familyId, {
        triggerEventType: 'manual_recompute',
        triggerMemberId: userId,
      })
      .catch((err) => {
        this.logger.error(
          `AURA recompute failed for family ${familyId}: ${err instanceof Error ? err.message : err}`,
          err instanceof Error ? err.stack : undefined,
        );
      });

    return {
      status: 'computing',
      message: 'AURA recomputation started. Poll GET /aura/' + familyId + ' for the result.',
      familyId,
    };
  }
}
