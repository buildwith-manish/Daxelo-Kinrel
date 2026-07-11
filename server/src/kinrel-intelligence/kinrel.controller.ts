// server/src/kinrel/kinrel.controller.ts
//
// Kinrel — REST API Controller
//
// Endpoints (all require JWT auth via global JwtAuthGuard):
//   GET  /kinrel/:familyId            — current Kinrel parameters
//   GET  /kinrel/:familyId/roles      — all member role glyphs
//   GET  /kinrel/:familyId/history    — Kinrel timeline snapshots
//   POST /kinrel/:familyId/recompute  — manually trigger Kinrel recomputation (async, 202)
//
// Family membership is verified in KinrelQueryService (for reads) and via RLS
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
import { KinrelOrchestrationService } from './kinrel-orchestration.service';
import { KinrelQueryService } from './kinrel-query.service';
import { PrismaService } from '../prisma/prisma.service';
import { ForbiddenException } from '@nestjs/common';

@Controller('kinrel')
export class KinrelController {
  private readonly logger = new Logger(KinrelController.name);

  constructor(
    private readonly orchestration: KinrelOrchestrationService,
    private readonly query: KinrelQueryService,
    private readonly prisma: PrismaService,
  ) {}

  private async assertAdmin(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) throw new ForbiddenException('Not a member of this family');
    if (membership.role !== 'admin' && membership.role !== 'owner') {
      throw new ForbiddenException('Only admins can trigger recomputation');
    }
  }

  // GET /kinrel/:familyId
  // Returns the current Kinrel parameters for a family.
  // Used by Flutter on first load and as a fallback if realtime fails.
  @Get(':familyId')
  async getFamilyKinrel(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.query.getFamilyKinrel(familyId, userId);
  }

  // GET /kinrel/:familyId/roles
  // Returns all member role glyphs for a family.
  @Get(':familyId/roles')
  async getMemberRoles(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.query.getMemberRoles(familyId, userId);
  }

  // GET /kinrel/:familyId/history
  // Returns the Kinrel Timeline — all historical Kinrel snapshots.
  @Get(':familyId/history')
  async getKinrelHistory(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.query.getKinrelHistory(familyId, userId);
  }

  // POST /kinrel/:familyId/recompute
  // Manually triggers a full Kinrel recomputation.
  // Used for: initial setup, after bulk imports, after migrations.
  // Returns 202 Accepted immediately; computation runs asynchronously.
  @Post(':familyId/recompute')
  @HttpCode(HttpStatus.ACCEPTED)
  async recomputeKinrel(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    // SECURITY: verify the requesting user is an admin of this family
    await this.assertAdmin(userId, familyId);

    // Bug 6 fix: pass null for triggerMemberId. The field has an FK
    // constraint against Person.id (the graph node ID), but `userId`
    // is a Supabase auth User ID — a completely different entity.
    // Passing it as-is caused the orchestration service to look up
    // the Person row, fail to find it, and silently null out the
    // field anyway. Passing null explicitly is the honest behaviour
    // — we don't have the Person ID at the controller level, and
    // the history snapshot's triggerMemberId column is nullable by
    // design for exactly this case (bulk / manual recomputes).
    //
    // If we later want to attribute the recompute to a specific
    // Person, the controller can do a Prisma lookup:
    //   const member = await this.prisma.familyMember.findUnique({
    //     where: { familyId_userId: { familyId, userId } },
    //     select: { personId: true },
    //   });
    //   triggerMemberId: member?.personId ?? null,
    // For now, null is correct and matches the existing orchestration
    // service's null-coalescing behaviour.
    this.orchestration
      .computeAndSave(familyId, {
        triggerEventType: 'manual_recompute',
        triggerMemberId: null,
      })
      .catch((err) => {
        this.logger.error(
          `Kinrel recompute failed for family ${familyId}: ${err instanceof Error ? err.message : err}`,
          err instanceof Error ? err.stack : undefined,
        );
      });

    return {
      status: 'computing',
      message: 'Kinrel recomputation started. Poll GET /kinrel/' + familyId + ' for the result.',
      familyId,
    };
  }
}
