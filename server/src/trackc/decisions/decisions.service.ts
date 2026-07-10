// =============================================================================
// Track C v2.0 — AURA Governance: Decisions
// decisions.service.ts
// =============================================================================
// Implements Section 6.2 (decision endpoints) + Section 10.2 (workflows) +
// Section 10.3 (lifecycle) of the FINAL v2.0 spec.
// =============================================================================

import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { ConstitutionService } from '../constitution/constitution.service';
import {
  DecisionType,
  assertCanVote,
  assertCanTransitionStatus,
  assertCanTransitionLifecycle,
  computeQuorum,
  validateDeadline,
  validateQuorumPct,
  assertCanChangeType,
} from './decisions.state-machine';

export interface CreateDecisionInput {
  title: string;
  description?: string;
  type: DecisionType;
  options: string[];
  eligibleUserIds?: string[]; // default: all active members
  quorumPct?: number;
  showVotesLive?: boolean;
  deadlineAt: string; // ISO
  constitutionVersionId?: string;
}

@Injectable()
export class DecisionsService {
  private readonly logger = new Logger(DecisionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emitter: TimelineEmitter,
    private readonly membership: FamilyMembershipService,
    private readonly constitutionService: ConstitutionService,
  ) {}

  async list(
    familyId: string,
    opts: { status?: string; cursor?: string; limit?: number; lifecycleState?: string } = {},
  ) {
    const limit = Math.min(Math.max(opts.limit ?? 50, 1), 100);
    const items = await this.prisma.familyDecision.findMany({
      where: {
        familyId,
        ...(opts.status ? { status: opts.status } : {}),
        ...(opts.lifecycleState ? { lifecycleState: opts.lifecycleState } : {}),
        ...(opts.cursor ? { updatedAt: { lt: new Date(opts.cursor) } } : {}),
      },
      orderBy: { updatedAt: 'desc' },
      take: limit + 1,
    });
    const hasNext = items.length > limit;
    const page = hasNext ? items.slice(0, limit) : items;
    return {
      items: page,
      nextCursor: hasNext && page.length > 0 ? page[page.length - 1].updatedAt.toISOString() : null,
      hasNext,
    };
  }

  async getOne(familyId: string, decisionId: string) {
    const decision = await this.prisma.familyDecision.findUnique({
      where: { id_familyId: { id: decisionId, familyId } },
      include: {
        votes: true,
        memory: true,
        impacts: { orderBy: { createdAt: 'asc' } },
      },
    });
    if (!decision) throw new NotFoundException('Decision not found');
    return decision;
  }

  async create(familyId: string, actorId: string, input: CreateDecisionInput) {
    await this.membership.requireMember(actorId, familyId);

    if (!input.title?.trim()) throw new BadRequestException('title is required');
    if (!input.options?.length) throw new BadRequestException('options must be non-empty');

    // Edge case #22: Elder council with no elders defined
    if (input.type === 'elder_council') {
      const elders = await this.membership.getElderUserIds(familyId);
      if (!elders.length) {
        throw new BadRequestException('No elders defined. Define elders before opening an elder council decision.');
      }
      input.eligibleUserIds = elders;
    }

    // Edge case #20: Quorum set to 0%
    validateQuorumPct(input.quorumPct ?? 50);

    // Edge case #7: Deadline in past
    const deadline = new Date(input.deadlineAt);
    validateDeadline(deadline);

    // Default eligible = all active members
    const eligibleUserIds = input.eligibleUserIds ?? (await this.membership.getActiveMemberUserIds(familyId));
    if (!eligibleUserIds.length) {
      throw new BadRequestException('No eligible voters in family');
    }

    const decision = await this.prisma.familyDecision.create({
      data: {
        familyId,
        createdById: actorId,
        title: input.title,
        description: input.description,
        type: input.type,
        status: 'open',
        options: input.options,
        eligibleUserIds,
        quorumPct: input.quorumPct ?? 50,
        showVotesLive: input.showVotesLive ?? false,
        deadlineAt: deadline,
        constitutionVersionId: input.constitutionVersionId,
      },
    });

    await this.emitter.append({
      familyId,
      kind: 'decision_created',
      actorId,
      targetEntityType: 'FamilyDecision',
      targetEntityId: decision.id,
      title: `Decision opened: ${decision.title}`,
      payload: { decisionId: decision.id, type: decision.type, deadlineAt: decision.deadlineAt.toISOString() },
    });

    return decision;
  }

  async patch(
    familyId: string,
    decisionId: string,
    actorId: string,
    patch: { title?: string; description?: string; deadlineAt?: string },
  ) {
    await this.membership.requireMember(actorId, familyId);
    const decision = await this.getOne(familyId, decisionId);

    if (decision.status !== 'open') {
      throw new ConflictException('Can only edit an open decision');
    }

    // Edge case #19: Decision type changed mid-flight — not allowed
    if (patch.title) {
      // OK
    }

    const data: any = {};
    if (patch.title !== undefined) data.title = patch.title;
    if (patch.description !== undefined) data.description = patch.description;
    if (patch.deadlineAt !== undefined) {
      const newDeadline = new Date(patch.deadlineAt);
      validateDeadline(newDeadline);
      data.deadlineAt = newDeadline;
    }

    return this.prisma.familyDecision.update({
      where: { id_familyId: { id: decisionId, familyId } },
      data,
    });
  }

  async vote(
    familyId: string,
    decisionId: string,
    actorId: string,
    option: string,
  ) {
    const decision = await this.getOne(familyId, decisionId);

    // Verify voter is eligible
    if (!(decision.eligibleUserIds as string[]).includes(actorId)) {
      throw new ForbiddenException('You are not an eligible voter for this decision');
    }

    // Edge case #10: Two members vote simultaneously — both succeed (append-only)
    // We rely on the UNIQUE(decisionId, userId) constraint; if a duplicate vote
    // comes in, Prisma will throw P2002.
    assertCanVote({
      type: decision.type as DecisionType,
      status: decision.status as any,
      lifecycleState: decision.lifecycleState as any,
      deadlineAt: decision.deadlineAt,
      resolvedAt: decision.resolvedAt,
      quorumPct: decision.quorumPct,
    });

    if (!(decision.options as string[]).includes(option)) {
      throw new BadRequestException(`'${option}' is not a valid option. Valid: ${(decision.options as string[]).join(', ')}`);
    }

    try {
      const vote = await this.prisma.decisionVote.create({
        data: {
          decisionId,
          familyId,
          userId: actorId,
          option,
        },
      });

      // Emit decision_voted only if showVotesLive is true (Section 11.1)
      if (decision.showVotesLive) {
        await this.emitter.append({
          familyId,
          kind: 'decision_voted',
          actorId,
          targetEntityType: 'FamilyDecision',
          targetEntityId: decisionId,
          title: `Vote cast: ${option}`,
          payload: { decisionId, userId: actorId, option },
        });
      }

      return vote;
    } catch (err: any) {
      if (err.code === 'P2002') {
        throw new ConflictException('You have already voted on this decision');
      }
      throw err;
    }
  }

  /**
   * Resolve a decision. Computes quorum + pass criterion and sets status='resolved'.
   * Idempotent — if already resolved, returns the existing result.
   */
  async resolve(familyId: string, decisionId: string, actorId: string, resolutionNote?: string) {
    await this.membership.requireMember(actorId, familyId);
    const decision = await this.getOne(familyId, decisionId);

    if (decision.status === 'resolved') {
      return decision;
    }
    if (decision.status === 'cancelled' || decision.status === 'expired') {
      throw new ConflictException(`Cannot resolve a ${decision.status} decision`);
    }

    assertCanTransitionStatus('open', 'resolved');

    const votes = decision.votes;
    const tallies: Record<string, number> = {};
    for (const v of votes) {
      tallies[v.option] = (tallies[v.option] ?? 0) + 1;
    }

    let elderEligibleCount: number | undefined;
    let elderTallies: Record<string, number> | undefined;
    if (decision.type === 'elder_council') {
      elderEligibleCount = (decision.eligibleUserIds as string[]).length;
      elderTallies = tallies;
    }

    const result = computeQuorum({
      type: decision.type as DecisionType,
      eligibleCount: (decision.eligibleUserIds as string[]).length,
      voteCount: votes.length,
      quorumPct: decision.quorumPct,
      voteTallies: tallies,
      elderEligibleCount,
      elderVoteTallies: elderTallies,
    });

    let outcome: string;
    if (result.outcome === 'no_quorum') {
      // Quorum not met — mark as expired instead of resolved
      return this.expireInternal(familyId, decision, actorId);
    } else if (result.outcome === 'approved') {
      outcome = 'approved';
    } else if (result.outcome === 'rejected') {
      outcome = 'rejected';
    } else {
      outcome = 'tie';
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.familyDecision.update({
        where: { id_familyId: { id: decisionId, familyId } },
        data: {
          status: 'resolved',
          outcome,
          resolvedAt: new Date(),
          resolutionNote,
          lifecycleState: 'planned',
          lifecycleUpdatedAt: new Date(),
        },
      });

      await this.emitter.append({
        familyId,
        kind: 'decision_resolved',
        actorId,
        targetEntityType: 'FamilyDecision',
        targetEntityId: decisionId,
        title: `Decision resolved: ${outcome}`,
        payload: {
          decisionId,
          outcome,
          voteCount: result.voteCount,
          eligibleCount: result.eligibleCount,
        },
      });

      // ── Constitution amendment resolution hook ───────────────────────
      // Section 10.1 of the spec: when a `constitution_amend` decision
      // resolves, the constitution must be either committed (approved) or
      // discarded (rejected). Failing to do either leaves the constitution
      // permanently locked (status='in_review', draftVersionId non-null).
      //
      // We run this *inside* the same transaction so that a commit/discard
      // failure rolls back the resolution write — preventing the situation
      // where the decision is marked resolved but the constitution is still
      // locked. The constitution_amended timeline event is emitted by
      // ConstitutionService.commitAmendment itself (best-effort, never throws).
      if (decision.type === 'constitution_amend') {
        try {
          if (outcome === 'approved') {
            this.logger.log(
              `Constitution amendment approved — committing draft for family ${familyId} (decision ${decisionId})`,
            );
            await this.constitutionService.commitAmendment(
              familyId,
              decision.constitutionVersionId ?? '',
              actorId,
              tx,
              decisionId,
            );
          } else if (outcome === 'rejected' || outcome === 'tie') {
            // A tie on a binary approve/reject amendment is treated as a
            // failure to reach supermajority → discard the draft.
            this.logger.log(
              `Constitution amendment ${outcome} — discarding draft for family ${familyId} (decision ${decisionId})`,
            );
            await this.constitutionService.discardDraft(familyId, actorId, tx);
          }
        } catch (commitErr) {
          // CRITICAL: log loudly. The transaction will roll back, so the
          // decision will remain 'open' — but the operator must investigate
          // why the constitution commit/discard failed.
          this.logger.error(
            `Constitution amendment resolution failed for decision ${decisionId} (family ${familyId}, outcome ${outcome}): ${(commitErr as Error).message}`,
            (commitErr as Error).stack,
          );
          throw commitErr; // rolls back the transaction
        }
      }

      return updated;
    });
  }

  /**
   * Auto-expire a decision whose deadline has passed without reaching quorum.
   * Called by the pg-boss deadline sweeper.
   */
  async autoExpireIfPastDeadline(familyId: string, decisionId: string): Promise<boolean> {
    const decision = await this.getOne(familyId, decisionId);
    if (decision.status !== 'open') return false;
    if (decision.deadlineAt > new Date()) return false;

    await this.expireInternal(familyId, decision, null);
    return true;
  }

  private async expireInternal(familyId: string, decision: any, actorId: string | null) {
    assertCanTransitionStatus(decision.status, 'expired');
    const updated = await this.prisma.$transaction(async (tx) => {
      const row = await tx.familyDecision.update({
        where: { id_familyId: { id: decision.id, familyId } },
        data: { status: 'expired', resolvedAt: new Date() },
      });

      await this.emitter.append({
        familyId,
        kind: 'decision_expired',
        actorId,
        targetEntityType: 'FamilyDecision',
        targetEntityId: decision.id,
        title: `Decision expired: ${decision.title}`,
        payload: {
          decisionId: decision.id,
          voteCount: decision.votes?.length ?? 0,
          eligibleCount: decision.eligibleUserIds?.length ?? 0,
        },
      });

      // ── Constitution amendment expiration hook ─────────────────────
      // An expired constitution_amend decision means the family failed to
      // vote within the deadline. Per spec, the constitution must be
      // unlocked (draft discarded) — otherwise it stays locked forever.
      if (decision.type === 'constitution_amend') {
        try {
          this.logger.log(
            `Constitution amendment expired — discarding draft for family ${familyId} (decision ${decision.id})`,
          );
          await this.constitutionService.discardDraft(familyId, actorId, tx);
        } catch (discardErr) {
          this.logger.error(
            `Constitution amendment discard-on-expire failed for decision ${decision.id} (family ${familyId}): ${(discardErr as Error).message}`,
            (discardErr as Error).stack,
          );
          throw discardErr; // roll back the expiration write — operator must investigate
        }
      }

      return row;
    });

    return updated;
  }

  async cancel(familyId: string, decisionId: string, actorId: string) {
    await this.membership.requireMember(actorId, familyId);
    const decision = await this.getOne(familyId, decisionId);
    assertCanTransitionStatus(decision.status as any, 'cancelled');

    const updated = await this.prisma.familyDecision.update({
      where: { id_familyId: { id: decisionId, familyId } },
      data: { status: 'cancelled', resolvedAt: new Date() },
    });

    return updated;
  }

  async transitionLifecycle(
    familyId: string,
    decisionId: string,
    actorId: string,
    to: string,
  ) {
    await this.membership.requireMember(actorId, familyId);
    const decision = await this.getOne(familyId, decisionId);

    if (decision.status !== 'resolved') {
      throw new ConflictException('Lifecycle transitions only allowed on resolved decisions');
    }

    assertCanTransitionLifecycle(decision.lifecycleState as any, to as any);

    const updated = await this.prisma.$transaction(async (tx) => {
      const result = await tx.familyDecision.update({
        where: { id_familyId: { id: decisionId, familyId } },
        data: {
          lifecycleState: to,
          lifecycleUpdatedAt: new Date(),
        },
      });

      await this.emitter.append({
        familyId,
        kind: 'decision_lifecycle_changed',
        actorId,
        targetEntityType: 'FamilyDecision',
        targetEntityId: decisionId,
        title: `Lifecycle: ${decision.lifecycleState ?? 'null'} → ${to}`,
        payload: {
          decisionId,
          from: decision.lifecycleState,
          to,
          actorId,
        },
      });

      return result;
    });

    return updated;
  }

  // ── Decision Memory + Impact ────────────────────────────────────────────

  async getMemory(familyId: string, decisionId: string) {
    const memory = await this.prisma.decisionMemory.findUnique({
      where: { decisionId_familyId: { decisionId, familyId } },
    });
    return memory;
  }

  async upsertMemory(
    familyId: string,
    decisionId: string,
    actorId: string,
    data: {
      summaryText: string;
      keyTakeaways?: string[];
      searchKeywords?: string[];
      relatedConstitutionArticleIds?: string[];
      relatedMemoryIds?: string[];
    },
  ) {
    await this.membership.requireMember(actorId, familyId);
    await this.getOne(familyId, decisionId);

    return this.prisma.decisionMemory.upsert({
      where: { decisionId_familyId: { decisionId, familyId } },
      create: {
        familyId,
        decisionId,
        summaryText: data.summaryText,
        keyTakeaways: data.keyTakeaways ?? [],
        searchKeywords: data.searchKeywords ?? [],
        relatedConstitutionArticleIds: data.relatedConstitutionArticleIds ?? [],
        relatedMemoryIds: data.relatedMemoryIds ?? [],
      },
      update: {
        summaryText: data.summaryText,
        keyTakeaways: data.keyTakeaways ?? [],
        searchKeywords: data.searchKeywords ?? [],
        relatedConstitutionArticleIds: data.relatedConstitutionArticleIds ?? [],
        relatedMemoryIds: data.relatedMemoryIds ?? [],
      },
    });
  }

  async addImpact(
    familyId: string,
    decisionId: string,
    actorId: string,
    data: { milestoneText: string; dueDate?: string; notes?: string },
  ) {
    await this.membership.requireMember(actorId, familyId);
    await this.getOne(familyId, decisionId);

    return this.prisma.decisionImpact.create({
      data: {
        familyId,
        decisionId,
        milestoneText: data.milestoneText,
        dueDate: data.dueDate ? new Date(data.dueDate) : null,
        notes: data.notes,
      },
    });
  }

  async patchImpact(
    familyId: string,
    decisionId: string,
    impactId: string,
    actorId: string,
    patch: { milestoneText?: string; dueDate?: string; completedAt?: string; notes?: string; evidenceUrls?: string[] },
  ) {
    await this.membership.requireMember(actorId, familyId);
    const impact = await this.prisma.decisionImpact.findUnique({
      where: { id: impactId },
    });
    if (!impact || impact.familyId !== familyId || impact.decisionId !== decisionId) {
      throw new NotFoundException('Impact not found');
    }

    const data: any = {};
    if (patch.milestoneText !== undefined) data.milestoneText = patch.milestoneText;
    if (patch.dueDate !== undefined) data.dueDate = patch.dueDate ? new Date(patch.dueDate) : null;
    if (patch.completedAt !== undefined) data.completedAt = patch.completedAt ? new Date(patch.completedAt) : null;
    if (patch.notes !== undefined) data.notes = patch.notes;
    if (patch.evidenceUrls !== undefined) data.evidenceUrls = patch.evidenceUrls;

    return this.prisma.decisionImpact.update({
      where: { id: impactId },
      data,
    });
  }
}
