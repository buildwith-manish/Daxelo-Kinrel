// =============================================================================
// Track C v2.0 — Decisions State Machine Tests
// =============================================================================
// Property-based tests for the pure state machine functions.
// Section 14.2 + 14.3 mandatory coverage.
// =============================================================================

import {
  assertCanTransitionStatus,
  assertCanTransitionLifecycle,
  assertCanVote,
  computeQuorum,
  validateDeadline,
  validateQuorumPct,
  assertCanChangeType,
  DecisionContext,
  DecisionType,
} from './decisions.state-machine';
import { ConflictException, BadRequestException } from '@nestjs/common';

describe('DecisionsStateMachine', () => {
  describe('assertCanTransitionStatus', () => {
    it('allows open → resolved', () => {
      expect(() => assertCanTransitionStatus('open', 'resolved')).not.toThrow();
    });

    it('allows open → expired', () => {
      expect(() => assertCanTransitionStatus('open', 'expired')).not.toThrow();
    });

    it('allows open → cancelled', () => {
      expect(() => assertCanTransitionStatus('open', 'cancelled')).not.toThrow();
    });

    it('rejects resolved → open (terminal state)', () => {
      expect(() => assertCanTransitionStatus('resolved', 'open')).toThrow(ConflictException);
    });

    it('rejects expired → resolved', () => {
      expect(() => assertCanTransitionStatus('expired', 'resolved')).toThrow(ConflictException);
    });

    it('rejects cancelled → any', () => {
      expect(() => assertCanTransitionStatus('cancelled', 'open')).toThrow(ConflictException);
      expect(() => assertCanTransitionStatus('cancelled', 'resolved')).toThrow(ConflictException);
    });
  });

  describe('assertCanVote', () => {
    const baseCtx: DecisionContext = {
      type: 'simple_vote',
      status: 'open',
      lifecycleState: null,
      deadlineAt: new Date(Date.now() + 86400_000), // 24h from now
      resolvedAt: null,
      quorumPct: 50,
    };

    it('allows voting on an open decision before deadline', () => {
      expect(() => assertCanVote(baseCtx)).not.toThrow();
    });

    it('rejects voting on a resolved decision (edge case #9)', () => {
      expect(() => assertCanVote({ ...baseCtx, status: 'resolved' })).toThrow(ConflictException);
    });

    it('rejects voting on an expired decision (edge case #8)', () => {
      expect(() => assertCanVote({ ...baseCtx, status: 'expired' })).toThrow(ConflictException);
    });

    it('rejects voting after deadline', () => {
      const pastDeadline: DecisionContext = {
        ...baseCtx,
        deadlineAt: new Date(Date.now() - 1000),
      };
      expect(() => assertCanVote(pastDeadline)).toThrow(ConflictException);
    });
  });

  describe('assertCanTransitionLifecycle', () => {
    it('allows null → planned (first lifecycle assignment)', () => {
      expect(() => assertCanTransitionLifecycle(null, 'planned')).not.toThrow();
    });

    it('rejects null → started (must start with planned)', () => {
      expect(() => assertCanTransitionLifecycle(null, 'started')).toThrow(ConflictException);
    });

    it('allows planned → started', () => {
      expect(() => assertCanTransitionLifecycle('planned', 'started')).not.toThrow();
    });

    it('allows started → in_progress', () => {
      expect(() => assertCanTransitionLifecycle('started', 'in_progress')).not.toThrow();
    });

    it('allows in_progress → completed', () => {
      expect(() => assertCanTransitionLifecycle('in_progress', 'completed')).not.toThrow();
    });

    it('allows any non-terminal → cancelled', () => {
      expect(() => assertCanTransitionLifecycle('planned', 'cancelled')).not.toThrow();
      expect(() => assertCanTransitionLifecycle('started', 'cancelled')).not.toThrow();
      expect(() => assertCanTransitionLifecycle('in_progress', 'cancelled')).not.toThrow();
    });

    it('allows any → archived', () => {
      expect(() => assertCanTransitionLifecycle('completed', 'archived')).not.toThrow();
      expect(() => assertCanTransitionLifecycle('cancelled', 'archived')).not.toThrow();
      expect(() => assertCanTransitionLifecycle('expired', 'archived')).not.toThrow();
    });

    it('rejects archived → any (terminal)', () => {
      expect(() => assertCanTransitionLifecycle('archived', 'planned')).toThrow(ConflictException);
      expect(() => assertCanTransitionLifecycle('archived', 'completed')).toThrow(ConflictException);
    });

    it('rejects completed → in_progress (no backward)', () => {
      expect(() => assertCanTransitionLifecycle('completed', 'in_progress')).toThrow(ConflictException);
    });
  });

  describe('computeQuorum — property tests', () => {
    // Property: quorumMet requires voteCount >= ceil(eligibleCount * quorumPct / 100)
    it('quorum met when voteCount >= required threshold', () => {
      const result = computeQuorum({
        type: 'simple_vote',
        eligibleCount: 10,
        voteCount: 5,
        quorumPct: 50,
        voteTallies: { yes: 3, no: 2 },
      });
      expect(result.quorumMet).toBe(true);
    });

    it('quorum NOT met when voteCount < required threshold', () => {
      const result = computeQuorum({
        type: 'simple_vote',
        eligibleCount: 10,
        voteCount: 4,
        quorumPct: 50,
        voteTallies: { yes: 2, no: 2 },
      });
      expect(result.quorumMet).toBe(false);
      expect(result.outcome).toBe('no_quorum');
    });

    it('handles zero eligible voters (edge case #2)', () => {
      const result = computeQuorum({
        type: 'simple_vote',
        eligibleCount: 0,
        voteCount: 0,
        quorumPct: 50,
        voteTallies: {},
      });
      expect(result.quorumMet).toBe(false);
      expect(result.outcome).toBe('no_quorum');
    });

    it('simple_vote: majority of cast votes wins', () => {
      const result = computeQuorum({
        type: 'simple_vote',
        eligibleCount: 10,
        voteCount: 7,
        quorumPct: 50,
        voteTallies: { yes: 5, no: 2 },
      });
      expect(result.outcome).toBe('approved');
      expect(result.winningOption).toBe('yes');
    });

    it('simple_vote: tie results in tie outcome', () => {
      const result = computeQuorum({
        type: 'simple_vote',
        eligibleCount: 10,
        voteCount: 6,
        quorumPct: 50,
        voteTallies: { yes: 3, no: 3 },
      });
      expect(result.outcome).toBe('tie');
    });

    it('consensus: requires 100% unanimous', () => {
      const approved = computeQuorum({
        type: 'consensus',
        eligibleCount: 5,
        voteCount: 5,
        quorumPct: 100,
        voteTallies: { yes: 5 },
      });
      expect(approved.outcome).toBe('approved');

      const rejected = computeQuorum({
        type: 'consensus',
        eligibleCount: 5,
        voteCount: 5,
        quorumPct: 100,
        voteTallies: { yes: 4, no: 1 },
      });
      expect(rejected.outcome).toBe('rejected');
    });

    it('elder_council: majority of elders', () => {
      const result = computeQuorum({
        type: 'elder_council',
        eligibleCount: 8, // total family
        voteCount: 0,
        quorumPct: 50,
        voteTallies: {},
        elderEligibleCount: 3,
        elderVoteTallies: { yes: 2, no: 1 },
      });
      expect(result.outcome).toBe('approved');
      expect(result.eligibleCount).toBe(3); // elders, not family total
    });

    it('constitution_amend: requires >=67% supermajority', () => {
      const approved = computeQuorum({
        type: 'constitution_amend',
        eligibleCount: 10,
        voteCount: 7, // 70% — meets quorum AND supermajority
        quorumPct: 67,
        voteTallies: { yes: 7 },
      });
      expect(approved.outcome).toBe('approved');

      const rejected = computeQuorum({
        type: 'constitution_amend',
        eligibleCount: 10,
        voteCount: 7, // meets quorum
        quorumPct: 67,
        voteTallies: { yes: 4, no: 3 }, // topCount=4 < 7 required for supermajority
      });
      expect(rejected.outcome).toBe('rejected');
    });

    // Property test: for any (eligible, votes, quorumPct) combination,
    // quorumMet should be deterministic and match the formula
    it('property: quorumMet is deterministic across all combinations', () => {
      for (let eligible = 1; eligible <= 20; eligible++) {
        for (let votes = 0; votes <= eligible; votes++) {
          for (const quorumPct of [1, 25, 50, 67, 75, 100]) {
            const result = computeQuorum({
              type: 'simple_vote',
              eligibleCount: eligible,
              voteCount: votes,
              quorumPct,
              voteTallies: votes > 0 ? { yes: votes } : {},
            });
            const required = Math.ceil((eligible * quorumPct) / 100);
            expect(result.quorumMet).toBe(votes >= required);
          }
        }
      }
    });
  });

  describe('validateDeadline', () => {
    it('rejects deadline in the past (edge case #7)', () => {
      const now = new Date();
      const past = new Date(now.getTime() - 1000);
      expect(() => validateDeadline(past, now)).toThrow(BadRequestException);
    });

    it('rejects deadline equal to createdAt', () => {
      const now = new Date();
      expect(() => validateDeadline(now, now)).toThrow(BadRequestException);
    });

    it('accepts future deadline', () => {
      const now = new Date();
      const future = new Date(now.getTime() + 86400_000);
      expect(() => validateDeadline(future, now)).not.toThrow();
    });
  });

  describe('validateQuorumPct', () => {
    it('rejects 0% (edge case #20)', () => {
      expect(() => validateQuorumPct(0)).toThrow(BadRequestException);
    });

    it('rejects negative', () => {
      expect(() => validateQuorumPct(-5)).toThrow(BadRequestException);
    });

    it('rejects > 100', () => {
      expect(() => validateQuorumPct(101)).toThrow(BadRequestException);
    });

    it('accepts 1 (minimum)', () => {
      expect(() => validateQuorumPct(1)).not.toThrow();
    });

    it('accepts 100 (maximum)', () => {
      expect(() => validateQuorumPct(100)).not.toThrow();
    });
  });

  describe('assertCanChangeType', () => {
    it('allows same type (no change)', () => {
      expect(() => assertCanChangeType('simple_vote', 'simple_vote')).not.toThrow();
    });

    it('rejects type change (edge case #19)', () => {
      expect(() => assertCanChangeType('simple_vote', 'consensus')).toThrow(ConflictException);
    });
  });
});
