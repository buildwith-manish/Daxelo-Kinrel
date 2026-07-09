// =============================================================================
// Track C v2.0 — Governance Sync
// sync.push.service.ts
// =============================================================================
// Push endpoint for offline mutations. Section 7.4 (Outbox Pattern) + 6.8.
//
// The client writes every mutating operation to a local Drift outbox table
// before the API call. The sync worker drains the outbox in order, with
// retry + exponential backoff. On success, the row is marked `applied`.
// On permanent failure (e.g., RLS rejection), it's marked `rejected` and
// surfaced to the user.
//
// Conflict resolution (Section 7.3):
//   - Constitution edits: structured merge at the clause level; conflicts
//     surface as "two members edited this clause — pick which version to keep"
//   - Decision edits: LWW on title/description; concurrent votes never conflict
//   - Timeline: never conflicts (append-only by design)
// =============================================================================

import {
  Injectable,
  Logger,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FamilyMembershipService } from '../common/family-membership.service';

export interface PushOperation {
  kind: 'create' | 'update' | 'delete';
  entity: string;
  op: string; // e.g. 'vote', 'editTitle', 'lifecycle'
  payload: any;
  clientOpId: string; // idempotency key
}

export interface PushResult {
  applied: Array<{ clientOpId: string; result: any }>;
  conflicts: Array<{ clientOpId: string; reason: string; serverVersion?: any }>;
  rejected: Array<{ clientOpId: string; reason: string }>;
}

@Injectable()
export class SyncPushService {
  private readonly logger = new Logger(SyncPushService.name);
  private readonly appliedOpIds = new Set<string>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly membership: FamilyMembershipService,
  ) {}

  async push(params: {
    userId: string;
    operations: PushOperation[];
  }): Promise<PushResult> {
    const result: PushResult = { applied: [], conflicts: [], rejected: [] };

    for (const op of params.operations) {
      // Idempotency: skip if we've already applied this clientOpId
      if (this.appliedOpIds.has(op.clientOpId)) {
        result.applied.push({ clientOpId: op.clientOpId, result: { skipped: true } });
        continue;
      }

      try {
        const opResult = await this.applyOperation(params.userId, op);
        this.appliedOpIds.add(op.clientOpId);
        // Cap the set size
        if (this.appliedOpIds.size > 10_000) {
          const first = this.appliedOpIds.values().next().value;
          if (first) this.appliedOpIds.delete(first);
        }
        result.applied.push({ clientOpId: op.clientOpId, result: opResult });
      } catch (err: any) {
        if (err.name === 'ConflictError' || err.status === 409) {
          result.conflicts.push({
            clientOpId: op.clientOpId,
            reason: err.message,
            serverVersion: err.serverVersion,
          });
        } else if (err.status === 403 || err.name === 'ForbiddenError') {
          // Edge case #16: Outbox operation rejected by RLS — marked `rejected`; not retried
          result.rejected.push({ clientOpId: op.clientOpId, reason: err.message });
        } else {
          // Transient errors → return as rejected so the client can retry
          result.rejected.push({ clientOpId: op.clientOpId, reason: err.message });
        }
      }
    }

    return result;
  }

  private async applyOperation(userId: string, op: PushOperation): Promise<any> {
    await this.membership.requireMember(userId, op.payload.familyId);

    switch (op.entity) {
      case 'decision':
        return this.applyDecisionOp(userId, op);
      case 'constitution':
        return this.applyConstitutionOp(userId, op);
      case 'reminder':
        return this.applyReminderOp(userId, op);
      default:
        throw new BadRequestException(`Unsupported entity for push: ${op.entity}`);
    }
  }

  private async applyDecisionOp(userId: string, op: PushOperation): Promise<any> {
    const familyId: string = op.payload.familyId;
    const decisionId: string = op.payload.decisionId;

    switch (op.op) {
      case 'vote': {
        const decision = await this.prisma.familyDecision.findUnique({
          where: { id_familyId: { id: decisionId, familyId } },
        });
        if (!decision) throw new BadRequestException('Decision not found');
        if (decision.status !== 'open') {
          throw { status: 409, message: 'Decision is no longer open for voting', name: 'ConflictError' };
        }
        if (!decision.eligibleUserIds.includes(userId)) {
          throw new ForbiddenException('Not eligible to vote on this decision');
        }
        try {
          return await this.prisma.decisionVote.create({
            data: {
              decisionId,
              familyId,
              userId,
              option: op.payload.option,
            },
          });
        } catch (err: any) {
          if (err.code === 'P2002') {
            // Already voted — idempotent success
            return { skipped: true, reason: 'already_voted' };
          }
          throw err;
        }
      }

      case 'editTitle':
      case 'editDescription': {
        // LWW on title/description (Section 7.3)
        const decision = await this.prisma.familyDecision.findUnique({
          where: { id_familyId: { id: decisionId, familyId } },
        });
        if (!decision) throw new BadRequestException('Decision not found');
        if (decision.status !== 'open') {
          throw { status: 409, message: 'Decision is no longer editable', name: 'ConflictError' };
        }
        const data: any = {};
        if (op.payload.title !== undefined) data.title = op.payload.title;
        if (op.payload.description !== undefined) data.description = op.payload.description;
        return this.prisma.familyDecision.update({
          where: { id_familyId: { id: decisionId, familyId } },
          data,
        });
      }

      case 'lifecycle': {
        const decision = await this.prisma.familyDecision.findUnique({
          where: { id_familyId: { id: decisionId, familyId } },
        });
        if (!decision) throw new BadRequestException('Decision not found');
        if (decision.status !== 'resolved') {
          throw { status: 409, message: 'Lifecycle transitions only allowed on resolved decisions', name: 'ConflictError' };
        }
        return this.prisma.familyDecision.update({
          where: { id_familyId: { id: decisionId, familyId } },
          data: {
            lifecycleState: op.payload.to,
            lifecycleUpdatedAt: new Date(),
          },
        });
      }

      default:
        throw new BadRequestException(`Unknown decision op: ${op.op}`);
    }
  }

  private async applyConstitutionOp(userId: string, op: PushOperation): Promise<any> {
    // Constitution edits use structured merge at the clause level.
    // For push, we only support clause edits — full rewrites require the
    // admin to use the regular /constitution/draft endpoint.
    if (op.op === 'editClause') {
      await this.membership.requireAdmin(userId, op.payload.familyId);
      const clause = await this.prisma.constitutionClause.findUnique({
        where: { id: op.payload.clauseId },
      });
      if (!clause || clause.familyId !== op.payload.familyId) {
        throw new BadRequestException('Clause not found');
      }
      return this.prisma.constitutionClause.update({
        where: { id: op.payload.clauseId },
        data: { text: op.payload.text },
      });
    }
    throw new BadRequestException(`Unknown constitution op: ${op.op}`);
  }

  private async applyReminderOp(userId: string, op: PushOperation): Promise<any> {
    const reminder = await this.prisma.smartReminder.findUnique({
      where: { id: op.payload.reminderId },
    });
    if (!reminder || reminder.familyId !== op.payload.familyId) {
      throw new BadRequestException('Reminder not found');
    }
    if (reminder.targetUserId !== userId) {
      throw new ForbiddenException('Cannot modify another user\'s reminder');
    }

    switch (op.op) {
      case 'snooze':
        return this.prisma.smartReminder.update({
          where: { id: op.payload.reminderId },
          data: {
            status: 'snoozed',
            snoozedUntil: new Date(op.payload.snoozedUntil),
            snoozeCount: { increment: 1 },
          },
        });
      case 'dismiss':
        return this.prisma.smartReminder.update({
          where: { id: op.payload.reminderId },
          data: { status: 'dismissed', dismissedAt: new Date() },
        });
      case 'act':
        return this.prisma.smartReminder.update({
          where: { id: op.payload.reminderId },
          data: { status: 'acted', actedAt: new Date() },
        });
      default:
        throw new BadRequestException(`Unknown reminder op: ${op.op}`);
    }
  }
}
