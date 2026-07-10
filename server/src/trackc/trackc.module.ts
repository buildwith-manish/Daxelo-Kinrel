// =============================================================================
// Track C v2.0 — Kinrel Governance Engine
// trackc.module.ts
// =============================================================================
// Top-level aggregator module. Import this from app.module.ts to enable all
// Track C v2.0 features.
//
// Module composition (Section 3.2):
//   - constitution
//   - decisions
//   - governance-timeline (Kinrel Timeline)
//   - kinrel-intelligence
//   - kinrel-learning
//   - kinrel-secretary
//   - kinrel-search
//   - kinrel-analytics
//   - governance-sync
// =============================================================================

import { Module } from '@nestjs/common';
import { TrackcCommonModule } from './common/trackc-common.module';
import { ConstitutionModule } from './constitution/constitution.module';
import { DecisionsModule } from './decisions/decisions.module';
import { GovernanceTimelineModule } from './governance-timeline/timeline.module';
import { KinrelIntelligenceModule } from './kinrel-intelligence/intelligence.module';
import { KinrelLearningModule } from './kinrel-learning/learning.module';
import { KinrelSecretaryModule } from './kinrel-secretary/secretary.module';
import { KinrelSearchModule } from './kinrel-search/search.module';
import { KinrelAnalyticsModule } from './kinrel-analytics/analytics.module';
import { GovernanceSyncModule } from './governance-sync/sync.module';
import { TrackcWorkers } from './trackc.workers';

@Module({
  imports: [
    TrackcCommonModule,
    ConstitutionModule,
    DecisionsModule,
    GovernanceTimelineModule,
    KinrelIntelligenceModule,
    KinrelLearningModule,
    KinrelSecretaryModule,
    KinrelSearchModule,
    KinrelAnalyticsModule,
    GovernanceSyncModule,
  ],
  providers: [TrackcWorkers],
  exports: [
    TrackcCommonModule,
    ConstitutionModule,
    DecisionsModule,
    GovernanceTimelineModule,
    KinrelIntelligenceModule,
    KinrelLearningModule,
    KinrelSecretaryModule,
    KinrelSearchModule,
    KinrelAnalyticsModule,
    GovernanceSyncModule,
  ],
})
export class TrackcModule {}
