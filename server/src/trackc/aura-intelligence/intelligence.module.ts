// =============================================================================
// Track C v2.0 — AURA Intelligence
// intelligence.module.ts
// =============================================================================
// The module wires the LLM provider based on environment:
//   - OPENAI_API_KEY present → OpenAIProvider
//   - Otherwise → MockLLMProvider (for local dev + tests)
// =============================================================================

import { Module, Logger } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { IntelligenceController } from './intelligence.controller';
import { IntelligenceService } from './intelligence.service';
import { IntelligenceCache } from './intelligence.cache';
import { CircuitBreaker } from './intelligence.circuit-breaker';
import { CostGuard } from './intelligence.cost-guard';
import { RedactionService } from './redaction';
import { DecisionAnalysisKind } from './kinds/decision-analysis.kind';
import { ProsConsKind } from './kinds/pros-cons.kind';
import { SummaryKind } from './kinds/summary.kind';
import { DuplicateDetectionKind } from './kinds/duplicate-detection.kind';
import { ActionItemsKind } from './kinds/action-items.kind';
import { LLM_PROVIDER, LLMProvider } from './llm-provider';
import { OpenAIProvider } from './llm-providers/openai.provider';
import { MockLLMProvider } from './llm-providers/mock.provider';
import { GovernanceTimelineModule } from '../governance-timeline/timeline.module';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, ConfigModule, TrackcCommonModule, GovernanceTimelineModule],
  controllers: [IntelligenceController],
  providers: [
    IntelligenceCache,
    CircuitBreaker,
    CostGuard,
    RedactionService,
    DecisionAnalysisKind,
    ProsConsKind,
    SummaryKind,
    DuplicateDetectionKind,
    ActionItemsKind,
    IntelligenceService,
    {
      // Factory: choose provider based on env
      provide: LLM_PROVIDER,
      inject: [ConfigService],
      useFactory: (config: ConfigService): LLMProvider => {
        const logger = new Logger('LLMProviderFactory');
        const apiKey = config.get<string>('OPENAI_API_KEY');
        const baseUrl = config.get<string>('OPENAI_BASE_URL');
        const defaultModelId = config.get<string>('OPENAI_DEFAULT_MODEL') ?? 'gpt-4o-mini';
        if (apiKey && apiKey.length > 10) {
          logger.log(`Using OpenAI LLM provider (model=${defaultModelId})`);
          return new OpenAIProvider({ apiKey, baseUrl, defaultModelId });
        }
        logger.warn('OPENAI_API_KEY not set — using MockLLMProvider. AI insights will be canned.');
        return new MockLLMProvider();
      },
    },
  ],
  exports: [IntelligenceService, IntelligenceCache, CircuitBreaker, CostGuard, RedactionService, DecisionAnalysisKind, ProsConsKind, SummaryKind, DuplicateDetectionKind, ActionItemsKind, LLM_PROVIDER],
})
export class AuraIntelligenceModule {}
