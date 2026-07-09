// =============================================================================
// Track C v2.0 — AURA Secretary
// secretary.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { SecretaryController } from './secretary.controller';
import { SecretaryService } from './secretary.service';
import { AuraIntelligenceModule } from '../aura-intelligence/intelligence.module';
import { GovernanceTimelineModule } from '../governance-timeline/timeline.module';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule, GovernanceTimelineModule, AuraIntelligenceModule],
  controllers: [SecretaryController],
  providers: [SecretaryService],
  exports: [SecretaryService],
})
export class AuraSecretaryModule {}
