// =============================================================================
// Track C v2.0 — Kinrel Learning Engine
// learning.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { LearningController } from './learning.controller';
import { LearningService } from './learning.service';
import { SignalIngestor } from './learning.signal-ingestor';
import { ProfileBuilder } from './learning.profile-builder';
import { LearningInference } from './learning.inference';
import { GovernanceTimelineModule } from '../governance-timeline/timeline.module';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule, GovernanceTimelineModule],
  controllers: [LearningController],
  providers: [LearningService, SignalIngestor, ProfileBuilder, LearningInference],
  exports: [LearningService, SignalIngestor, ProfileBuilder, LearningInference],
})
export class KinrelLearningModule {}
