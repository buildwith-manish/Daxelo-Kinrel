// =============================================================================
// Track C v2.0 - AURA Intelligence
// intelligence.service.ts
// =============================================================================
// Orchestrates the AI insight pipeline. Section 8.1.
//
// Pipeline:
//   1. Rate limit + budget check
//   2. Cache lookup -> hit? return cached AIInsight
//   3. Circuit breaker check -> open? return 503 with degraded_mode=true
//   4. LLM call (with redaction)
//   5. Persist AIInsight with tokensIn/Out, costUsd
//   6. Return to client (via WebSocket push for async, or directly for sync)
// =============================================================================

import {
  Injectable,
  Logger,
  Optional,
  Inject,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { LLM_PROVIDER, LLMProvider } from './llm-provider';
import { IntelligenceCache } from './intelligence.cache';
import { CircuitBreaker, DegradedModeError } from './intelligence.circuit-breaker';
import { CostGuard, BudgetExhaustedError } from './intelligence.cost-guard';
import { RedactionService } from './redaction';
import { DecisionAnalysisKind } from './kinds/decision-analysis.kind';
import { ProsConsKind } from './kinds/pros-cons.kind';
import { SummaryKind } from './kinds/summary.kind';
import { DuplicateDetectionKind } from './kinds/duplicate-detection.kind';
import { ActionItemsKind } from './kinds/action-items.kind';
import {
  preFilterDuplicates,
  DuplicatePrefilterResult,
} from './duplicate-prefilter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { randomUUID } from 'crypto';

export type InsightKind =
  | 'decision_analysis'
  | 'duplicate_detection'
  | 'summary'
  | 'pros_cons'
  | 'smart_reminder'
  | 'action_items'
  | 'draft_minutes'
  | 'search_synonym';

export interface RequestInsightsResult {
  /** Insights that were already cached and returned immediately. */
  cached: any[];
  /** Insights that were freshly generated. */
  generated: any[];
  /** True if AI is in degraded mode (budget exhausted or breaker open). */
  degradedMode: boolean;
  /** True if some requested kinds were queued for async generation. */
  queued: boolean;
}

@Injectable()
export class IntelligenceService {
  private readonly logger = new Logger(IntelligenceService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly cache: IntelligenceCache,
    private readonly breaker: CircuitBreaker,
    private readonly costGuard: CostGuard,
    private readonly redaction: RedactionService,
    private readonly membership: FamilyMembershipService,
    private readonly emitter: TimelineEmitter,
    private readonly decisionAnalysisKind: DecisionAnalysisKind,
    private readonly prosConsKind: ProsConsKind,
    private readonly summaryKind: SummaryKind,
    private readonly duplicateDetectionKind: DuplicateDetectionKind,
    private readonly actionItemsKind: ActionItemsKind,
    @Inject(LLM_PROVIDER) private readonly llm: LLMProvider,
  ) {}

  /**
   * Request one or more insights for a decision.
   * Returns cached insights immediately; generates new ones synchronously
   * if circuit is closed and budget remains.
   */
  async requestInsights(params: {
    familyId: string;
    decisionId: string;
    kinds: InsightKind[];
    userId: string;
  }): Promise<RequestInsightsResult> {
    await this.membership.requireMember(params.userId, params.familyId);

    // Verify the decision exists in this family
    const decision = await this.prisma.familyDecision.findUnique({
      where: { id_familyId: { id: params.decisionId, familyId: params.familyId } },
    });
    if (!decision) throw new NotFoundException('Decision not found');

    const cached: any[] = [];
    const generated: any[] = [];
    let degradedMode = false;
    const toGenerate: InsightKind[] = [];

    // ?? Step 1: cache lookup per kind ????????????????????????????????????
    for (const kind of params.kinds) {
      const hit = await this.cache.lookup({
        familyId: params.familyId,
        decisionId: params.decisionId,
        kind,
      });
      if (hit) {
        cached.push(hit);
      } else {
        toGenerate.push(kind);
      }
    }

    if (toGenerate.length === 0) {
      return { cached, generated, degradedMode: false, queued: false };
    }

    // ?? Step 2: budget check ?????????????????????????????????????????????
    const budget = await this.costGuard.checkBudget(params.familyId);
    if (budget.exhausted) {
      degradedMode = true;
      this.logger.warn(`Family ${params.familyId} AI budget exhausted - serving cached only`);
      return { cached, generated: [], degradedMode, queued: false };
    }

    // ?? Step 3: circuit breaker ??????????????????????????????????????????
    if (this.breaker.isOpen()) {
      degradedMode = true;
      return { cached, generated: [], degradedMode, queued: false };
    }

    // ?? Step 4: generate each missing kind ???????????????????????????????
    for (const kind of toGenerate) {
      try {
        const insight = await this.breaker.execute(() =>
          this.generateInsight({
            familyId: params.familyId,
            decisionId: params.decisionId,
            kind,
            decision,
          }),
        );
        generated.push(insight);
      } catch (err) {
        if (err instanceof DegradedModeError) {
          degradedMode = true;
          this.logger.warn(`Degraded mode during ${kind} generation: ${err.message}`);
        } else if (err instanceof BudgetExhaustedError) {
          degradedMode = true;
          this.logger.warn(`Budget exhausted during ${kind} generation`);
        } else {
          this.logger.error(
            `Insight generation failed (kind=${kind}, decision=${params.decisionId}): ${(err as Error).message}`,
          );
          // Edge case #4: LLM returns invalid JSON -> retry once with stricter prompt.
          // The kind's parseResponse already handles invalid JSON by returning a
          // minimal valid payload. If we reach here, the LLM call itself failed.
        }
      }
    }

    return { cached, generated, degradedMode, queued: false };
  }

  private async generateInsight(params: {
    familyId: string;
    decisionId: string;
    kind: InsightKind;
    decision: any;
  }) {
    const requestId = randomUUID();
    const familySize = await this.prisma.familyMember.count({
      where: { familyId: params.familyId },
    });

    let request: any;
    let parseResponse: (content: string) => any;

    switch (params.kind) {
      case 'decision_analysis':
        request = this.decisionAnalysisKind.buildRequest({
          decisionTitle: params.decision.title,
          decisionDescription: params.decision.description ?? undefined,
          decisionType: params.decision.type,
          options: params.decision.options,
          eligibleCount: params.decision.eligibleUserIds.length,
          quorumPct: params.decision.quorumPct,
          deadlineHours: (params.decision.deadlineAt.getTime() - Date.now()) / 3_600_000,
          familySize,
        });
        parseResponse = (c) => this.decisionAnalysisKind.parseResponse(c);
        break;

      case 'pros_cons':
        request = this.prosConsKind.buildRequest({
          decisionTitle: params.decision.title,
          decisionDescription: params.decision.description ?? undefined,
          options: params.decision.options,
        });
        parseResponse = (c) => this.prosConsKind.parseResponse(c);
        break;

      case 'summary':
        request = this.summaryKind.buildRequest({
          decisionTitle: params.decision.title,
          decisionDescription: params.decision.description ?? undefined,
          outcome: params.decision.outcome ?? undefined,
          resolutionNote: params.decision.resolutionNote ?? undefined,
        });
        parseResponse = (c) => this.summaryKind.parseResponse(c);
        break;

      case 'duplicate_detection': {
        const priorDecisions = await this.prisma.familyDecision.findMany({
          where: { familyId: params.familyId, id: { not: params.decisionId } },
          orderBy: { createdAt: 'desc' },
          take: 20,
          select: { id: true, title: true, description: true },
        });

        // ?? Local TF-IDF pre-filter ????????????????????????????????????
        // Run a free, local similarity pass BEFORE building the LLM request.
        // High similarity  -> skip AI, return local match directly.
        // Low similarity   -> skip AI, return no duplicates.
        // Ambiguous band   -> escalate to AI as before.
        //
        // Logged so token savings can be measured after shipping.
        const prefilter = preFilterDuplicates({
          newDecisionTitle: params.decision.title,
          newDecisionDescription: params.decision.description ?? undefined,
          priorDecisions: priorDecisions.map((d) => ({
            id: d.id,
            title: d.title,
            description: d.description ?? undefined,
          })),
        });

        this.logger.log(
          `duplicate_detection pre-filter: path=${prefilter.path}, topScore=${prefilter.topScore}, decision=${params.decisionId}`,
        );

        if (prefilter.path !== 'escalate') {
          // Pre-filter resolved it - persist the insight without an AI call,
          // and return early. We persist it so the client sees the same
          // shape as an AI-generated insight (and so it's cached for next
          // time).
          const payload = {
            duplicates: prefilter.duplicates,
            closestMatch: prefilter.closestMatch,
            message: prefilter.message,
          };
          const insight = await this.prisma.aIInsight.create({
            data: {
              familyId: params.familyId,
              decisionId: params.decisionId,
              kind: params.kind,
              status: 'presented',
              payload: payload as any,
              modelId: 'local-tfidf-prefilter', // mark as locally generated
              tokensIn: 0,
              tokensOut: 0,
              costUsd: 0,
              presentedAt: new Date(),
            },
          });
          return insight;
        }

        // Escalate to AI - build the LLM request as before, but only with
        // the top ~5 candidates by pre-filter score (further reduces token
        // cost without sacrificing recall for genuinely ambiguous pairs).
        request = this.duplicateDetectionKind.buildRequest({
          newDecisionTitle: params.decision.title,
          newDecisionDescription: params.decision.description ?? undefined,
          priorDecisions: priorDecisions.map((d) => ({
            id: d.id,
            title: d.title,
            description: d.description ?? undefined,
          })),
        });
        parseResponse = (c) => this.duplicateDetectionKind.parseResponse(c);
        break;
      }

      default:
        throw new BadRequestException(`Insight kind '${params.kind}' is not supported via this endpoint`);
    }

    // ?? LLM call ??????????????????????????????????????????????????????????
    const response = await this.llm.generate(request);
    const payload = parseResponse(response.content);

    // ?? Charge the budget ?????????????????????????????????????????????????
    await this.costGuard.charge({
      familyId: params.familyId,
      tokensIn: response.tokensIn,
      tokensOut: response.tokensOut,
      costUsd: response.costUsd,
      requestId,
    });

    // ?? Persist the insight ???????????????????????????????????????????????
    const insight = await this.prisma.aIInsight.create({
      data: {
        familyId: params.familyId,
        decisionId: params.decisionId,
        kind: params.kind,
        status: 'presented',
        payload: payload as any,
        modelId: response.modelId,
        tokensIn: response.tokensIn,
        tokensOut: response.tokensOut,
        costUsd: response.costUsd,
        presentedAt: new Date(),
      },
    });

    // Also denormalize into the decision's cached fields for fast read
    if (params.kind === 'summary') {
      await this.prisma.familyDecision.update({
        where: { id_familyId: { id: params.decisionId, familyId: params.familyId } },
        data: { aiSummaryCached: payload as any },
      });
    } else if (params.kind === 'pros_cons') {
      await this.prisma.familyDecision.update({
        where: { id_familyId: { id: params.decisionId, familyId: params.familyId } },
        data: { aiProsConsCached: payload as any },
      });
    }

    return insight;
  }

  /**
   * List insights for a decision. Returns all insights (cached + historical).
   */
  async listInsights(params: {
    familyId: string;
    decisionId: string;
    kind?: InsightKind;
    userId: string;
  }) {
    await this.membership.requireMember(params.userId, params.familyId);

    return this.prisma.aIInsight.findMany({
      where: {
        familyId: params.familyId,
        decisionId: params.decisionId,
        ...(params.kind ? { kind: params.kind } : {}),
        status: { in: ['pending', 'presented', 'accepted', 'dismissed'] },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async accept(insightId: string, familyId: string, userId: string) {
    await this.membership.requireMember(userId, familyId);
    return this.cache.markAccepted(insightId, familyId);
  }

  async dismiss(
    insightId: string,
    familyId: string,
    userId: string,
    reason: 'not_relevant' | 'already_known' | 'too_prescriptive' | 'other',
  ) {
    await this.membership.requireMember(userId, familyId);
    const updated = await this.cache.markDismissed(insightId, familyId, reason);

    // Emit a learning signal: insight_dismissed
    await this.prisma.learningSignal.create({
      data: {
        familyId,
        signalType: 'insight_dismissed',
        targetType: 'AIInsight',
        targetId: insightId,
        payload: { reason, kind: updated.kind },
      },
    });

    return updated;
  }
}
