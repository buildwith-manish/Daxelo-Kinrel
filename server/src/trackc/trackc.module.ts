// =============================================================================
// Track C v2.0 — AURA Governance Engine
// trackc.module.ts
// =============================================================================
// Top-level aggregator module. Import this from app.module.ts to enable all
// Track C v2.0 features.
//
// Module composition (Section 3.2):
//   - constitution
//   - decisions
//   - governance-timeline (AURA Timeline)
//   - aura-intelligence
//   - aura-learning
//   - aura-secretary
//   - aura-search
//   - aura-analytics
//   - governance-sync
// =============================================================================

import { Module } from '@nestjs/common';
import { TrackcCommonModule } from './common/trackc-common.module';
import { ConstitutionModule } from './constitution/constitution.module';
import { DecisionsModule } from './decisions/decisions.module';
import { GovernanceTimelineModule } from './governance-timeline/timeline.module';
import { AuraIntelligenceModule } from './aura-intelligence/intelligence.module';
import { AuraLearningModule } from './aura-learning/learning.module';
import { AuraSecretaryModule } from './aura-secretary/secretary.module';
import { AuraSearchModule } from './aura-search/search.module';
import { AuraAnalyticsModule } from './aura-analytics/analytics.module';
import { GovernanceSyncModule } from './governance-sync/sync.module';

@Module({
  imports: [
    TrackcCommonModule,
    ConstitutionModule,
    DecisionsModule,
    GovernanceTimelineModule,
    AuraIntelligenceModule,
    AuraLearningModule,
    AuraSecretaryModule,
    AuraSearchModule,
    AuraAnalyticsModule,
    GovernanceSyncModule,
  ],
  exports: [
    TrackcCommonModule,
    ConstitutionModule,
    DecisionsModule,
    GovernanceTimelineModule,
    AuraIntelligenceModule,
    AuraLearningModule,
    AuraSecretaryModule,
    AuraSearchModule,
    AuraAnalyticsModule,
    GovernanceSyncModule,
  ],
})
export class TrackcModule {}
