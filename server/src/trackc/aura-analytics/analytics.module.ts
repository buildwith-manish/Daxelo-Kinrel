// =============================================================================
// Track C v2.0 — AURA Analytics
// analytics.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { AnalyticsController } from './analytics.controller';
import { AnalyticsService } from './analytics.service';
import { AnalyticsSnapshotWorker } from './analytics.snapshot-worker';
import { AnalyticsAnomalyDetector } from './analytics.anomaly-detector';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule],
  controllers: [AnalyticsController],
  providers: [AnalyticsService, AnalyticsSnapshotWorker, AnalyticsAnomalyDetector],
  exports: [AnalyticsService, AnalyticsSnapshotWorker, AnalyticsAnomalyDetector],
})
export class AuraAnalyticsModule {}
