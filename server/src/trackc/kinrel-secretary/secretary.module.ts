// =============================================================================
// Track C v2.0 — Kinrel Secretary
// secretary.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { SecretaryController } from './secretary.controller';
import { SecretaryService } from './secretary.service';
import { KinrelIntelligenceModule } from '../kinrel-intelligence/intelligence.module';
import { GovernanceTimelineModule } from '../governance-timeline/timeline.module';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule, GovernanceTimelineModule, KinrelIntelligenceModule],
  controllers: [SecretaryController],
  providers: [SecretaryService],
  exports: [SecretaryService],
})
export class KinrelSecretaryModule {}
