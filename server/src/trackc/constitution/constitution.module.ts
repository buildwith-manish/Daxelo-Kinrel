// =============================================================================
// Track C v2.0 — AURA Governance: Constitution
// constitution.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { ConstitutionController } from './constitution.controller';
import { ConstitutionService } from './constitution.service';
import { GovernanceTimelineModule } from '../governance-timeline/timeline.module';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule, GovernanceTimelineModule],
  controllers: [ConstitutionController],
  providers: [ConstitutionService],
  exports: [ConstitutionService],
})
export class ConstitutionModule {}
