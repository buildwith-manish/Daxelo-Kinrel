// =============================================================================
// Track C v2.0 — AURA Governance: Decisions
// decisions.state-machine.ts
// =============================================================================
// Pure functions for the decision state machine. Section 10.2 + 10.3.
//
// Active state machine (status field):
//   open ── deadline passes ──▶ expired
//   open ── vote resolves ────▶ resolved
//   open ── cancel ───────────▶ cancelled
//
// Post-resolution state machine (lifecycleState field, NULL until resolved):
//   planned → started → in_progress → completed
//                                  ↘ cancelled
//                                  ↘ expired (no action in 90d)
//                                  ↘ archived (>2yr)
//
// Pure functions make the state machine trivially unit-testable.
// =============================================================================

import { BadRequestException, ConflictException } from '@nestjs/common';

export type DecisionStatus = 'open' | 'resolved' | 'expired' | 'cancelled';
export type LifecycleState =
  | 'planned'
  | 'started'
  | 'in_progress'
  | 'completed'
  | 'cancelled'
  | 'expired'
  | 'archived';

export type DecisionType =
  | 'simple_vote'
  | 'consensus'
  | 'elder_council'
  | 'constitution_amend';

export interface DecisionContext {
  type: DecisionType;
  status: DecisionStatus;
  lifecycleState: LifecycleState | null;
  deadlineAt: Date;
  resolvedAt: Date | null;
  quorumPct: number;
}

// ── Active state transitions (status field) ───────────────────────────────

const ALLOWED_STATUS_TRANSITIONS: Record<DecisionStatus, DecisionStatus[]> = {
  open: ['resolved', 'expired', 'cancelled'],
  resolved: [], // terminal — only lifecycleState can change
  expired: [],
  cancelled: [],
};

export function assertCanTransitionStatus(
  from: DecisionStatus,
  to: DecisionStatus,
): void {
  const allowed = ALLOWED_STATUS_TRANSITIONS[from];
  if (!allowed?.includes(to)) {
    throw new ConflictException(
      `Cannot transition decision status from '${from}' to '${to}'`,
    );
  }
}

export function assertCanVote(ctx: DecisionContext, now: Date = new Date()): void {
  if (ctx.status !== 'open') {
    // Edge case #9: Vote after resolution → 409 Conflict
    // Edge case #8: Vote after deadline → 410 Gone (mapped to Conflict here)
    if (ctx.status === 'resolved') {
      throw new ConflictException('Cannot vote — decision is already resolved');
    }
    if (ctx.status === 'expired') {
      throw new ConflictException('Cannot vote — deadline has passed (410 Gone)');
    }
    throw new ConflictException(`Cannot vote — decision status is '${ctx.status}'`);
  }
  if (ctx.deadlineAt <= now) {
    throw new ConflictException('Cannot vote — deadline has passed');
  }
}

// ── Lifecycle state transitions (lifecycleState field) ────────────────────

const ALLOWED_LIFECYCLE_TRANSITIONS: Record<LifecycleState, LifecycleState[]> = {
  planned: ['started', 'cancelled', 'expired', 'archived'],
  started: ['in_progress', 'cancelled', 'expired', 'archived'],
  in_progress: ['completed', 'cancelled', 'expired', 'archived'],
  completed: ['archived'],
  cancelled: ['archived'],
  expired: ['archived'],
  archived: [],
};

export function assertCanTransitionLifecycle(
  from: LifecycleState | null,
  to: LifecycleState,
): void {
  if (from === null) {
    // First lifecycle assignment — only allowed right after resolution
    if (to !== 'planned') {
      throw new ConflictException(
        `First lifecycle state must be 'planned' (got '${to}')`,
      );
    }
    return;
  }
  const allowed = ALLOWED_LIFECYCLE_TRANSITIONS[from];
  if (!allowed?.includes(to)) {
    throw new ConflictException(
      `Cannot transition lifecycle from '${from}' to '${to}'`,
    );
  }
}

// ── Quorum calculation ────────────────────────────────────────────────────

export interface QuorumResult {
  eligibleCount: number;
  voteCount: number;
  quorumPct: number;
  quorumMet: boolean;
  /** For simple_vote: majority of cast votes. For consensus: 100%. For elder_council: majority of elders. For amend: supermajority. */
  passCriterionMet: boolean;
  outcome: 'approved' | 'rejected' | 'no_quorum' | 'tie';
  winningOption?: string;
}

/**
 * Compute whether quorum is met and whether the pass criterion is satisfied.
 * Pure function — trivially property-testable (Section 14.3).
 */
export function computeQuorum(params: {
  type: DecisionType;
  eligibleCount: number;
  voteCount: number;
  quorumPct: number;
  /** Map of option → count of votes for that option */
  voteTallies: Record<string, number>;
  elderEligibleCount?: number; // for elder_council
  elderVoteTallies?: Record<string, number>;
}): QuorumResult {
  const { type, eligibleCount, voteCount, quorumPct, voteTallies } = params;

  if (eligibleCount === 0) {
    return {
      eligibleCount: 0,
      voteCount: 0,
      quorumPct,
      quorumMet: false,
      passCriterionMet: false,
      outcome: 'no_quorum',
    };
  }

  const requiredVotes = Math.ceil((eligibleCount * quorumPct) / 100);
  const quorumMet = voteCount >= requiredVotes;

  if (!quorumMet) {
    return {
      eligibleCount,
      voteCount,
      quorumPct,
      quorumMet: false,
      passCriterionMet: false,
      outcome: 'no_quorum',
    };
  }

  // Determine winning option by majority of cast votes
  const sorted = Object.entries(voteTallies).sort((a, b) => b[1] - a[1]);
  const [topOption, topCount] = sorted[0] ?? ['', 0];
  const [secondOption, secondCount] = sorted[1] ?? ['', 0];
  const isTie = topCount === secondCount && topCount > 0;

  let passCriterionMet = false;
  let outcome: QuorumResult['outcome'] = 'tie';

  switch (type) {
    case 'simple_vote':
      // majority of cast votes
      passCriterionMet = !isTie && topCount > voteCount / 2;
      outcome = passCriterionMet ? 'approved' : isTie ? 'tie' : 'rejected';
      break;

    case 'consensus':
      // 100% of eligible (unanimous). All eligible must vote the same way.
      passCriterionMet = voteCount === eligibleCount && sorted.length === 1 && topCount === eligibleCount;
      outcome = passCriterionMet ? 'approved' : 'rejected';
      break;

    case 'elder_council': {
      // majority of elders
      const elderEligible = params.elderEligibleCount ?? eligibleCount;
      const elderTallies = params.elderVoteTallies ?? voteTallies;
      const elderVotes = Object.values(elderTallies).reduce((a, b) => a + b, 0);
      const elderSorted = Object.entries(elderTallies).sort((a, b) => b[1] - a[1]);
      const [elderTop, elderTopCount] = elderSorted[0] ?? ['', 0];
      passCriterionMet = elderVotes > 0 && elderTopCount > elderVotes / 2;
      outcome = passCriterionMet ? 'approved' : 'rejected';
      return {
        eligibleCount: elderEligible,
        voteCount: elderVotes,
        quorumPct,
        quorumMet: elderVotes >= Math.ceil((elderEligible * quorumPct) / 100),
        passCriterionMet,
        outcome,
        winningOption: passCriterionMet ? elderTop : undefined,
      };
    }

    case 'constitution_amend':
      // supermajority (>=67% of eligible)
      passCriterionMet = !isTie && topCount >= Math.ceil((eligibleCount * 67) / 100);
      outcome = passCriterionMet ? 'approved' : 'rejected';
      break;
  }

  return {
    eligibleCount,
    voteCount,
    quorumPct,
    quorumMet,
    passCriterionMet,
    outcome,
    winningOption: passCriterionMet ? topOption : undefined,
  };
}

// ── Validation helpers ────────────────────────────────────────────────────

export function validateDeadline(deadlineAt: Date, createdAt: Date = new Date()): void {
  if (deadlineAt <= createdAt) {
    // Edge case #7: Decision deadline in the past — rejected at API layer with 400
    throw new BadRequestException('Decision deadline must be in the future');
  }
}

export function validateQuorumPct(quorumPct: number): void {
  // Edge case #20: Quorum set to 0% — rejected at API layer with 400 (min 1%)
  if (quorumPct < 1 || quorumPct > 100) {
    throw new BadRequestException('quorumPct must be between 1 and 100');
  }
}

export function assertCanChangeType(currentType: DecisionType, newType: DecisionType): void {
  // Edge case #19: Decision type changed mid-flight — not allowed (409)
  if (currentType !== newType) {
    throw new ConflictException('Decision type cannot be changed after creation');
  }
}
