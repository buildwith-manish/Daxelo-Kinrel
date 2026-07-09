// =============================================================================
// Track C v2.0 — AURA Intelligence
// intelligence.cost-guard.ts
// =============================================================================
// Per-family daily token budget enforcement. Section 8.3 + 2.3.
//
// Default budget: 50,000 tokens/day per family (configurable per tier).
// When budget is exhausted, AI endpoints return 429 with `degraded_mode = true`
// and cached insights are still served.
//
// The cost guard is a transactional upsert against the AICostBudget table:
//   - INSERT if no row exists for (familyId, today_utc)
//   - Otherwise UPDATE tokensUsed += N, costUsd += C
//
// Idempotency: the caller provides a `requestId`; the guard rejects duplicate
// charges for the same requestId.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export class BudgetExhaustedError extends Error {
  constructor(familyId: string, used: number, budget: number) {
    super(`AI daily budget exhausted for family ${familyId}: ${used}/${budget} tokens used`);
    this.name = 'BudgetExhaustedError';
  }
}

@Injectable()
export class CostGuard {
  private readonly logger = new Logger(CostGuard.name);
  private readonly chargedRequestIds = new Set<string>();
  private readonly DEFAULT_DAILY_BUDGET = 50_000;

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Check if a family has budget remaining. Does NOT charge.
   * Use `charge` after a successful LLM call to record usage.
   */
  async checkBudget(familyId: string, now: Date = new Date()): Promise<{
    remaining: number;
    used: number;
    budget: number;
    exhausted: boolean;
  }> {
    const dateUtc = this.utcDate(now);
    const row = await this.prisma.aICostBudget.findUnique({
      where: { familyId_dateUtc: { familyId, dateUtc } },
    });
    const used = row?.tokensUsed ?? 0;
    const budget = row?.budgetTokens ?? this.DEFAULT_DAILY_BUDGET;
    const remaining = Math.max(0, budget - used);
    return { remaining, used, budget, exhausted: remaining === 0 };
  }

  /**
   * Record usage after a successful LLM call. Idempotent per requestId.
   * Throws BudgetExhaustedError if usage would exceed budget.
   */
  async charge(params: {
    familyId: string;
    tokensIn: number;
    tokensOut: number;
    costUsd: number;
    requestId: string;
    now?: Date;
  }): Promise<void> {
    // Idempotency: skip if we've already charged this requestId
    if (this.chargedRequestIds.has(params.requestId)) return;
    this.chargedRequestIds.add(params.requestId);

    // Cap the set size (evict oldest ~arbitrary; in production use Redis with TTL)
    if (this.chargedRequestIds.size > 10_000) {
      const first = this.chargedRequestIds.values().next().value;
      if (first) this.chargedRequestIds.delete(first);
    }

    const now = params.now ?? new Date();
    const dateUtc = this.utcDate(now);
    const totalTokens = params.tokensIn + params.tokensOut;

    // Upsert the daily budget row, incrementing atomically.
    // We check BEFORE incrementing to allow one final over-budget call (so
    // cached-only mode kicks in cleanly) — but reject subsequent calls.
    const existing = await this.prisma.aICostBudget.findUnique({
      where: { familyId_dateUtc: { familyId: params.familyId, dateUtc } },
    });

    const budget = existing?.budgetTokens ?? this.DEFAULT_DAILY_BUDGET;
    const used = existing?.tokensUsed ?? 0;

    if (used >= budget) {
      throw new BudgetExhaustedError(params.familyId, used, budget);
    }

    await this.prisma.aICostBudget.upsert({
      where: { familyId_dateUtc: { familyId: params.familyId, dateUtc } },
      create: {
        familyId: params.familyId,
        dateUtc,
        tokensUsed: totalTokens,
        costUsd: params.costUsd,
        budgetTokens: budget,
      },
      update: {
        tokensUsed: { increment: totalTokens },
        costUsd: { increment: params.costUsd },
      },
    });
  }

  /**
   * Open the circuit manually (e.g., when LLM provider returns 5xx consistently
   * outside the breaker's own detection window).
   */
  async openCircuit(familyId: string, reason: string, now: Date = new Date()): Promise<void> {
    const dateUtc = this.utcDate(now);
    await this.prisma.aICostBudget.upsert({
      where: { familyId_dateUtc: { familyId, dateUtc } },
      create: {
        familyId,
        dateUtc,
        circuitOpen: true,
        circuitOpenedAt: now,
        budgetTokens: this.DEFAULT_DAILY_BUDGET,
      },
      update: {
        circuitOpen: true,
        circuitOpenedAt: now,
      },
    });
    this.logger.warn(`AI circuit opened for family ${familyId}: ${reason}`);
  }

  async closeCircuit(familyId: string, now: Date = new Date()): Promise<void> {
    const dateUtc = this.utcDate(now);
    await this.prisma.aICostBudget.updateMany({
      where: { familyId, dateUtc, circuitOpen: true },
      data: { circuitOpen: false, circuitOpenedAt: null },
    });
  }

  async isCircuitOpen(familyId: string, now: Date = new Date()): Promise<boolean> {
    const dateUtc = this.utcDate(now);
    const row = await this.prisma.aICostBudget.findUnique({
      where: { familyId_dateUtc: { familyId, dateUtc } },
    });
    return row?.circuitOpen ?? false;
  }

  private utcDate(d: Date): Date {
    return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  }
}
