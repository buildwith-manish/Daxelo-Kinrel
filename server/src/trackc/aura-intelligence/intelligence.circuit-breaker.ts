// =============================================================================
// Track C v2.0 — AURA Intelligence
// intelligence.circuit-breaker.ts
// =============================================================================
// Circuit breaker for the LLM provider. ADR-005.
//
// Behavior:
//   - Tracks recent LLM call outcomes in a sliding 60-second window.
//   - If error rate exceeds 10% over the last 60s, the breaker OPENS for 5 min.
//   - While OPEN, all requests fail fast with a DegradedModeError.
//   - After 5 min, the breaker moves to HALF_OPEN: one trial request is allowed.
//   - If the trial succeeds, the breaker CLOSES. If it fails, it re-OPENS.
//
// Section 2 operating rule #4: If the upstream LLM provider error rate
// exceeds 10% over 60s, AI features auto-disable for 5 minutes and a
// `degraded_mode` flag is returned to clients.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';

export class DegradedModeError extends Error {
  constructor(message = 'AI features are in degraded mode (circuit breaker open)') {
    super(message);
    this.name = 'DegradedModeError';
  }
}

interface CallOutcome {
  timestamp: number;
  success: boolean;
}

@Injectable()
export class CircuitBreaker {
  private readonly logger = new Logger(CircuitBreaker.name);
  private outcomes: CallOutcome[] = [];
  private state: 'closed' | 'open' | 'half_open' = 'closed';
  private openedAt: number | null = null;

  // Configuration (Section 2 rule #4)
  private readonly windowMs = 60_000;
  private readonly errorThresholdPct = 0.10;
  private readonly openDurationMs = 5 * 60_000;
  private readonly minCallsBeforeTrip = 5;

  /**
   * Wrap an async function call with circuit-breaker protection.
   * Throws DegradedModeError if the breaker is OPEN.
   */
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    this.maybeRecover();

    if (this.state === 'open') {
      throw new DegradedModeError();
    }

    try {
      const result = await fn();
      this.recordOutcome(true);
      // If we were in half_open and the trial succeeded, close.
      if (this.state === 'half_open') {
        this.state = 'closed';
        this.logger.log('Circuit breaker CLOSED (trial succeeded)');
      }
      return result;
    } catch (err) {
      // Don't trip on DegradedModeError (it's our own)
      if (err instanceof DegradedModeError) throw err;
      this.recordOutcome(false);
      throw err;
    }
  }

  isOpen(): boolean {
    this.maybeRecover();
    return this.state === 'open';
  }

  getState(): 'closed' | 'open' | 'half_open' {
    this.maybeRecover();
    return this.state;
  }

  private recordOutcome(success: boolean): void {
    const now = Date.now();
    this.outcomes.push({ timestamp: now, success });
    // Prune old outcomes outside the window
    this.outcomes = this.outcomes.filter((o) => now - o.timestamp < this.windowMs);

    if (this.state === 'half_open') {
      // Trial failed — reopen
      if (!success) {
        this.trip();
      }
      return;
    }

    // Only trip if we have enough calls to be statistically meaningful
    if (this.outcomes.length < this.minCallsBeforeTrip) return;

    const failures = this.outcomes.filter((o) => !o.success).length;
    const errorRate = failures / this.outcomes.length;

    if (errorRate >= this.errorThresholdPct) {
      this.trip();
    }
  }

  private trip(): void {
    if (this.state === 'open') return;
    this.state = 'open';
    this.openedAt = Date.now();
    this.logger.warn(
      `Circuit breaker OPENED — LLM error rate exceeded ${this.errorThresholdPct * 100}% over last ${this.windowMs / 1000}s. Auto-recovering in ${this.openDurationMs / 1000}s.`,
    );
  }

  private maybeRecover(): void {
    if (this.state === 'open' && this.openedAt !== null) {
      if (Date.now() - this.openedAt >= this.openDurationMs) {
        this.state = 'half_open';
        this.openedAt = null;
        this.outcomes = []; // fresh window
        this.logger.log('Circuit breaker HALF_OPEN — next call is a trial');
      }
    }
  }
}
