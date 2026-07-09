// =============================================================================
// Track C v2.0 — AURA Governance: Decisions
// decisions.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { DecisionsController } from './decisions.controller';
import { DecisionsService } from './decisions.service';
import { GovernanceTimelineModule } from '../governance-timeline/timeline.module';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule, GovernanceTimelineModule],
  controllers: [DecisionsController],
  providers: [DecisionsService],
  exports: [DecisionsService],
})
export class DecisionsModule {}
