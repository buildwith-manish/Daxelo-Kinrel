// =============================================================================
// Track C v2.0 — IntelligenceService Tests
// =============================================================================
// Real coverage of the IntelligenceService pipeline:
//   - cache hit path (returns cached insight without calling the provider)
//   - cache miss path (calls provider, persists insight, returns it)
//   - budget exhaustion path (returns degraded-mode response)
//   - circuit breaker open path (returns degraded-mode response)
//   - PII redaction is applied to user-content before sending to the provider
//
// The original MockLLMProvider tests are preserved at the bottom of this file
// for backwards compatibility.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
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
import { MockLLMProvider } from './llm-providers/mock.provider';
import { NotFoundException } from '@nestjs/common';

// ───────────────────────────────────────────────────────────────────────────
// Real IntelligenceService tests
// ───────────────────────────────────────────────────────────────────────────
describe('IntelligenceService', () => {
  let prisma: any;
  let cache: IntelligenceCache;
  let breaker: CircuitBreaker;
  let costGuard: CostGuard;
  let redaction: RedactionService;
  let membership: any;
  let emitter: any;
  let decisionAnalysisKind: DecisionAnalysisKind;
  let prosConsKind: ProsConsKind;
  let summaryKind: SummaryKind;
  let duplicateDetectionKind: DuplicateDetectionKind;
  let actionItemsKind: ActionItemsKind;
  let llm: jest.Mocked<LLMProvider>;
  let service: IntelligenceService;

  beforeEach(() => {
    prisma = new PrismaService();
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).create.mockResolvedValue({});
        (m as any).update.mockResolvedValue({});
        (m as any).updateMany.mockResolvedValue({ count: 0 });
        (m as any).upsert.mockResolvedValue({});
        (m as any).count.mockResolvedValue(0);
      }
    }

    // Real collaborators (exercise actual logic)
    cache = new IntelligenceCache(prisma as any);
    breaker = new CircuitBreaker();
    costGuard = new CostGuard(prisma as any);
    redaction = new RedactionService();
    decisionAnalysisKind = new DecisionAnalysisKind(redaction);
    prosConsKind = new ProsConsKind(redaction);
    summaryKind = new SummaryKind(redaction);
    duplicateDetectionKind = new DuplicateDetectionKind(redaction);
    actionItemsKind = new ActionItemsKind(redaction);

    // Mocked collaborators
    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
      getElderUserIds: jest.fn().mockResolvedValue([]),
      getActiveMemberUserIds: jest.fn().mockResolvedValue(['u1', 'u2']),
    };
    emitter = { append: jest.fn().mockResolvedValue('event-id') };
    llm = {
      generate: jest.fn().mockResolvedValue({
        modelId: 'mock',
        content: JSON.stringify({
          qualityScore: 0.7,
          strengths: ['Clear options'],
          risks: ['Tight deadline'],
          recommendation: 'Extend deadline by 2 days',
          confidenceLevel: 'medium',
        }),
        tokensIn: 100,
        tokensOut: 80,
        costUsd: 0.001,
        latencyMs: 200,
      }),
      providerName: 'mock',
      getUsageStats: jest.fn().mockReturnValue({
        totalRequests: 0,
        totalTokensIn: 0,
        totalTokensOut: 0,
        totalCostUsd: 0,
        errorCount: 0,
      }),
    } as any;

    service = new IntelligenceService(
      prisma as any,
      cache,
      breaker,
      costGuard,
      redaction,
      membership as any,
      emitter as any,
      decisionAnalysisKind,
      prosConsKind,
      summaryKind,
      duplicateDetectionKind,
      actionItemsKind,
      llm as any,
    );
  });

  function mockDecision(overrides: any = {}) {
    return {
      id: 'd_1',
      familyId: 'fam_1',
      title: 'Family vacation',
      description: 'Where to go this summer',
      type: 'simple_vote',
      status: 'open',
      options: ['beach', 'mountains'],
      eligibleUserIds: ['u1', 'u2', 'u3'],
      quorumPct: 50,
      deadlineAt: new Date(Date.now() + 86_400_000),
      resolvedAt: null,
      outcome: null,
      resolutionNote: null,
      ...overrides,
    };
  }

  // ── Cache hit path ─────────────────────────────────────────────────
  describe('cache hit path', () => {
    it('returns cached insight without calling the LLM provider', async () => {
      const decision = mockDecision();
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      const cachedInsight = {
        id: 'ins_cached',
        familyId: 'fam_1',
        decisionId: 'd_1',
        kind: 'decision_analysis',
        status: 'presented',
        payload: { qualityScore: 0.5 },
        createdAt: new Date(),
      };
      // Cache lookup hits
      prisma.aIInsight.findMany.mockResolvedValueOnce([cachedInsight]);

      const result = await service.requestInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kinds: ['decision_analysis'],
        userId: 'u_1',
      });

      expect(result.cached).toEqual([cachedInsight]);
      expect(result.generated).toEqual([]);
      expect(result.degradedMode).toBe(false);
      // The LLM provider must NOT be called when the cache hits
      expect(llm.generate).not.toHaveBeenCalled();
      // No new AIInsight row should be persisted
      expect(prisma.aIInsight.create).not.toHaveBeenCalled();
    });
  });

  // ── Cache miss path ────────────────────────────────────────────────
  describe('cache miss path', () => {
    it('calls the provider, persists the insight, and returns it', async () => {
      const decision = mockDecision();
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      // Cache miss
      prisma.aIInsight.findMany.mockResolvedValueOnce([]);
      // Budget check (costGuard.checkBudget → aICostBudget.findUnique returns null → not exhausted)
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null);
      // costGuard.charge → aICostBudget.findUnique again, then upsert
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null);
      // Persist the new insight
      const persisted = {
        id: 'ins_new',
        familyId: 'fam_1',
        decisionId: 'd_1',
        kind: 'decision_analysis',
        status: 'presented',
        payload: { qualityScore: 0.7 },
      };
      prisma.aIInsight.create.mockResolvedValueOnce(persisted);
      // familyMember.count for familySize
      prisma.familyMember.count.mockResolvedValueOnce(5);

      const result = await service.requestInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kinds: ['decision_analysis'],
        userId: 'u_1',
      });

      // LLM provider must have been called
      expect(llm.generate).toHaveBeenCalledTimes(1);
      // The insight must be persisted
      expect(prisma.aIInsight.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: 'fam_1',
            decisionId: 'd_1',
            kind: 'decision_analysis',
            status: 'presented',
            tokensIn: 100,
            tokensOut: 80,
            costUsd: 0.001,
          }),
        }),
      );
      // The result must include the generated insight
      expect(result.generated).toEqual([persisted]);
      expect(result.degradedMode).toBe(false);
    });

    it('throws NotFoundException when the decision does not exist', async () => {
      prisma.familyDecision.findUnique.mockResolvedValueOnce(null);
      await expect(
        service.requestInsights({
          familyId: 'fam_1',
          decisionId: 'missing',
          kinds: ['decision_analysis'],
          userId: 'u_1',
        }),
      ).rejects.toThrow(NotFoundException);
      expect(llm.generate).not.toHaveBeenCalled();
    });
  });

  // ── Budget exhaustion path ─────────────────────────────────────────
  describe('budget exhaustion path', () => {
    it('returns degraded-mode response without calling the LLM provider', async () => {
      const decision = mockDecision();
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      // Cache miss
      prisma.aIInsight.findMany.mockResolvedValueOnce([]);
      // Budget exhausted — budget row exists with tokensUsed >= budgetTokens
      prisma.aICostBudget.findUnique.mockResolvedValueOnce({
        familyId: 'fam_1',
        dateUtc: new Date(),
        tokensUsed: 50_000,
        budgetTokens: 50_000,
        costUsd: 1.5,
        circuitOpen: false,
      });

      const result = await service.requestInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kinds: ['decision_analysis'],
        userId: 'u_1',
      });

      expect(result.degradedMode).toBe(true);
      expect(result.generated).toEqual([]);
      // The LLM provider must NOT be called when budget is exhausted
      expect(llm.generate).not.toHaveBeenCalled();
      // No new AIInsight row should be persisted
      expect(prisma.aIInsight.create).not.toHaveBeenCalled();
    });
  });

  // ── Circuit breaker open path ──────────────────────────────────────
  describe('circuit breaker open path', () => {
    it('returns degraded-mode response when the breaker is open', async () => {
      const decision = mockDecision();
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      // Cache miss
      prisma.aIInsight.findMany.mockResolvedValueOnce([]);
      // Budget OK (not exhausted)
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null);

      // Force the breaker open by recording 5 failures (minCallsBeforeTrip=5)
      // The breaker trips when error rate >= 10% over the last 60s with >=5 calls.
      for (let i = 0; i < 5; i++) {
        try {
          await breaker.execute(async () => {
            throw new Error('upstream error');
          });
        } catch {
          // expected
        }
      }
      expect(breaker.isOpen()).toBe(true);

      const result = await service.requestInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kinds: ['decision_analysis'],
        userId: 'u_1',
      });

      expect(result.degradedMode).toBe(true);
      expect(result.generated).toEqual([]);
      // The LLM provider must NOT be called when the breaker is open
      expect(llm.generate).not.toHaveBeenCalled();
    });
  });

  // ── Redaction ──────────────────────────────────────────────────────
  describe('PII redaction', () => {
    it('redacts email/phone PII from the decision title before sending to the LLM provider', async () => {
      const decision = mockDecision({
        title: 'Email john@example.com or call +1-555-867-5309 about the vacation',
        description: 'Reach out to schedule a call',
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      // Cache miss
      prisma.aIInsight.findMany.mockResolvedValueOnce([]);
      // Budget OK
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null);
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null); // charge() re-lookup
      prisma.aIInsight.create.mockResolvedValueOnce({
        id: 'ins_new',
        familyId: 'fam_1',
        kind: 'decision_analysis',
      });
      prisma.familyMember.count.mockResolvedValueOnce(5);

      await service.requestInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kinds: ['decision_analysis'],
        userId: 'u_1',
      });

      // The LLM provider must have been called exactly once
      expect(llm.generate).toHaveBeenCalledTimes(1);
      const request = llm.generate.mock.calls[0][0];
      // Inspect the user message — it must NOT contain the raw PII
      const userMsg = request.messages.find((m: any) => m.role === 'user')!;
      expect(userMsg.content).not.toContain('john@example.com');
      expect(userMsg.content).not.toContain('+1-555-867-5309');
      // The redaction markers must be present
      expect(userMsg.content).toContain('[REDACTED_EMAIL]');
      expect(userMsg.content).toContain('[REDACTED_PHONE]');
    });

    it('redacts PII from the description too', async () => {
      const decision = mockDecision({
        title: 'Vacation planning',
        description: 'Contact jane@example.com for details',
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      prisma.aIInsight.findMany.mockResolvedValueOnce([]);
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null);
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null);
      prisma.aIInsight.create.mockResolvedValueOnce({ id: 'ins', familyId: 'fam_1' });
      prisma.familyMember.count.mockResolvedValueOnce(5);

      await service.requestInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kinds: ['decision_analysis'],
        userId: 'u_1',
      });

      const request = llm.generate.mock.calls[0][0];
      const userMsg = request.messages.find((m: any) => m.role === 'user')!;
      expect(userMsg.content).not.toContain('jane@example.com');
      expect(userMsg.content).toContain('[REDACTED_EMAIL]');
    });
  });

  // ── Multiple kinds ─────────────────────────────────────────────────
  describe('mixed cache hit + miss across multiple kinds', () => {
    it('returns cached for some kinds and generates the rest', async () => {
      const decision = mockDecision();
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      // Cache hit for decision_analysis, miss for summary
      prisma.aIInsight.findMany
        .mockResolvedValueOnce([
          {
            id: 'ins_cached_da',
            kind: 'decision_analysis',
            status: 'presented',
            createdAt: new Date(),
          },
        ])
        .mockResolvedValueOnce([]); // summary cache miss
      // Budget OK
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null);
      prisma.aICostBudget.findUnique.mockResolvedValueOnce(null); // charge() re-lookup
      prisma.aIInsight.create.mockResolvedValueOnce({
        id: 'ins_new_sum',
        familyId: 'fam_1',
        kind: 'summary',
      });
      prisma.familyMember.count.mockResolvedValueOnce(5);
      // Summary denormalizes to decision.aiSummaryCached
      prisma.familyDecision.update.mockResolvedValueOnce({});

      const result = await service.requestInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kinds: ['decision_analysis', 'summary'],
        userId: 'u_1',
      });

      // decision_analysis was cached
      expect(result.cached).toHaveLength(1);
      expect(result.cached[0].kind).toBe('decision_analysis');
      // summary was generated
      expect(result.generated).toHaveLength(1);
      expect(result.generated[0].kind).toBe('summary');
      // Only ONE LLM call (for the missing kind)
      expect(llm.generate).toHaveBeenCalledTimes(1);
    });
  });

  // ── listInsights ───────────────────────────────────────────────────
  describe('listInsights()', () => {
    it('returns insights for the decision ordered by createdAt DESC', async () => {
      const insights = [
        { id: 'i2', kind: 'summary', createdAt: new Date('2026-07-13') },
        { id: 'i1', kind: 'decision_analysis', createdAt: new Date('2026-07-06') },
      ];
      prisma.aIInsight.findMany.mockResolvedValueOnce(insights);

      const result = await service.listInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        userId: 'u_1',
      });

      expect(result).toEqual(insights);
      expect(prisma.aIInsight.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            familyId: 'fam_1',
            decisionId: 'd_1',
            status: { in: ['pending', 'presented', 'accepted', 'dismissed'] },
          }),
          orderBy: { createdAt: 'desc' },
        }),
      );
    });

    it('filters by kind when provided', async () => {
      prisma.aIInsight.findMany.mockResolvedValueOnce([]);
      await service.listInsights({
        familyId: 'fam_1',
        decisionId: 'd_1',
        kind: 'summary',
        userId: 'u_1',
      });
      expect(prisma.aIInsight.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ kind: 'summary' }),
        }),
      );
    });
  });

  // ── dismiss() ──────────────────────────────────────────────────────
  describe('dismiss()', () => {
    it('marks the insight dismissed and emits a learning signal', async () => {
      prisma.aIInsight.update.mockResolvedValueOnce({
        id: 'ins_1',
        kind: 'decision_analysis',
        status: 'dismissed',
      });
      prisma.learningSignal.create.mockResolvedValueOnce({ id: 'sig_1' });

      const result = await service.dismiss('ins_1', 'fam_1', 'u_1', 'not_relevant');

      expect(result.status).toBe('dismissed');
      // A learning signal must be persisted
      expect(prisma.learningSignal.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: 'fam_1',
            signalType: 'insight_dismissed',
            targetId: 'ins_1',
            payload: { reason: 'not_relevant', kind: 'decision_analysis' },
          }),
        }),
      );
    });
  });
});

// ───────────────────────────────────────────────────────────────────────────
// Original MockLLMProvider tests (preserved for backwards compatibility)
// ───────────────────────────────────────────────────────────────────────────
describe('MockLLMProvider', () => {
  let provider: MockLLMProvider;

  beforeEach(() => {
    provider = new MockLLMProvider();
  });

  it('returns valid decision_analysis JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [
        { role: 'system', content: 'decision_analysis' },
        { role: 'user', content: 'Decision: family vacation' },
      ],
    });
    const parsed = JSON.parse(response.content);
    expect(parsed.qualityScore).toBeGreaterThan(0);
    expect(parsed.qualityScore).toBeLessThanOrEqual(1);
    expect(Array.isArray(parsed.strengths)).toBe(true);
    expect(Array.isArray(parsed.risks)).toBe(true);
    expect(parsed.recommendation).toBeTruthy();
    expect(['low', 'medium', 'high']).toContain(parsed.confidenceLevel);
  });

  it('returns valid pros_cons JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'pros_cons' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(Array.isArray(parsed.pros)).toBe(true);
    expect(Array.isArray(parsed.cons)).toBe(true);
    expect(parsed.balancedAssessment).toBeTruthy();
  });

  it('returns valid summary JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'summary' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(parsed.summary).toBeTruthy();
    expect(Array.isArray(parsed.keyTakeaways)).toBe(true);
  });

  it('returns valid duplicate_detection JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'duplicate_detection' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(Array.isArray(parsed.duplicates)).toBe(true);
    expect(parsed.message).toBeTruthy();
  });

  it('returns valid action_items JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'action_items' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(Array.isArray(parsed.actionItems)).toBe(true);
    for (const item of parsed.actionItems) {
      expect(item.assigneeRole).toBeTruthy();
      expect(item.text).toBeTruthy();
      expect(typeof item.dueOffsetDays).toBe('number');
    }
  });

  it('returns valid draft_minutes JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'draft_minutes' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(parsed.draftMinutes).toContain('# Meeting Minutes');
  });

  it('tracks usage stats', async () => {
    await provider.generate({
      modelId: 'mock',
      messages: [{ role: 'system', content: 'test' }, { role: 'user', content: 'hello' }],
    });
    const stats = provider.getUsageStats();
    expect(stats.totalRequests).toBe(1);
    expect(stats.totalTokensIn).toBeGreaterThan(0);
    expect(stats.totalTokensOut).toBeGreaterThan(0);
    expect(stats.totalCostUsd).toBe(0); // mock is free
  });
});
